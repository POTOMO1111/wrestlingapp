class_name StateGettingUp
extends BaseState

const DURATION: float = 1.2

var _timer: float = 0.0

func enter(_prev: GameEnums.CharacterState) -> void:
	_timer = 0.0
	combat_controller.play_anim("getting_up")

func update(delta: float) -> void:
	_timer += delta
	if _timer >= DURATION:
		combat_controller.transition_to(GameEnums.CharacterState.IDLE)

func handle_input(_action: GameEnums.ActionType) -> void:
	pass
