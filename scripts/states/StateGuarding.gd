class_name StateGuarding
extends BaseState

var _guard_timer: float = 0.0
const MAX_GUARD_HOLD: float = 3.0

func enter(_prev: GameEnums.CharacterState) -> void:
	_guard_timer = 0.0
	combat_controller.play_anim("guard")

func update(delta: float) -> void:
	# ブロックキーが離されたらガード解除
	if not Input.is_action_pressed("block"):
		combat_controller.transition_to(GameEnums.CharacterState.IDLE)
		return
	_guard_timer += delta
	# ガード中はじわじわ回復可能HPを消費
	combat_controller.health.take_damage(2.0 * delta, GameEnums.DamageLayer.RECOVERABLE)
	if _guard_timer >= MAX_GUARD_HOLD:
		combat_controller.transition_to(GameEnums.CharacterState.IDLE)

func handle_input(action: GameEnums.ActionType) -> void:
	if action != GameEnums.ActionType.GUARD:
		combat_controller.transition_to(GameEnums.CharacterState.IDLE)
