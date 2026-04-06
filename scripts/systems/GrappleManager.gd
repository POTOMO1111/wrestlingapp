class_name GrappleManager
extends Node

# ============================================================
#  GrappleManager.gd
#  FightManager の子ノードとして存在。
#  dominance 型グラップルシステムを管理する。
#  グループ "grapple_manager" に追加すること。
#
#  【終了条件】
#    dominance = 1.0 → 攻め側勝利: 受け側の回復不可能HPに GRAPPLE_FINISH_DAMAGE
#    dominance = 0.0 → 受け側勝利: 攻め側の回復不可能HPに GRAPPLE_FINISH_DAMAGE
#    タイムアウト    → 引き分け（ダメージなし）
#
#  【decayレート: /sec, 回復可能HP差による動的変化】
#    攻め側HP + 30 < 受け側HP : 0.5
#    攻め側HP < 受け側HP ≤ +30: 0.4
#    両者ほぼ同等（±1以内）  : 0.3
#    受け側HP < 攻め側HP ≤ +30: 0.2
#    受け側HP + 30 < 攻め側HP : 0.1
# ============================================================

var grapple_initiator:    Node       = null
var grapple_receiver:     Node       = null
var active_grapple_data:  GrappleData = null

# dominance: 0.0〜1.0（1.0に近いほど攻め側有利）
var dominance: float = 0.5

const DOMINANCE_GAIN_PER_INPUT: float = 0.08
const GRAPPLE_FINISH_DAMAGE:    float = 20.0   # 勝敗決定時の永続ダメージ
const HP_EQUAL_EPSILON:         float = 1.0    # 「HP等しい」とみなす閾値
const GRAPPLE_CAM_FOV:          float = 55.0   # グラップルカメラの視野角

var _initiator_input_this_frame: bool  = false
var _receiver_input_this_frame:  bool  = false
var _grapple_camera:             Camera3D = null  # グラップル専用サイドカメラ
var is_active: bool = false

signal grapple_ended(winner: Node, loser: Node)
signal dominance_changed(new_dominance: float)

func _ready() -> void:
	add_to_group("grapple_manager")

func _physics_process(delta: float) -> void:
	if not is_active:
		return
	_process_dominance(delta)
	_reset_frame_inputs()

# ----------------------------------------------------------
# テキストエフェクト（旧 GrappleSystem._spawn_text_effect の後継）
# ----------------------------------------------------------
func spawn_text_effect(text: String, pos: Vector3, color: Color = Color.WHITE) -> void:
	var label := Label3D.new()
	label.text = text
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.pixel_size = 0.05
	label.modulate = color
	label.outline_size = 8
	label.no_depth_test = true
	get_tree().root.add_child(label)
	label.global_position = pos
	var tween := create_tween()
	tween.tween_property(label, "global_position:y", pos.y + 2.0, 1.0) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 1.0)
	tween.tween_callback(label.queue_free)

# ----------------------------------------------------------
# グラップル開始
# ----------------------------------------------------------
func start_grapple(initiator: Node, receiver: Node, grapple_data: GrappleData) -> void:
	grapple_initiator   = initiator
	grapple_receiver    = receiver
	active_grapple_data = grapple_data
	dominance           = 0.5
	is_active           = true

	# 受け側を攻め側の正面 1m に位置合わせ
	# initiator / receiver は Node 型宣言だが実体は CharacterBody3D (Node3D)
	var i3d := initiator as Node3D
	var r3d := receiver  as Node3D
	var fwd := -i3d.global_transform.basis.z.normalized()
	r3d.global_position = i3d.global_position + fwd * 1.0
	r3d.look_at(i3d.global_position, Vector3.UP)

	# 両者の回復可能HP回復を停止
	_set_regen_paused(true)

	# カメラをグラップル専用の近距離視点に変更
	_adjust_camera(true)

# ----------------------------------------------------------
# グラップル入力登録（各キャラの InputHandler / CPUController から呼ぶ）
# ----------------------------------------------------------
func register_input(player_id: GameEnums.PlayerID) -> void:
	if not is_active:
		return

	var initiator_health: HealthComponent = \
		grapple_initiator.get_node_or_null("CombatController/HealthComponent")
	var receiver_health: HealthComponent = \
		grapple_receiver.get_node_or_null("CombatController/HealthComponent")

	if player_id == _get_initiator_player_id():
		var mod := initiator_health.get_dominance_modifier() if initiator_health else 1.0
		dominance = min(1.0, dominance + DOMINANCE_GAIN_PER_INPUT * mod)
		_initiator_input_this_frame = true
	else:
		var mod := receiver_health.get_dominance_modifier() if receiver_health else 1.0
		dominance = max(0.0, dominance - DOMINANCE_GAIN_PER_INPUT * mod)
		_receiver_input_this_frame = true

	dominance_changed.emit(dominance)

	# 勝利条件チェック（入力により端点到達）
	if dominance >= 1.0:
		# 攻め側勝利 → 受け側に永続ダメージ
		_resolve_grapple(grapple_initiator, grapple_receiver)
	elif dominance <= 0.0:
		# 受け側勝利（逆転）→ 攻め側に永続ダメージ
		_resolve_grapple(grapple_receiver, grapple_initiator)

# ----------------------------------------------------------
# 内部処理
# ----------------------------------------------------------

func _process_dominance(delta: float) -> void:
	var rate := _get_decay_rate()
	# 入力がない側は dominance が 0.0 に向かって減衰（CPU の抵抗をdecayで表現）
	if not _initiator_input_this_frame:
		dominance = move_toward(dominance, 0.0, rate * delta)
	if not _receiver_input_this_frame:
		dominance = move_toward(dominance, 0.0, rate * delta)
	dominance_changed.emit(dominance)

	# 勝利条件チェック（decay により端点到達した場合）
	if dominance >= 1.0:
		_resolve_grapple(grapple_initiator, grapple_receiver)
	elif dominance <= 0.0:
		_resolve_grapple(grapple_receiver, grapple_initiator)

## 回復可能HP差に基づいた動的 decay レートを返す（/sec）
## diff = 攻め側HP − 受け側HP
func _get_decay_rate() -> float:
	var i_hp := _get_recoverable_hp(grapple_initiator)
	var r_hp  := _get_recoverable_hp(grapple_receiver)
	var diff  := i_hp - r_hp

	if diff < -30.0:
		return 0.25  # 受け側が30以上有利 → 速く中立へ戻る
	elif diff < -HP_EQUAL_EPSILON:
		return 0.15  # 受け側がやや有利
	elif diff <= HP_EQUAL_EPSILON:
		return 0.1   # ほぼ互角
	elif diff <= 30.0:
		return 0.05  # 攻め側がやや有利
	else:
		return 0.03  # 攻め側が30以上有利 → ゆっくり中立へ戻る

## 勝者/敗者を確定し永続ダメージを与えてグラップルを終了
func _resolve_grapple(winner: Node, loser: Node) -> void:
	var loser_health: HealthComponent = \
		loser.get_node_or_null("CombatController/HealthComponent")
	if loser_health:
		loser_health.take_damage(GRAPPLE_FINISH_DAMAGE, GameEnums.DamageLayer.PERMANENT)
	_end_grapple(winner, loser)

func _end_grapple(winner: Node, loser: Node) -> void:
	is_active = false

	# 両者の回復可能HP回復を再開
	_set_regen_paused(false)

	# カメラを通常視点に戻す
	_adjust_camera(false)

	grapple_ended.emit(winner, loser)
	grapple_initiator   = null
	grapple_receiver    = null
	active_grapple_data = null

func _reset_frame_inputs() -> void:
	_initiator_input_this_frame = false
	_receiver_input_this_frame  = false

# ----------------------------------------------------------
# HP 回復停止 / 再開
# ----------------------------------------------------------
func _set_regen_paused(paused: bool) -> void:
	for character in [grapple_initiator, grapple_receiver]:
		if character == null:
			continue
		var hc: HealthComponent = character.get_node_or_null("CombatController/HealthComponent")
		if hc:
			hc.set_regen_paused(paused)

# ----------------------------------------------------------
# カメラ操作（グラップル専用サイドカメラ）
# ----------------------------------------------------------
func _adjust_camera(enable: bool) -> void:
	if enable:
		_create_grapple_camera()
	else:
		_destroy_grapple_camera()

func _create_grapple_camera() -> void:
	var i3d := grapple_initiator as Node3D
	var r3d := grapple_receiver  as Node3D
	if i3d == null or r3d == null:
		return

	var p1_pos := i3d.global_position
	var p2_pos := r3d.global_position
	var mid    := (p1_pos + p2_pos) * 0.5

	# 両者がちょうど視野の両端に収まる距離（キャラ間距離の2倍＋余裕）
	var fighters_dist := p1_pos.distance_to(p2_pos)
	var cam_dist: float = maxf(fighters_dist * 2.2, 3.5)

	# ステージ中央 (x=0) に近い側から X 方向に配置
	# mid.x >= 0 → -X 側、mid.x < 0 → +X 側
	var side_sign := -1.0 if mid.x >= 0.0 else 1.0
	var cam_pos   := Vector3(mid.x + side_sign * cam_dist, mid.y + 1.6, mid.z)
	var look_at_pos := Vector3(mid.x, mid.y + 1.0, mid.z)

	_grapple_camera = Camera3D.new()
	_grapple_camera.fov = GRAPPLE_CAM_FOV
	get_tree().root.add_child(_grapple_camera)
	_grapple_camera.global_position = cam_pos
	_grapple_camera.look_at(look_at_pos, Vector3.UP)
	_grapple_camera.current = true

func _destroy_grapple_camera() -> void:
	# SpringArm 内の主カメラを再び有効化
	for node in get_tree().root.get_children():
		if node is SpringArm3D:
			var main_cam := node.get_node_or_null("Camera3D") as Camera3D
			if main_cam:
				main_cam.current = true
			break
	if _grapple_camera:
		_grapple_camera.queue_free()
		_grapple_camera = null

# ----------------------------------------------------------
# ユーティリティ
# ----------------------------------------------------------
func _get_initiator_player_id() -> GameEnums.PlayerID:
	var ctrl = grapple_initiator.get_node_or_null("CombatController")
	if ctrl:
		return ctrl.player_id
	return GameEnums.PlayerID.PLAYER_ONE

func _get_recoverable_hp(character: Node) -> float:
	var hc: HealthComponent = character.get_node_or_null("CombatController/HealthComponent")
	return hc.current_recoverable_hp if hc else 0.0
