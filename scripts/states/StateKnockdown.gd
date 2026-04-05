class_name StateKnockdown
extends BaseState

func enter(_prev: GameEnums.CharacterState) -> void:
	combat_controller.play_anim("knockdown")

func handle_input(_action: GameEnums.ActionType) -> void:
	pass
