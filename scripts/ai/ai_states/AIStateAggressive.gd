class_name AIStateAggressive
extends AIStateBase

# ============================================================
#  AIStateAggressive.gd
#  攻撃的戦略ステート。
#  モメンタム優位時・相手ダメージ大時に遷移。
#  打撃・グラップルの重みを上げ、ガード・stallを下げる。
# ============================================================

func get_weight_modifiers() -> Dictionary:
	return {
		"punch_heavy": 1.5, "kick_heavy": 1.5, "grapple": 1.3,
		"guard": 0.3, "stall": 0.2, "circle": 0.5
	}

func check_transition() -> String:
	var ms: MoveSelector = brain.move_selector
	if ms.own_recoverable_hp_ratio < 0.25:
		return "defensive"
	if ms.opponent_state == GameEnums.CharacterState.ATTACKING:
		return "opportunistic"
	return ""
