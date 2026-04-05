class_name InputHandler
extends Node

# ============================================================
#  InputHandler.gd
#  プレイヤーキャラクターの子ノードとしてアタッチ。
#  _input イベントドリブンで CombatController に渡す。
# ============================================================

@export var player_id: GameEnums.PlayerID = GameEnums.PlayerID.PLAYER_ONE

var _combat_controller: CombatController = null

## DebugOverlay がこのシグナルを接続して画面上にログを表示する
signal input_received(action: GameEnums.ActionType)

func _ready() -> void:
	# CombatController は兄弟ノードとして存在する
	_combat_controller = get_parent().get_node_or_null("CombatController")
	if GameManager.debug_mode:
		print("[InputHandler] _ready — parent=%s ctrl=%s" % [get_parent().name, str(_combat_controller)])
		if _combat_controller == null:
			print("[InputHandler] ERROR: CombatController not found! Children of parent:")
			for c in get_parent().get_children():
				print("  - %s" % c.name)

## _input はフレームレートに依存せず確実に押下を1回だけ検出できる
func _input(event: InputEvent) -> void:
	if _combat_controller == null:
		return
	# echo（キーリピート）は無視
	if event is InputEventKey and event.is_echo():
		return

	if event.is_action_pressed("attack light"):
		_send(GameEnums.ActionType.PUNCH)

	elif event.is_action_pressed("attack heavy"):
		_send(GameEnums.ActionType.KICK)

	elif event.is_action_pressed("grapple"):
		_send(GameEnums.ActionType.GRAPPLE)

	# ガード開始
	if event.is_action_pressed("block"):
		_send(GameEnums.ActionType.GUARD)

func _send(action: GameEnums.ActionType) -> void:
	if GameManager.debug_mode:
		print("[InputHandler:%s] → %s" % [get_parent().name, GameEnums.ActionType.keys()[action]])
	input_received.emit(action)
	_combat_controller.receive_input(action)
