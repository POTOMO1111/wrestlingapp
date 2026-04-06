extends "res://scripts/characters/PlayerController.gd"

# ============================================================
#  CPUController.gd
#  PlayerController を継承し、人間入力を AIBrain に置き換える。
#  player.tscn に対して set_script() で差し替えて使う。
# ============================================================

class_name CPUController

@export var ai_profile_resource: AIProfile
@export var difficulty_resource: DifficultyProfile

var ai_brain: AIBrain

# --- AI移動制御 ---
var _ai_move_direction: Vector3 = Vector3.ZERO
var _ai_should_run: bool = false
var _ai_move_timer: float = 0.0
const AI_MOVE_DURATION: float = 0.4   # 1回の移動指令の持続時間（秒）

# --- 回り込み制御 ---
var _circle_dir: float = 1.0          # 1 or -1

# ----------------------------------------------------------
# 初期化
# ----------------------------------------------------------
func _ready() -> void:
	is_dummy = true   # PlayerController の人間入力を無効化
	super._ready()

	ai_brain = AIBrain.new()
	ai_brain.name = "AIBrain"
	add_child(ai_brain)

	ai_brain.action_decided.connect(_on_action_decided)
	ai_brain.movement_decided.connect(_on_movement_decided)

## main.gd の _attach_combat_system() 末尾から呼ぶ。
## CombatController が動的生成された後でないと呼べない。
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
# 人間入力を完全に無視（PlayerController._input / _unhandled_input をオーバーライド）
# ----------------------------------------------------------
func _input(_event: InputEvent) -> void:
	pass

func _unhandled_input(_event: InputEvent) -> void:
	pass

# ----------------------------------------------------------
# メインループ（PlayerController._physics_process を完全上書き）
# ----------------------------------------------------------
func _physics_process(delta: float) -> void:
	if is_dead:
		_apply_gravity(delta)
		move_and_slide()
		return

	_tick_cooldowns(delta)
	_apply_gravity(delta)
	_update_ai_movement(delta)
	move_and_slide()
	_update_animation()

# ----------------------------------------------------------
# AI移動を velocity に反映
# ----------------------------------------------------------
func _update_ai_movement(delta: float) -> void:
	_ai_move_timer -= delta

	var combat_ctrl := get_node_or_null("CombatController")
	if combat_ctrl:
		var cc_state = combat_ctrl.get_current_state()
		# 戦闘アクション中は移動を減衰させるだけ
		if cc_state in [
			GameEnums.CharacterState.ATTACKING,
			GameEnums.CharacterState.GUARDING,
			GameEnums.CharacterState.GRAPPLING,
			GameEnums.CharacterState.GRAPPLED,
			GameEnums.CharacterState.HIT_STUN,
			GameEnums.CharacterState.KNOCKDOWN,
			GameEnums.CharacterState.GETTING_UP,
			GameEnums.CharacterState.INCAPACITATED,
			GameEnums.CharacterState.KO
		]:
			velocity.x = move_toward(velocity.x, 0.0, 20.0 * delta)
			velocity.z = move_toward(velocity.z, 0.0, 20.0 * delta)
			return

	if _ai_move_timer > 0.0 and _ai_move_direction.length_squared() > 0.01:
		var speed := run_speed if _ai_should_run else walk_speed
		velocity.x = _ai_move_direction.x * speed
		velocity.z = _ai_move_direction.z * speed
		# キャラを移動方向に向ける
		var look_target := global_position + _ai_move_direction
		look_target.y = global_position.y
		if global_position.distance_to(look_target) > 0.01:
			look_at(look_target, Vector3.UP)
		_change_state(State.RUN if _ai_should_run else State.WALK)
	else:
		velocity.x = move_toward(velocity.x, 0.0, walk_speed * 0.5)
		velocity.z = move_toward(velocity.z, 0.0, walk_speed * 0.5)
		_change_state(State.IDLE)

# ----------------------------------------------------------
# AIBrain シグナルハンドラ
# ----------------------------------------------------------

## 行動決定 → CombatController に入力を渡す
func _on_action_decided(action_key: String) -> void:
	var combat_ctrl := get_node_or_null("CombatController")
	if not combat_ctrl:
		return

	var action := _key_to_action_type(action_key)
	if action == GameEnums.ActionType.NONE:
		return

	combat_ctrl.receive_input(action)

	# コンボ追跡開始
	if action in [GameEnums.ActionType.PUNCH, GameEnums.ActionType.KICK]:
		if not ai_brain._in_combo:
			ai_brain._in_combo = true
			ai_brain.move_selector.begin_combo()

## 移動決定 → velocity 制御のためにキャッシュ
func _on_movement_decided(direction: Vector3, should_run: bool) -> void:
	# "circle" 指令のとき横方向に変換する
	if direction.length_squared() > 0.01 and not should_run:
		var lateral := Vector3(-direction.z, 0.0, direction.x) * _circle_dir
		_ai_move_direction = (lateral * 0.7 + direction * 0.3).normalized()
		# 次回は逆方向に回り込む（ランダム反転）
		if randf() < 0.15:
			_circle_dir *= -1.0
	else:
		_ai_move_direction = direction

	_ai_should_run = should_run
	_ai_move_timer = AI_MOVE_DURATION

# ----------------------------------------------------------
# ユーティリティ
# ----------------------------------------------------------

func _key_to_action_type(key: String) -> GameEnums.ActionType:
	match key:
		"punch_light", "punch_heavy": return GameEnums.ActionType.PUNCH
		"kick_light",  "kick_heavy":  return GameEnums.ActionType.KICK
		"grapple":                    return GameEnums.ActionType.GRAPPLE
		"guard":                      return GameEnums.ActionType.GUARD
		_:                            return GameEnums.ActionType.NONE
