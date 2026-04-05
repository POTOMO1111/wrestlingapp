class_name StateIdle
extends BaseState

func enter(_prev: GameEnums.CharacterState) -> void:
	combat_controller.play_anim("idle")

func update(delta: float) -> void:
	# 移動はPlayerController / CPUController 側で処理
	pass

func handle_input(action: GameEnums.ActionType) -> void:
	match action:
		GameEnums.ActionType.PUNCH, GameEnums.ActionType.KICK:
			if GameManager.debug_mode:
				print("[StateIdle] handle_input PUNCH/KICK  combo_mgr=%s" % str(combat_controller.combo_manager))
			var attack = combat_controller.combo_manager.try_input(action)
			if GameManager.debug_mode:
				print("[StateIdle] try_input result: %s" % str(attack))
			if attack != null:
				combat_controller._pending_grapple_data = null  # グラップルデータをクリア
				combat_controller._pending_attack = attack
				combat_controller.health.consume_stamina(attack.stamina_cost)
				combat_controller.transition_to(GameEnums.CharacterState.ATTACKING)

		GameEnums.ActionType.GRAPPLE:
			# GrappleData が未設定なら基本グラップルリソースをロード
			if combat_controller._pending_grapple_data == null:
				var gd = load("res://resources/attacks/grapple_basic.tres")
				combat_controller._pending_grapple_data = gd if gd != null else GrappleData.new()
			var grapple = combat_controller._pending_grapple_data
			if combat_controller.health.consume_stamina(grapple.stamina_cost):
				combat_controller._pending_attack = null  # 前回の打撃データをクリア
				combat_controller.transition_to(GameEnums.CharacterState.ATTACKING)

		GameEnums.ActionType.GUARD:
			combat_controller.transition_to(GameEnums.CharacterState.GUARDING)
