extends "res://scripts/characters/PlayerController.gd"

# ============================================================
#  CPUController.gd
#  PlayerController を継承し、人間入力を AIPhase ステートマシンに置き換える。
#  player.tscn に対して set_script() で差し替えて使う。
#
#  【フェーズ駆動型設計】
#  APPROACH : 毎フレーム相手方向へ移動。打撃射程に入ったら ENGAGE へ
#  ENGAGE   : AIBrain.request_attack() を呼び即 WAIT へ
#  WAIT     : CombatController が IDLE に戻るまで待機
#  REPOSITION: difficulty.reposition_duration 秒間後退して APPROACH へ
# ============================================================

class_name CPUController

@export var ai_profile_resource: AIProfile
@export var difficulty_resource: DifficultyProfile

var ai_brain: AIBrain

# --- AIPhase ---
enum AIPhase { APPROACH, ENGAGE, WAIT, REPOSITION }
var _ai_phase: AIPhase = AIPhase.APPROACH

# --- フェーズ内部状態 ---
var _reposition_timer: float = 0.0
var _last_cc_state: GameEnums.CharacterState = GameEnums.CharacterState.IDLE
var _reposition_dir: Vector3 = Vector3.ZERO  # REPOSITION中の後退方向

# --- 回り込み方向 ---
var _circle_dir: float = 1.0

# ----------------------------------------------------------
# 初期化
# ----------------------------------------------------------

func _ready() -> void:
	is_dummy = true
	super._ready()

	ai_brain = AIBrain.new()
	ai_brain.name = "AIBrain"
	add_child(ai_brain)

	# ガードリアクションのシグナルのみ接続（移動シグナルは廃止）
	ai_brain.action_decided.connect(_on_action_decided)

func initialize_ai(
	opponent: CharacterBody3D,
	own_combat_ctrl: Node,
	opponent_combat_ctrl: Node
) -> void:
	if not ai_profile_resource:
		ai_profile_resource = load("res://resources/ai_profiles/ai_balanced.tres")
	if not difficulty_resource:
		difficulty_resource = load("res://resources/difficulty/difficulty_normal.tres")

	ai_brain.initialize(
		self,
		opponent,
		own_combat_ctrl,
		opponent_combat_ctrl,
		ai_profile_resource,
		difficulty_resource
	)

# ----------------------------------------------------------
# 人間入力を完全に無視
# ----------------------------------------------------------

func _input(_event: InputEvent) -> void:
	pass

func _unhandled_input(_event: InputEvent) -> void:
	pass

# ----------------------------------------------------------
# メインループ
# ----------------------------------------------------------

func _physics_process(delta: float) -> void:
	if is_dead:
		_apply_gravity(delta)
		move_and_slide()
		return

	_tick_cooldowns(delta)
	_apply_gravity(delta)
	_face_opponent(delta)
	_update_ai_phase(delta)
	move_and_slide()
	_update_animation()

# ----------------------------------------------------------
# AIPhase ステートマシン
# ----------------------------------------------------------

func _update_ai_phase(delta: float) -> void:
	var combat_ctrl := get_node_or_null("CombatController")
	if not combat_ctrl:
		return

	var cc_state: GameEnums.CharacterState = combat_ctrl.get_current_state()
	var spatial: SpatialAwareness = ai_brain.spatial if ai_brain else null

	# KO・ダウン系は何もしない
	if cc_state in [
		GameEnums.CharacterState.KO,
		GameEnums.CharacterState.KNOCKDOWN,
		GameEnums.CharacterState.GETTING_UP,
		GameEnums.CharacterState.INCAPACITATED
	]:
		_stop_movement(delta)
		_last_cc_state = cc_state
		return

	# 被弾したら即 REPOSITION へ割り込み
	if cc_state == GameEnums.CharacterState.HIT_STUN and \
	   _last_cc_state != GameEnums.CharacterState.HIT_STUN:
		_enter_reposition(spatial)

	match _ai_phase:
		AIPhase.APPROACH:
			_phase_approach(delta, cc_state, spatial)
		AIPhase.ENGAGE:
			_phase_engage(cc_state, spatial)
		AIPhase.WAIT:
			_phase_wait(delta, cc_state, spatial)
		AIPhase.REPOSITION:
			_phase_reposition(delta)

	_last_cc_state = cc_state

# ----------------------------------------------------------
# 各フェーズ処理
# ----------------------------------------------------------

func _phase_approach(delta: float, cc_state: GameEnums.CharacterState, spatial: SpatialAwareness) -> void:
	# 戦闘アクション中は移動減衰のみ
	if _is_combat_busy(cc_state):
		_stop_movement(delta)
		return

	if spatial and spatial.is_opponent_in_strike_range:
		_ai_phase = AIPhase.ENGAGE
		return

	# 相手方向へ歩く
	if spatial:
		_move_toward(spatial.direction_to_opponent, false, delta)

func _phase_engage(cc_state: GameEnums.CharacterState, spatial: SpatialAwareness) -> void:
	# 戦闘アクション中なら WAIT へ
	if _is_combat_busy(cc_state):
		_ai_phase = AIPhase.WAIT
		return

	# 射程外に出ていたら APPROACH へ戻る
	if spatial and not spatial.is_opponent_in_strike_range:
		_ai_phase = AIPhase.APPROACH
		return

	# 攻撃を選択して実行
	var action_key := ai_brain.request_attack()
	_execute_action_key(action_key, spatial)
	_ai_phase = AIPhase.WAIT

func _phase_wait(delta: float, cc_state: GameEnums.CharacterState, spatial: SpatialAwareness) -> void:
	_stop_movement(delta)

	# IDLE に戻ったら次フェーズへ
	if cc_state == GameEnums.CharacterState.IDLE and \
	   _last_cc_state != GameEnums.CharacterState.IDLE:
		if spatial and spatial.is_opponent_in_strike_range:
			_ai_phase = AIPhase.ENGAGE
		else:
			_ai_phase = AIPhase.APPROACH

func _phase_reposition(delta: float) -> void:
	_reposition_timer -= delta
	if _reposition_timer <= 0.0:
		_ai_phase = AIPhase.APPROACH
		return

	# ガード優先フラグ（_reposition_dir がゼロ）の場合は移動しない
	if _reposition_dir.length_squared() < 0.01:
		_stop_movement(delta)
		return

	# 後退方向へ移動
	velocity.x = _reposition_dir.x * walk_speed
	velocity.z = _reposition_dir.z * walk_speed

# ----------------------------------------------------------
# 行動実行
# ----------------------------------------------------------

func _execute_action_key(action_key: String, spatial: SpatialAwareness) -> void:
	var combat_ctrl := get_node_or_null("CombatController")
	if not combat_ctrl:
		return

	var action := _key_to_action_type(action_key)
	if action == GameEnums.ActionType.NONE:
		return

	# グラップルは射程チェック（万一ずれた場合の保険）
	if action == GameEnums.ActionType.GRAPPLE:
		if spatial and not spatial.is_opponent_in_grapple_range:
			_ai_phase = AIPhase.APPROACH
			return

	combat_ctrl.receive_input(action)
	ai_brain.notify_attack_executed(action_key)

# ----------------------------------------------------------
# ガードリアクション（AIBrain.action_decided シグナル）
# ----------------------------------------------------------

func _on_action_decided(action_key: String) -> void:
	var combat_ctrl := get_node_or_null("CombatController")
	if not combat_ctrl:
		return

	var action := _key_to_action_type(action_key)
	if action == GameEnums.ActionType.NONE:
		return

	combat_ctrl.receive_input(action)

	# ガード後は APPROACH に戻す
	if action == GameEnums.ActionType.GUARD:
		_ai_phase = AIPhase.APPROACH

# ----------------------------------------------------------
# 移動ヘルパー
# ----------------------------------------------------------

func _move_toward(direction: Vector3, run: bool, delta: float) -> void:
	if direction.length_squared() < 0.01:
		_stop_movement(delta)
		return

	var speed := run_speed if run else walk_speed
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed

	# 向きは _face_opponent() が毎フレーム制御するため look_at() は不要

	_change_state(State.RUN if run else State.WALK)

func _stop_movement(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, walk_speed * 2.0 * delta)
	velocity.z = move_toward(velocity.z, 0.0, walk_speed * 2.0 * delta)
	if velocity.x == 0.0 and velocity.z == 0.0:
		_change_state(State.IDLE)

func _enter_reposition(spatial: SpatialAwareness) -> void:
	_ai_phase = AIPhase.REPOSITION
	_reposition_timer = difficulty_resource.reposition_duration if difficulty_resource else 0.7

	# 回復可能HPが低く相手が射程内にいる場合はガード優先
	var low_hp := ai_brain and ai_brain.move_selector and \
		ai_brain.move_selector.own_recoverable_hp_ratio < 0.4
	var in_range := spatial and spatial.is_opponent_in_strike_range
	if low_hp and in_range:
		var combat_ctrl := get_node_or_null("CombatController")
		if combat_ctrl:
			combat_ctrl.receive_input(GameEnums.ActionType.GUARD)
		_reposition_dir = Vector3.ZERO
		return

	# 相手と逆方向 + わずかに横成分を加える
	if spatial and spatial.direction_to_opponent.length_squared() > 0.01:
		var away := -spatial.direction_to_opponent
		var lateral := Vector3(-away.z, 0.0, away.x) * _circle_dir
		_reposition_dir = (away * 0.8 + lateral * 0.2).normalized()
		_circle_dir *= -1.0  # 次回は逆方向
	else:
		_reposition_dir = -global_transform.basis.z

# ----------------------------------------------------------
# ユーティリティ
# ----------------------------------------------------------

func _is_combat_busy(cc_state: GameEnums.CharacterState) -> bool:
	return cc_state in [
		GameEnums.CharacterState.ATTACKING,
		GameEnums.CharacterState.GUARDING,
		GameEnums.CharacterState.GRAPPLING,
		GameEnums.CharacterState.GRAPPLED,
		GameEnums.CharacterState.HIT_STUN,
		GameEnums.CharacterState.KNOCKDOWN,
		GameEnums.CharacterState.GETTING_UP,
		GameEnums.CharacterState.INCAPACITATED,
		GameEnums.CharacterState.KO
	]

func _key_to_action_type(key: String) -> GameEnums.ActionType:
	match key:
		"punch_light", "punch_heavy": return GameEnums.ActionType.PUNCH
		"kick_light",  "kick_heavy":  return GameEnums.ActionType.KICK
		"grapple":                    return GameEnums.ActionType.GRAPPLE
		"guard":                      return GameEnums.ActionType.GUARD
		_:                            return GameEnums.ActionType.NONE
