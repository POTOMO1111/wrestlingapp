class_name ComboManager
extends Node

# ============================================================
#  ComboManager.gd
#  キャラクターノードの子ノードとしてアタッチ。
#  P/K の最大3入力コンボツリーを追跡・管理する。
# ============================================================

@export var combo_tree_root: ComboNode

var _current_node:  ComboNode = null
var _window_timer:  int  = 0
var _window_open:   bool = false

signal combo_attack_resolved(attack: AttackData, is_ender: bool, ender_multiplier: float)
signal combo_reset()

func _physics_process(_delta: float) -> void:
	if _window_open and _window_timer > 0:
		_window_timer -= 1
		if _window_timer <= 0:
			reset_combo()

## コンボウィンドウを開く（StateAttacking の active→recovery 遷移時に呼ぶ）
func open_combo_window() -> void:
	if _current_node == null:
		return
	_window_timer = _current_node.window_frames
	_window_open  = true

## コンボウィンドウを閉じる（recovery 終了時に呼ぶ）
func close_combo_window() -> void:
	_window_open = false
	if _current_node != null and not _current_node.is_ender:
		reset_combo()

## 打撃入力を受け付ける。
## 戻り値: 実行すべき AttackData（コンボ継続）または null（コンボ不成立）
func try_input(action: GameEnums.ActionType) -> AttackData:
	var key = _action_to_key(action)
	if key == "":
		return null

	# combo_tree_root 未設定時はデフォルトアタックリソースで代替
	if combo_tree_root == null:
		return _load_default_attack(action)

	if _current_node == null:
		# コンボ未開始 → ルートから検索
		if not combo_tree_root.branches.has(key):
			return _load_default_attack(action)
		_current_node = combo_tree_root.branches[key]
		return _resolve_node()
	else:
		# コンボ継続中 → ウィンドウ内かチェック
		if _window_open and _current_node.branches.has(key):
			_current_node = _current_node.branches[key]
			return _resolve_node()
		else:
			# ウィンドウ外 or 繋がらない → リセットして単発として再試行
			reset_combo()
			return try_input(action)

func _load_default_attack(action: GameEnums.ActionType) -> AttackData:
	match action:
		GameEnums.ActionType.PUNCH:
			var a = load("res://resources/attacks/punch_light.tres")
			if GameManager.debug_mode:
				print("[ComboManager] _load_default_attack PUNCH → %s" % str(a))
			return a if a != null else null
		GameEnums.ActionType.KICK:
			var a = load("res://resources/attacks/kick_light.tres")
			if GameManager.debug_mode:
				print("[ComboManager] _load_default_attack KICK → %s" % str(a))
			return a if a != null else null
	if GameManager.debug_mode:
		print("[ComboManager] _load_default_attack: action=%s → null (no match)" % str(action))
	return null

func reset_combo() -> void:
	_current_node = null
	_window_open  = false
	_window_timer = 0
	combo_reset.emit()

# ----------------------------------------------------------
# 内部ユーティリティ
# ----------------------------------------------------------

func _resolve_node() -> AttackData:
	var atk = _current_node.attack_data
	if _current_node.is_ender:
		combo_attack_resolved.emit(atk, true, _current_node.ender_damage_multiplier)
		reset_combo()
	else:
		combo_attack_resolved.emit(atk, false, 1.0)
	return atk

func _action_to_key(action: GameEnums.ActionType) -> String:
	match action:
		GameEnums.ActionType.PUNCH: return "PUNCH"
		GameEnums.ActionType.KICK:  return "KICK"
	return ""
