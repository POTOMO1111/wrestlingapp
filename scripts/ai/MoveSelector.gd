class_name MoveSelector
extends Node

# ============================================================
#  MoveSelector.gd
#  ユーティリティスコアリング + 重み付きランダム選択で技を決定する。
#  AIProfile の重みテーブルをベースに、SpatialAwareness の状況で補正。
#  DifficultyProfile の optimal_move_selection で最適解選択確率を制御。
# ============================================================

# --- 外部参照（AIBrain.initialize() で代入） ---
var ai_profile: AIProfile
var difficulty: DifficultyProfile
var spatial: SpatialAwareness

# --- 相手・自身の状態（AIBrain が毎思考サイクルでセット） ---
var opponent_damage_ratio: float = 0.0       # 相手の被ダメ割合 (0.0〜1.0)
var opponent_state: GameEnums.CharacterState = GameEnums.CharacterState.IDLE
var own_state: GameEnums.CharacterState = GameEnums.CharacterState.IDLE
var own_recoverable_hp_ratio: float = 1.0
var current_dominance: float = 0.5

# --- コンボ追跡 ---
var combo_position: int = 0
var _current_combo_route: String = ""
var _last_actions: Array[String] = []
const MAX_ACTION_HISTORY: int = 10

# --- RNG ---
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()

# ----------------------------------------------------------
# メイン技選択
# ----------------------------------------------------------

## action_key 文字列を返す。
## "punch_light","punch_heavy","kick_light","kick_heavy","grapple","guard","circle","stall"
func select_action() -> String:
	var base_weights := _get_damage_tier_weights()
	var scored_weights := _apply_context_modifiers(base_weights)
	scored_weights = _apply_signature_pattern(scored_weights)
	scored_weights = _apply_strategy_modifiers(scored_weights)

	if _rng.randf() < difficulty.optimal_move_selection:
		return _pick_highest(scored_weights)
	else:
		return _pick_weighted_random(scored_weights)

# ----------------------------------------------------------
# コンボ制御
# ----------------------------------------------------------

## コンボウィンドウ中に呼ばれる。次に入力すべき ActionType を返す。null でコンボ中断。
func decide_combo_continuation() -> Variant:
	if _rng.randf() > ai_profile.combo_attempt_rate:
		return null
	if _rng.randf() > difficulty.combo_execution_rate:
		return null

	if _current_combo_route.length() > combo_position:
		var next_char := _current_combo_route[combo_position]
		match next_char:
			"P": return GameEnums.ActionType.PUNCH
			"K": return GameEnums.ActionType.KICK

	# ルートが尽きたかルート未設定ならランダム
	return [GameEnums.ActionType.PUNCH, GameEnums.ActionType.KICK].pick_random()

## コンボ開始時に呼ぶ。使用ルートを決定する。
func begin_combo() -> void:
	combo_position = 0
	if ai_profile.preferred_combo_routes.size() > 0:
		_current_combo_route = ai_profile.preferred_combo_routes.pick_random()
	else:
		_current_combo_route = ["PPP", "PPK", "PKP", "PKK", "KPP", "KPK", "KKP", "KKK"].pick_random()

## コンボ段階を進める
func advance_combo() -> void:
	combo_position += 1

## コンボリセット
func reset_combo() -> void:
	combo_position = 0
	_current_combo_route = ""

## 行動履歴に追加
func record_action(action_key: String) -> void:
	_last_actions.append(action_key)
	if _last_actions.size() > MAX_ACTION_HISTORY:
		_last_actions.pop_front()

# ----------------------------------------------------------
# 戦略ステートからの重み補正を受け付ける（AIBrain経由で呼ぶ）
# ----------------------------------------------------------
var _strategy_modifiers: Dictionary = {}

func set_strategy_modifiers(modifiers: Dictionary) -> void:
	_strategy_modifiers = modifiers

# ----------------------------------------------------------
# 内部: 重みテーブル構築
# ----------------------------------------------------------

## 相手ダメージ割合から該当する重みテーブルを補間取得
func _get_damage_tier_weights() -> Dictionary:
	if opponent_damage_ratio < 0.25:
		return ai_profile.weights_early.duplicate()
	elif opponent_damage_ratio < 0.50:
		return _lerp_weights(ai_profile.weights_early, ai_profile.weights_mid,
			(opponent_damage_ratio - 0.25) / 0.25)
	elif opponent_damage_ratio < 0.75:
		return _lerp_weights(ai_profile.weights_mid, ai_profile.weights_late,
			(opponent_damage_ratio - 0.50) / 0.25)
	else:
		return _lerp_weights(ai_profile.weights_late, ai_profile.weights_critical,
			(opponent_damage_ratio - 0.75) / 0.25)

## 2つの重みテーブルを線形補間
func _lerp_weights(a: Dictionary, b: Dictionary, t: float) -> Dictionary:
	var result := {}
	for key in a.keys():
		var va: float = float(a.get(key, 0))
		var vb: float = float(b.get(key, 0))
		result[key] = va + (vb - va) * t
	return result

## 空間・状況に基づくコンテキスト補正
func _apply_context_modifiers(weights: Dictionary) -> Dictionary:
	var w := weights.duplicate()

	# 距離ベース補正
	if not spatial.is_opponent_in_strike_range:
		for key in ["punch_light", "punch_heavy", "kick_light", "kick_heavy"]:
			w[key] = w.get(key, 0.0) * 0.1
		w["circle"] = w.get("circle", 0.0) * 3.0

	if not spatial.is_opponent_in_grapple_range:
		w["grapple"] = w.get("grapple", 0.0) * 0.2

	# リングポジション補正
	if spatial.is_in_corner:
		w["circle"] = w.get("circle", 0.0) * 2.5
		w["guard"] = w.get("guard", 0.0) * 1.5

	if spatial.is_opponent_in_corner:
		for key in ["punch_heavy", "kick_heavy", "grapple"]:
			w[key] = w.get(key, 0.0) * 1.5

	# 相手ステートベース補正
	match opponent_state:
		GameEnums.CharacterState.HIT_STUN:
			for key in ["punch_light", "punch_heavy", "kick_light", "kick_heavy"]:
				w[key] = w.get(key, 0.0) * 2.0
			w["grapple"] = w.get("grapple", 0.0) * 0.3

		GameEnums.CharacterState.KNOCKDOWN, GameEnums.CharacterState.GETTING_UP:
			w["circle"] = w.get("circle", 0.0) * 2.0
			w["stall"] = w.get("stall", 0.0) * 1.5

		GameEnums.CharacterState.INCAPACITATED:
			w["grapple"] = w.get("grapple", 0.0) * 4.0

		GameEnums.CharacterState.ATTACKING:
			w["guard"] = w.get("guard", 0.0) * 3.0

	# 自身の体力ベース補正
	if own_recoverable_hp_ratio < 0.3:
		w["guard"] = w.get("guard", 0.0) * 2.0
		w["stall"] = w.get("stall", 0.0) * 2.0
		for key in ["punch_heavy", "kick_heavy"]:
			w[key] = w.get(key, 0.0) * 0.5

	# ドミナンス補正
	if current_dominance > 0.6:
		w["grapple"] = w.get("grapple", 0.0) * 1.8
	elif current_dominance < 0.4:
		w["grapple"] = w.get("grapple", 0.0) * 0.5

	# 性格パラメータ最終補正
	w["guard"] = w.get("guard", 0.0) * (1.0 + ai_profile.discretion)
	w["stall"] = w.get("stall", 0.0) * (1.0 + ai_profile.discretion)
	w["grapple"] = w.get("grapple", 0.0) * (1.0 + ai_profile.grapple_preference)
	for key in ["punch_light", "punch_heavy", "kick_light", "kick_heavy"]:
		w[key] = w.get(key, 0.0) * (1.0 + (1.0 - ai_profile.grapple_preference))

	return w

## 特徴的パターンの発動チェックと重み修正
func _apply_signature_pattern(weights: Dictionary) -> Dictionary:
	if ai_profile.signature_pattern == "none":
		return weights
	if _rng.randf() > ai_profile.pattern_frequency:
		return weights

	var w := weights.duplicate()
	match ai_profile.signature_pattern:
		"strike_strike_grapple":
			if _last_actions.size() >= 2:
				var recent := _last_actions.slice(-2)
				var strikes := ["punch_light", "punch_heavy", "kick_light", "kick_heavy"]
				if recent[0] in strikes and recent[1] in strikes:
					w["grapple"] = w.get("grapple", 0.0) * 5.0
		"grapple_after_guard":
			if _last_actions.size() >= 1 and _last_actions[-1] == "guard":
				w["grapple"] = w.get("grapple", 0.0) * 5.0
		"heavy_opener":
			if _last_actions.size() == 0:
				w["punch_heavy"] = w.get("punch_heavy", 0.0) * 3.0
				w["kick_heavy"] = w.get("kick_heavy", 0.0) * 3.0
	return w

## 戦略ステートの乗数補正を適用
func _apply_strategy_modifiers(weights: Dictionary) -> Dictionary:
	if _strategy_modifiers.is_empty():
		return weights
	var w := weights.duplicate()
	for key in _strategy_modifiers:
		if w.has(key):
			w[key] = w[key] * float(_strategy_modifiers[key])
	return w

# ----------------------------------------------------------
# 内部: 選択
# ----------------------------------------------------------

## 最高重みの action_key を返す
func _pick_highest(weights: Dictionary) -> String:
	var best_key := "stall"
	var best_val := -1.0
	for key in weights:
		if float(weights[key]) > best_val:
			best_val = float(weights[key])
			best_key = key
	return best_key

## 重み付きランダムで action_key を返す
func _pick_weighted_random(weights: Dictionary) -> String:
	var total := 0.0
	for key in weights:
		total += maxf(float(weights[key]), 0.0)
	if total <= 0.0:
		return "stall"
	var roll := _rng.randf() * total
	var cumulative := 0.0
	for key in weights:
		cumulative += maxf(float(weights[key]), 0.0)
		if roll <= cumulative:
			return key
	return weights.keys()[-1]
