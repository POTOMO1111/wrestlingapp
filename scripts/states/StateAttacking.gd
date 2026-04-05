class_name StateAttacking
extends BaseState

var _current_attack: AttackData  = null
var _current_grapple: GrappleData = null
var _frame_counter: int = 0
var _phase: String = "startup"  # "startup" / "active" / "recovery"
var _is_grapple: bool = false

func enter(_prev: GameEnums.CharacterState) -> void:
	_frame_counter = 0
	_phase = "startup"
	_current_attack  = combat_controller._pending_attack
	_current_grapple = combat_controller._pending_grapple_data
	_is_grapple = (_current_attack == null and _current_grapple != null)

	if GameManager.debug_mode:
		print("[StateAttacking:%s] enter — attack=%s grapple=%s is_grapple=%s" % [
			combat_controller.get_parent().name, str(_current_attack), str(_current_grapple), _is_grapple
		])

	if _is_grapple:
		combat_controller.play_anim(_current_grapple.initiator_animation)
	elif _current_attack != null:
		combat_controller.play_anim(_current_attack.animation_name)
	else:
		if GameManager.debug_mode:
			print("[StateAttacking:%s] no attack or grapple — reverting to IDLE" % combat_controller.get_parent().name)
		combat_controller.transition_to(GameEnums.CharacterState.IDLE)

func update(_delta: float) -> void:
	_frame_counter += 1
	var startup = _current_grapple.startup_frames if _is_grapple else (_current_attack.startup_frames if _current_attack else 1)
	var active  = _current_grapple.active_frames  if _is_grapple else (_current_attack.active_frames  if _current_attack else 1)
	var recovery = _current_grapple.recovery_frames if _is_grapple else (_current_attack.recovery_frames if _current_attack else 1)

	match _phase:
		"startup":
			if _frame_counter >= startup:
				_phase = "active"
				_frame_counter = 0
				if GameManager.debug_mode:
					print("[StateAttacking:%s] startup→active — activating hitbox" % combat_controller.get_parent().name)
				if _is_grapple:
					combat_controller.hitbox_manager.activate_grapple_hitbox(_current_grapple)
				else:
					combat_controller.hitbox_manager.activate_hitbox(_current_attack)

		"active":
			if _frame_counter >= active:
				_phase = "recovery"
				_frame_counter = 0
				combat_controller.hitbox_manager.deactivate_hitbox()
				if not _is_grapple:
					combat_controller.combo_manager.open_combo_window()

		"recovery":
			if _frame_counter >= recovery:
				if not _is_grapple:
					combat_controller.combo_manager.close_combo_window()
				# グラップルが成立してステートが変わっていれば何もしない
				if combat_controller.get_current_state() == GameEnums.CharacterState.ATTACKING:
					combat_controller.transition_to(GameEnums.CharacterState.IDLE)

func exit(_next: GameEnums.CharacterState) -> void:
	# 強制遷移（リセット等）時にも hitbox を必ず無効化する
	combat_controller.hitbox_manager.deactivate_hitbox()

func handle_input(action: GameEnums.ActionType) -> void:
	# コンボウィンドウ中（recovery フェーズ）のみ次入力を受け付ける
	if _phase != "recovery" or _is_grapple:
		return
	var next_attack = combat_controller.combo_manager.try_input(action)
	if next_attack != null:
		combat_controller._pending_attack = next_attack
		combat_controller.transition_to(GameEnums.CharacterState.IDLE)
		combat_controller.transition_to(GameEnums.CharacterState.ATTACKING)
