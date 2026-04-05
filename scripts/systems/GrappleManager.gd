class_name GrappleManager
extends Node

# ============================================================
#  GrappleManager.gd
#  FightManager の子ノードとして存在。
#  dominance 型グラップルシステムを管理する。
#  グループ "grapple_manager" に追加すること。
# ============================================================

var grapple_initiator: Node = null
var grapple_receiver:  Node = null
var active_grapple_data: GrappleData = null

# dominance: 0.0〜1.0（1.0に近いほど攻め側有利）
var dominance: float = 0.5

const DOMINANCE_GAIN_PER_INPUT:    float = 0.08
const DOMINANCE_DECAY_RATE:        float = 0.05
const DOMINANCE_DAMAGE_THRESHOLD:  float = 0.75
const DOMINANCE_REVERSE_THRESHOLD: float = 0.25
const DAMAGE_INTERVAL:             float = 1.0
const GRAPPLE_TIMEOUT:             float = 8.0  # 最大継続秒数（無限グラップル防止）

var _damage_interval_timer: float = 0.0
var _timeout_timer:         float = 0.0
var _initiator_input_this_frame: bool = false
var _receiver_input_this_frame:  bool = false
var is_active: bool = false

signal grapple_damage_dealt(target: Node, rec_dmg: float, perm_dmg: float)
signal grapple_ended(winner: Node, loser: Node)
signal dominance_changed(new_dominance: float)

func _ready() -> void:
	add_to_group("grapple_manager")

func _physics_process(delta: float) -> void:
	if not is_active:
		return
	_timeout_timer += delta
	if _timeout_timer >= GRAPPLE_TIMEOUT:
		_end_grapple(null, null)
		return
	_process_dominance(delta)
	_process_damage(delta)
	_reset_frame_inputs()

## テキストエフェクト（旧 GrappleSystem._spawn_text_effect の後継）
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
	tween.tween_property(label, "global_position:y", pos.y + 2.0, 1.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 1.0)
	tween.tween_callback(label.queue_free)

## グラップル開始
func start_grapple(initiator: Node, receiver: Node, grapple_data: GrappleData) -> void:
	grapple_initiator    = initiator
	grapple_receiver     = receiver
	active_grapple_data  = grapple_data
	dominance            = 0.5
	_damage_interval_timer = 0.0
	_timeout_timer         = 0.0
	is_active            = true

	# 受け側を攻め側の正面 1m に位置合わせ
	var fwd = -initiator.global_transform.basis.z.normalized()
	receiver.global_position = initiator.global_position + fwd * 1.0
	receiver.look_at(initiator.global_position, Vector3.UP)

## グラップル入力登録（各キャラの InputHandler / CPUController から呼ぶ）
func register_input(player_id: GameEnums.PlayerID) -> void:
	if not is_active:
		return

	var initiator_health: HealthComponent = grapple_initiator.get_node_or_null("CombatController/HealthComponent")
	var receiver_health:  HealthComponent = grapple_receiver.get_node_or_null("CombatController/HealthComponent")

	if player_id == _get_initiator_player_id():
		var mod = initiator_health.get_dominance_modifier() if initiator_health else 1.0
		dominance = min(1.0, dominance + DOMINANCE_GAIN_PER_INPUT * mod)
		_initiator_input_this_frame = true
	else:
		var mod = receiver_health.get_dominance_modifier() if receiver_health else 1.0
		dominance = max(0.0, dominance - DOMINANCE_GAIN_PER_INPUT * mod)
		_receiver_input_this_frame = true

	dominance_changed.emit(dominance)

func end_grapple_by_timeout() -> void:
	_end_grapple(null, null)

# ----------------------------------------------------------
# 内部処理
# ----------------------------------------------------------

func _process_dominance(delta: float) -> void:
	if not _initiator_input_this_frame:
		dominance = move_toward(dominance, 0.5, DOMINANCE_DECAY_RATE * delta)
	if not _receiver_input_this_frame:
		dominance = move_toward(dominance, 0.5, DOMINANCE_DECAY_RATE * delta)
	dominance_changed.emit(dominance)

	if dominance <= DOMINANCE_REVERSE_THRESHOLD:
		_on_receiver_reversal()

func _process_damage(delta: float) -> void:
	_damage_interval_timer += delta
	if _damage_interval_timer < DAMAGE_INTERVAL:
		return
	_damage_interval_timer = 0.0

	if dominance < DOMINANCE_DAMAGE_THRESHOLD:
		return

	var initiator_stats: CharacterStats = _get_stats(grapple_initiator)
	var receiver_stats:  CharacterStats = _get_stats(grapple_receiver)
	if initiator_stats == null or receiver_stats == null:
		return

	var dmg = DamageCalculator.calculate_grapple_damage(
		active_grapple_data, dominance, initiator_stats, receiver_stats
	)
	grapple_damage_dealt.emit(grapple_receiver, dmg["recoverable"], dmg["permanent"])

func _on_receiver_reversal() -> void:
	_end_grapple(grapple_receiver, grapple_initiator)

func _end_grapple(winner: Node, loser: Node) -> void:
	is_active = false
	grapple_ended.emit(winner, loser)
	grapple_initiator   = null
	grapple_receiver    = null
	active_grapple_data = null

func _reset_frame_inputs() -> void:
	_initiator_input_this_frame = false
	_receiver_input_this_frame  = false

func _get_initiator_player_id() -> GameEnums.PlayerID:
	var ctrl = grapple_initiator.get_node_or_null("CombatController")
	if ctrl:
		return ctrl.player_id
	return GameEnums.PlayerID.PLAYER_ONE

func _get_stats(character: Node) -> CharacterStats:
	var hc: HealthComponent = character.get_node_or_null("CombatController/HealthComponent")
	return hc.stats if hc else null
