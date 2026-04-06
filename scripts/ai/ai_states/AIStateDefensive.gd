class_name AIStateDefensive
extends AIStateBase

# ============================================================
#  AIStateDefensive.gd
#  防御的戦略ステート。
#  自身の体力が低い時・相手の攻勢が激しい時に遷移。
#  ガード・stall・circleの重みを上げ、攻撃の重みを下げる。
# ============================================================

func get_weight_modifiers() -> Dictionary:
	return {
		"guard": 2.5, "stall": 2.0, "circle": 1.8,
		"punch_light": 0.7, "punch_heavy": 0.3,
		"kick_light": 0.7, "kick_heavy": 0.3, "grapple": 0.4
	}

func check_transition() -> String:
	var ms: MoveSelector = brain.move_selector
	if ms.own_recoverable_hp_ratio > 0.5:
		return "opportunistic"
	if ms.opponent_state in [
		GameEnums.CharacterState.KNOCKDOWN,
		GameEnums.CharacterState.INCAPACITATED
	]:
		return "aggressive"
	return ""
