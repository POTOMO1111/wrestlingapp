class_name AttackData
extends Resource

# ============================================================
#  AttackData.gd
#  打撃1種類のすべての数値・設定を格納するリソース。
#  .tres ファイルとしてエディタから値を設定して使う。
# ============================================================

# === 基本情報 ===
@export var attack_name: String = ""
@export var action_type: GameEnums.ActionType = GameEnums.ActionType.PUNCH

# === フレームデータ（60fps基準） ===
@export var startup_frames: int = 5    # 発生フレーム（入力→判定発生まで）
@export var active_frames: int = 3     # 判定持続フレーム
@export var recovery_frames: int = 10  # 硬直フレーム（判定消滅→次行動可能まで）

# === ダメージ ===
@export var recoverable_damage: float = 10.0  # 回復可能HPへのダメージ
@export var permanent_damage: float = 0.0     # 回復不可能HPへのダメージ（基本0）
@export var stamina_cost: float = 5.0         # 行動コスト（回復可能HPから消費）

# === ヒットボックス（CharacterBody3D相対位置） ===
@export var hitbox_size: Vector3 = Vector3(0.5, 0.5, 0.5)
@export var hitbox_offset: Vector3 = Vector3(0.0, 0.0, 0.8)

# === カウンター倍率 ===
@export var counter_hit_multiplier: float = 1.5

# === ヒットスタン ===
@export var hit_stun_frames: int = 12   # 被弾側の硬直フレーム数
@export var block_stun_frames: int = 5  # ガード成功側の硬直フレーム数

# === 有効距離 ===
@export var max_range: float = 1.5

# === アニメーション ===
@export var animation_name: String = ""

# === コンボキャンセル ===
@export var cancel_into: Array[GameEnums.ActionType] = []
