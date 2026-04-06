class_name AIProfile
extends Resource

# ============================================================
#  AIProfile.gd
#  レスラーの「性格・行動傾向」を定義するリソース。
#  難易度（DifficultyProfile）とは独立し、「何をしたいか」を決定する。
# ============================================================

# --- 性格パラメータ (0.0〜1.0) ---
@export_group("性格")
@export_range(0.0, 1.0) var aggression: float = 0.5
## 攻撃性。高いほど攻め時間が長く、stall/circleが少ない。

@export_range(0.0, 1.0) var grapple_preference: float = 0.5
## グラップル嗜好。高いほどグラップルを優先、低いほど打撃を優先。

@export_range(0.0, 1.0) var risk_taking: float = 0.5
## リスク嗜好。高いほど大技を序盤から使い、ヘビー攻撃を多用する。

@export_range(0.0, 1.0) var showmanship: float = 0.3
## 見せ場作り。高いほどコンボエンダーや大技前にstallを挟む。

@export_range(0.0, 1.0) var discretion: float = 0.5
## 慎重さ。高いほどリング中央を好み、呼吸休憩を入れる。

# --- ダメージ段階別行動重み ---
# action_key: "punch_light","punch_heavy","kick_light","kick_heavy",
#             "grapple","guard","circle","stall"
# 値は相対的な重み（正規化して使用するため合計は問わない）

@export_group("ダメージ段階別行動重み")
@export var weights_early: Dictionary = {
	"punch_light": 30, "punch_heavy": 5, "kick_light": 25, "kick_heavy": 5,
	"grapple": 10, "guard": 5, "circle": 15, "stall": 5
}
## 序盤（相手被ダメ 0〜25%）の行動重み

@export var weights_mid: Dictionary = {
	"punch_light": 20, "punch_heavy": 15, "kick_light": 15, "kick_heavy": 15,
	"grapple": 20, "guard": 5, "circle": 5, "stall": 5
}
## 中盤（相手被ダメ 25〜50%）の行動重み

@export var weights_late: Dictionary = {
	"punch_light": 10, "punch_heavy": 20, "kick_light": 10, "kick_heavy": 20,
	"grapple": 25, "guard": 5, "circle": 5, "stall": 5
}
## 終盤（相手被ダメ 50〜75%）の行動重み

@export var weights_critical: Dictionary = {
	"punch_light": 5, "punch_heavy": 25, "kick_light": 5, "kick_heavy": 25,
	"grapple": 30, "guard": 0, "circle": 5, "stall": 5
}
## 決定的局面（相手被ダメ 75〜100%）の行動重み

# --- コンボ傾向 ---
@export_group("コンボ傾向")
@export var preferred_combo_routes: Array[String] = ["PPK", "KKP"]
## 好みのコンボルート（エンダーまでの入力列）
## "PPK" = PUNCH→PUNCH→KICK(ender)

@export_range(0.0, 1.0) var combo_attempt_rate: float = 0.7
## コンボウィンドウ中に継続入力を試みる確率

# --- 特徴的パターン ---
@export_group("特徴的パターン")
@export_enum("none", "strike_strike_grapple", "grapple_after_guard", "heavy_opener") \
	var signature_pattern: String = "strike_strike_grapple"
## AIの癖。プレイヤーが学習して罰することができるパターン。
## "strike_strike_grapple": 2回打撃後にグラップルを仕掛ける
## "grapple_after_guard": ガード成功後に必ずグラップル
## "heavy_opener": 開幕に必ずヘビー攻撃

@export_range(0.0, 1.0) var pattern_frequency: float = 0.4
## 特徴的パターンの発動頻度
