class_name StateHitStun
extends BaseState

var _stun_frames: int = 0
var _frame_counter: int = 0

func enter(_prev: GameEnums.CharacterState) -> void:
	_frame_counter = 0
	_stun_frames   = combat_controller._pending_hit_stun_frames
	combat_controller.play_anim("hit_stun")

func update(_delta: float) -> void:
	_frame_counter += 1
	if _frame_counter >= _stun_frames:
		combat_controller.transition_to(GameEnums.CharacterState.IDLE)

func handle_input(_action: GameEnums.ActionType) -> void:
	pass  # ヒットスタン中は入力無効
