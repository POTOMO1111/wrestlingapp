extends "res://scripts/characters/PlayerController.gd"

# ============================================================
#  CPUController.gd
#  PlayerController を継承し、入力をAIに置き換える。
#  player.tscn に対して set_script() で差し替えて使う。
# ============================================================

# --- AI パラメータ ---
@export var aggression     : float = 0.6   # 攻撃頻度 (0.0〜1.0)
@export var skill_level    : float = 0.5   # 反応速度・判断精度 (0.0〜1.0)

# --- 内部状態 ---
var _opponent          : Node3D = null
var _ai_timer          : float = 0.0    # 次の判断までのタイマー
var _action_cd         : float = 0.0    # 行動後の硬直
var _ai_behavior       : StringName = &"approach"
var _circle_dir        : float = 1.0    # 回り込み方向 (1 or -1)
var _block_timer       : float = 0.0
var _combat_controller : Node = null    # 新戦闘システムへの参照

# 攻撃クールダウン（新システムではフレームデータで管理するが AI 判断間隔として保持）
var _light_cd   : float = 0.0
var _heavy_cd   : float = 0.0
var _grapple_cd : float = 0.0
const light_attack_cooldown : float = 0.5
const heavy_attack_cooldown : float = 0.9
const grapple_cooldown      : float = 1.2

# 距離しきい値
const ATTACK_RANGE   : float = 1.8
const GRAPPLE_RANGE  : float = 1.4
const APPROACH_RANGE : float = 4.0
const RETREAT_DIST   : float = 1.0

# ----------------------------------------------------------
# 初期化
# ----------------------------------------------------------
func _ready() -> void:
	is_dummy = true   # PlayerController の入力処理を無効化
	super._ready()
	# 1フレーム後に対戦相手を検索（add_child が全て完了してから）
	call_deferred("_deferred_init")

func _deferred_init() -> void:
	_find_opponent()
	_find_combat_controller()
	# 見つからなかった場合は次の物理フレームで再試行される

func _find_combat_controller() -> void:
	_combat_controller = get_node_or_null("CombatController")

func _find_opponent() -> void:
	for fighter in get_tree().get_nodes_in_group("fighter"):
		if fighter != self and is_instance_valid(fighter) and fighter is CharacterBody3D:
			_opponent = fighter
			return

# ----------------------------------------------------------
# メインループ（PlayerController._physics_process を完全に上書き）
# ----------------------------------------------------------
func _physics_process(delta: float) -> void:
	if is_dead:
		_apply_gravity(delta)
		move_and_slide()
		return

	if _opponent == null or not is_instance_valid(_opponent) or not (_opponent is CharacterBody3D):
		_find_opponent()

	_tick_cooldowns(delta)
	_apply_gravity(delta)
	_ai_think(delta)
	move_and_slide()
	_update_animation()

# ----------------------------------------------------------
# AI 思考メイン
# ----------------------------------------------------------
func _ai_think(delta: float) -> void:
	_ai_timer   -= delta
	_action_cd  -= delta
	_block_timer -= delta
	_light_cd   = max(0.0, _light_cd   - delta)
	_heavy_cd   = max(0.0, _heavy_cd   - delta)
	_grapple_cd = max(0.0, _grapple_cd - delta)

	# グラップル中の専用処理（新システム）
	if _combat_controller:
		var cc_state = _combat_controller.get_current_state()
		if cc_state == GameEnums.CharacterState.GRAPPLING or cc_state == GameEnums.CharacterState.GRAPPLED:
			_handle_grapple_ai()
			return

	# 攻撃・被弾中は動けない（踏み込み減衰だけ処理）
	if current_state in [State.ATTACK_LIGHT, State.ATTACK_HEAVY, State.GRAPPLE, State.HIT, State.DOWN]:
		velocity.x = move_toward(velocity.x, 0, 20.0 * delta)
		velocity.z = move_toward(velocity.z, 0, 20.0 * delta)
		return

	if _opponent == null or not is_instance_valid(_opponent):
		velocity.x = 0
		velocity.z = 0
		_change_state(State.IDLE)
		return

	var to_opp := _opponent.global_position - global_position
	to_opp.y = 0
	var dist := to_opp.length()
	var dir  := to_opp.normalized() if dist > 0.1 else -global_transform.basis.z

	# 一定間隔で行動方針を再決定
	if _ai_timer <= 0.0:
		_ai_timer = _next_think_interval()
		_decide_behavior(dist)

	# 行動方針に従って動く
	match _ai_behavior:
		&"approach":
			_do_approach(dir, dist, delta)
		&"attack":
			_do_attack(dir, dist)
		&"circle":
			_do_circle(dir, delta)
		&"retreat":
			_do_retreat(dir, delta)
		&"block":
			_do_block_behavior(delta)
		&"idle":
			velocity.x = 0
			velocity.z = 0
			_change_state(State.IDLE)

# ----------------------------------------------------------
# 行動方針の決定
# ----------------------------------------------------------
func _decide_behavior(dist: float) -> void:
	# 体力が低いときは慎重に
	var hc: HealthComponent = get_node_or_null("CombatController/HealthComponent")
	var hp_ratio := (hc.current_permanent_hp / hc.stats.max_permanent_hp) if hc and hc.stats else 1.0
	var stam_ratio := (hc.current_recoverable_hp / hc.stats.max_recoverable_hp) if hc and hc.stats else 1.0

	# スタミナが低いなら後退
	if stam_ratio < 0.2:
		_ai_behavior = &"retreat"
		return

	# 相手の攻撃を受けた直後はブロックしやすい
	if current_state == State.HIT or _block_timer > 0:
		if randf() < 0.4 + skill_level * 0.3:
			_ai_behavior = &"block"
			_block_timer = randf_range(0.3, 0.8)
			return

	if dist > APPROACH_RANGE:
		# 遠い → 近づく
		_ai_behavior = &"approach"
	elif dist > ATTACK_RANGE:
		# 中距離 → 確率で近づく or 回り込む
		var roll := randf()
		if roll < aggression:
			_ai_behavior = &"approach"
		else:
			_ai_behavior = &"circle"
			_circle_dir = [-1.0, 1.0].pick_random()
	else:
		# 攻撃射程内
		if _action_cd <= 0:
			var roll := randf()
			if roll < aggression * 0.7:
				_ai_behavior = &"attack"
			elif roll < aggression * 0.7 + 0.15:
				_ai_behavior = &"circle"
				_circle_dir = [-1.0, 1.0].pick_random()
			elif hp_ratio < 0.4 and randf() < 0.3:
				_ai_behavior = &"retreat"
			else:
				_ai_behavior = &"idle"
		else:
			_ai_behavior = &"circle"

# ----------------------------------------------------------
# 接近
# ----------------------------------------------------------
func _do_approach(dir: Vector3, dist: float, delta: float) -> void:
	var speed := walk_speed
	# 遠ければ走る
	if dist > APPROACH_RANGE * 0.8 and consume_stamina(20.0 * delta):
		speed = run_speed
		_change_state(State.RUN)
	else:
		_change_state(State.WALK)

	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	_face_direction(dir, delta)

	# 射程に入ったら攻撃に切り替え
	if dist < ATTACK_RANGE and _action_cd <= 0:
		_ai_behavior = &"attack"

# ----------------------------------------------------------
# 攻撃
# ----------------------------------------------------------
func _do_attack(dir: Vector3, dist: float) -> void:
	if _action_cd > 0:
		_ai_behavior = &"circle"
		return

	_face_direction(dir, 1.0)  # 即座に向く
	velocity.x = 0
	velocity.z = 0

	# 攻撃選択
	var roll := randf()

	if dist < GRAPPLE_RANGE and roll < 0.25 and _grapple_cd <= 0.0:
		# グラップル（新システム経由）
		if _combat_controller and _combat_controller.has_method("receive_input"):
			_combat_controller.receive_input(GameEnums.ActionType.GRAPPLE)
			_grapple_cd = grapple_cooldown
			_action_cd = 1.5
			_ai_behavior = &"idle"
	elif roll < 0.6 and _light_cd <= 0.0:
		# 弱攻撃（新システム経由）
		if _combat_controller and _combat_controller.has_method("receive_input"):
			_combat_controller.receive_input(GameEnums.ActionType.PUNCH)
			_light_cd = light_attack_cooldown
			_action_cd = 0.6 + randf_range(0.0, 0.3)
			_ai_behavior = &"idle"
	elif _heavy_cd <= 0.0:
		# 強攻撃（新システム経由）
		if _combat_controller and _combat_controller.has_method("receive_input"):
			_combat_controller.receive_input(GameEnums.ActionType.KICK)
			_heavy_cd = heavy_attack_cooldown
			_action_cd = 1.0 + randf_range(0.0, 0.4)
			_ai_behavior = &"idle"
	else:
		# クールダウン中 → 回り込み
		_ai_behavior = &"circle"

# ----------------------------------------------------------
# 回り込み
# ----------------------------------------------------------
func _do_circle(dir: Vector3, delta: float) -> void:
	var lateral := Vector3(-dir.z, 0, dir.x) * _circle_dir
	# 少し近づきながら横移動
	var move := (lateral * 0.8 + dir * 0.2).normalized()

	velocity.x = move.x * walk_speed
	velocity.z = move.z * walk_speed
	_face_direction(dir, delta)
	_change_state(State.WALK)

# ----------------------------------------------------------
# 後退
# ----------------------------------------------------------
func _do_retreat(dir: Vector3, delta: float) -> void:
	velocity.x = -dir.x * walk_speed
	velocity.z = -dir.z * walk_speed
	_face_direction(dir, delta)
	_change_state(State.WALK)

# ----------------------------------------------------------
# ブロック
# ----------------------------------------------------------
func _do_block_behavior(delta: float) -> void:
	velocity.x = 0
	velocity.z = 0

	if _opponent and is_instance_valid(_opponent):
		var dir := (_opponent.global_position - global_position).normalized()
		dir.y = 0
		_face_direction(dir, delta)

	# 新システム経由でガード入力
	if _combat_controller and _combat_controller.has_method("receive_input"):
		_combat_controller.receive_input(GameEnums.ActionType.GUARD)

	_block_timer -= delta
	if _block_timer <= 0:
		_ai_behavior = &"approach"

# ----------------------------------------------------------
# グラップルロック中のAI入力
# ----------------------------------------------------------
func _handle_grapple_ai() -> void:
	velocity.x = 0
	velocity.z = 0
	# CPU の抵抗は decay レートで表現するため、入力は行わない

# ----------------------------------------------------------
# 被ダメージ（ブロック反応）
# ----------------------------------------------------------
func take_damage(_amount: int, _knockback_dir: Vector3 = Vector3.ZERO) -> void:
	# ダメージは新システム（HealthComponent）が処理する。
	# 次のサイクルでブロックしやすくする AI 反応のみ保持。
	_block_timer = randf_range(0.2, 0.6)

# ----------------------------------------------------------
# ユーティリティ
# ----------------------------------------------------------
func _face_direction(dir: Vector3, delta: float) -> void:
	if dir.length_squared() > 0.01:
		var target_angle := atan2(dir.x, dir.z)
		rotation.y = lerp_angle(rotation.y, target_angle, 10.0 * delta)

func _next_think_interval() -> float:
	# skill_level が高いほど判断が速い
	return randf_range(0.15, 0.5) / (0.5 + skill_level * 0.5)
