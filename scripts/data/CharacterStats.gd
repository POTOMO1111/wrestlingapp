class_name CharacterStats
extends Resource

# ============================================================
#  CharacterStats.gd
#  キャラクター固有のステータスリソース。
# ============================================================

@export var character_name: String = "Fighter"

# === 体力設定 ===
@export var max_recoverable_hp: float = 100.0  # 回復可能HP（打撃ダメージ先、白ゲージ）
@export var max_permanent_hp: float = 100.0    # 回復不可能HP（グラップルダメージ先、赤ゲージ）

# === 回復設定 ===
@export var recoverable_hp_regen_rate: float = 5.0     # 毎秒回復量
@export var recoverable_hp_regen_delay: float = 2.5    # 最後にダメージを受けてから回復開始するまでの秒数

# === 行動不可状態設定 ===
@export var incapacitated_duration: float = 3.0                 # 行動不可継続秒数
@export var incapacitated_dominance_penalty: float = 0.6        # 行動不可中のdominance倍率

# === 基礎ステータス ===
@export var punch_damage_multiplier: float = 1.0
@export var kick_damage_multiplier: float = 1.0
@export var grapple_damage_multiplier: float = 1.0
@export var defense_multiplier: float = 1.0      # 受けるダメージへの乗数（1.0=等倍）
@export var dominance_gain_rate: float = 1.0     # dominance蓄積速度の倍率
