class_name StateGrappled
extends BaseState

func enter(_prev: GameEnums.CharacterState) -> void:
	combat_controller.play_anim("grapple_receiver")

func handle_input(action: GameEnums.ActionType) -> void:
	if action == GameEnums.ActionType.GRAPPLE:
		var grapple_mgr = get_tree().get_first_node_in_group("grapple_manager")
		if grapple_mgr:
			grapple_mgr.register_input(combat_controller.player_id)
