class_name AIStateOpportunistic
extends AIStateBase

# ============================================================
#  AIStateOpportunistic.gd
#  日和見的戦略ステート。初期デフォルト。
#  バランスの取れた行動。状況を見て攻守を切り替える。
# ============================================================

func get_weight_modifiers() -> Dictionary:
	return {}  # 補正なし（AIProfile の素の重みを使用）

func check_transition() -> String:
	var ms: MoveSelector = brain.move_selector
	if ms.own_recoverable_hp_ratio < 0.25:
		return "defensive"
	if ms.opponent_damage_ratio > 0.6:
		return "aggressive"
	if ms.own_recoverable_hp_ratio < 0.4 and ms.opponent_state == GameEnums.CharacterState.ATTACKING:
		return "defensive"
	return ""
