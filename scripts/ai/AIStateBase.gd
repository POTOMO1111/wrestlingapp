class_name AIStateBase
extends Node

# ============================================================
#  AIStateBase.gd
#  AI戦略ステートの基底クラス。
#  AIBrain の子ノードとして配置され、戦略レベルの判断を行う。
# ============================================================

var brain: Node  # AIBrain への参照（_register_strategy() でセット）

## ステートに入った時
func enter() -> void:
	pass

## ステートから出る時
func exit() -> void:
	pass

## 思考サイクルで適用する action_key 乗数テーブルを返す。
## 空の Dictionary を返すと補正なし。
func get_weight_modifiers() -> Dictionary:
	return {}

## 遷移判定。遷移先ステート名を返す。空文字列なら遷移なし。
func check_transition() -> String:
	return ""
