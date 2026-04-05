class_name GrappleData
extends Resource

# ============================================================
#  GrappleData.gd
#  グラップル技1種類の数値・設定リソース。
# ============================================================

@export var grapple_name: String = ""

# === フレームデータ ===
@export var startup_frames: int = 18   # グラップルはパンチより発生が遅い
@export var active_frames: int = 5     # 掴み判定持続
@export var recovery_frames: int = 20  # 失敗時の硬直

# === ダメージ（成立時） ===
@export var permanent_damage: float = 15.0   # 回復不可能HPへのダメージ
@export var recoverable_damage: float = 5.0  # 回復可能HPにも若干ダメージ
@export var stamina_cost: float = 12.0

# === dominance への影響 ===
@export var dominance_gain: float = 0.25
@export var dominance_damage_threshold: float = 0.7  # この値以上でダメージ発生

# === グラップル判定 ===
@export var max_range: float = 1.2
@export var can_bypass_guard: bool = true  # ガード貫通（常にtrue）
@export var hitbox_size: Vector3 = Vector3(0.6, 0.8, 0.6)
@export var hitbox_offset: Vector3 = Vector3(0.0, 0.5, 0.8)

# === アニメーション ===
@export var initiator_animation: String = ""
@export var receiver_animation: String = ""

# === dominance 中の追加ダメージ倍率 ===
@export var dominant_damage_multiplier: float = 1.4
