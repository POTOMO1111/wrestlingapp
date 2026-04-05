class_name BaseState
extends Node

# ============================================================
#  BaseState.gd
#  CombatController が管理するステートの基底クラス。
# ============================================================

var combat_controller: Node = null

func enter(_prev_state: GameEnums.CharacterState) -> void:
	pass

func exit(_next_state: GameEnums.CharacterState) -> void:
	pass

func update(_delta: float) -> void:
	pass

func handle_input(_action: GameEnums.ActionType) -> void:
	pass
