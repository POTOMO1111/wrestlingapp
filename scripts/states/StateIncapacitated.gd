class_name StateIncapacitated
extends BaseState

func enter(_prev: GameEnums.CharacterState) -> void:
	combat_controller.play_anim("knockdown")
	# HealthComponent のタイマーが終了すると incapacitation_ended → GETTING_UP に遷移

func handle_input(_action: GameEnums.ActionType) -> void:
	pass  # 行動不可中は一切の入力を無効化
