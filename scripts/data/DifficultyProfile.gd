class_name DifficultyProfile
extends Resource

# ============================================================
#  DifficultyProfile.gd
#  難易度の「実行精度」を定義するリソース。
#  レスラーの性格（AIProfile）とは独立。
# ============================================================

# --- 反応速度 ---
@export_group("反応速度")
@export var reaction_delay_min: float = 0.1
## 反応遅延の最小値（秒）。攻撃検知→ガード/回避判断までの遅延。

@export var reaction_delay_max: float = 0.5
## 反応遅延の最大値（秒）。この範囲内でランダムに決定。

# --- カウンター能力 ---
@export_group("カウンター能力")
@export_range(0.0, 1.0) var counter_probability: float = 0.3
## 相手の攻撃にカウンター（ガード or 回避行動）を試みる確率。

@export_range(0.0, 1.0) var grapple_counter_probability: float = 0.25
## 相手のグラップル開始に対してガードで防ぐ確率。

# --- コンボ実行 ---
@export_group("コンボ実行")
@export_range(0.0, 1.0) var combo_execution_rate: float = 0.65
## コンボの各ステップを成功させる確率。失敗するとコンボが途切れIDLEに戻る。

@export_range(0.0, 1.0) var optimal_move_selection: float = 0.5
## ユーティリティスコア最高の技を選ぶ確率。
## 残りの確率で重み付きランダム選択にフォールバック。

# --- 戦略深度 ---
@export_group("戦略深度")
@export var enables_body_part_targeting: bool = false
## true: 弱った部位（回復可能HPが低い方）を狙う行動をとる

@export var enables_pattern_adaptation: bool = false
## true: プレイヤーの行動パターンを記録し対応を変える

@export_range(0.0, 1.0) var input_read_probability: float = 0.0
## スタートアップフレーム中の相手の行動を「読む」確率（Expert以上のみ非ゼロ）

# --- グラップルドミナンス ---
@export_group("グラップルドミナンス")
@export_range(0.0, 1.0) var grapple_mash_rate: float = 0.0
## グラップル中にCPUがregister_input()を呼ぶ頻度（/0.1sec）。
## 0.0=全く入力しない（decayのみで抵抗）, 1.0=毎インターバル入力

@export_range(0.0, 1.0) var grapple_initiate_accuracy: float = 0.5
## グラップル開始の適切なタイミング判定の精度。高いほど相手の隙を正確に突く。

# --- フェーズ制御 ---
@export_group("フェーズ制御")
@export var reposition_duration: float = 0.7
## REPOSITIONフェーズの持続時間（秒）。短いほど立て直しが速く攻撃的になる。
