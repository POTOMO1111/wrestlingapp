class_name StateKO
extends BaseState

func enter(_prev: GameEnums.CharacterState) -> void:
	combat_controller.play_anim("ko")

func handle_input(_action: GameEnums.ActionType) -> void:
	pass  # KO中は一切の入力無効
