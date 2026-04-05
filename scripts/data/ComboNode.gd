class_name ComboNode
extends Resource

# ============================================================
#  ComboNode.gd
#  コンボツリーの1ノード。
#  combo_tree_root.tres としてツリー全体を定義する。
# ============================================================

@export var attack_data: AttackData = null

# Key: "PUNCH" or "KICK"、Value: ComboNode
@export var branches: Dictionary = {}

@export var hit_count: int = 1
@export var is_ender: bool = false
@export var ender_damage_multiplier: float = 1.3
@export var window_frames: int = 20  # コンボウィンドウ受付フレーム数
