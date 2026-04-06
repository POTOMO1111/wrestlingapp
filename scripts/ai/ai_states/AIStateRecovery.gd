class_name AIStateRecovery
extends AIStateBase

# ============================================================
#  AIStateRecovery.gd
#  回復戦略ステート。
#  INCAPACITATED から復帰した直後や体力が危険域の時。
#  時間稼ぎ（stall/circle）を最優先し、回復可能HPのリジェンを待つ。
# ============================================================

var _recovery_timer: float = 0.0
const RECOVERY_DURATION: float = 3.0  # 回復ステート最低滞在時間（秒）

func enter() -> void:
	_recovery_timer = 0.0

func get_weight_modifiers() -> Dictionary:
	return {
		"stall": 4.0, "circle": 3.0, "guard": 2.0,
		"punch_light": 0.3, "punch_heavy": 0.1,
		"kick_light": 0.3, "kick_heavy": 0.1, "grapple": 0.1
	}

func check_transition() -> String:
	_recovery_timer += brain.last_think_delta
	if _recovery_timer < RECOVERY_DURATION:
		return ""
	var ms: MoveSelector = brain.move_selector
	if ms.own_recoverable_hp_ratio > 0.4:
		return "opportunistic"
	if ms.own_recoverable_hp_ratio > 0.25:
		return "defensive"
	return ""
