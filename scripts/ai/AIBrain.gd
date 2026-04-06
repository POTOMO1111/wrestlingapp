class_name AIBrain
extends Node

# ============================================================
#  AIBrain.gd
#  CPU AI の意思決定中枢。
#  CPUController の子ノードとして動的生成される。
#  思考サイクルごとに MoveSelector で技を選び、
#  action_decided / movement_decided シグナルで CPUController に通知する。
# ============================================================

signal action_decided(action_key: String)
signal movement_decided(direction: Vector3, should_run: bool)

# --- 外部から設定（initialize() で代入） ---
var owner_body: CharacterBody3D
var opponent_body: CharacterBody3D
var combat_controller: Node
var opponent_combat_controller: Node
var ai_profile: AIProfile
var difficulty_profile: DifficultyProfile

# --- 子コンポーネント ---
var spatial: SpatialAwareness
var move_selector: MoveSelector

# --- AI戦略ステートマシン ---
var _strategy_states: Dictionary = {}        # {name: AIStateBase}
var _current_strategy: AIStateBase
var _current_strategy_name: String = "opportunistic"

# --- 思考タイマー ---
var _think_timer: float = 0.0
var _next_think_interval: float = 0.5
var last_think_delta: float = 0.0            # AIStateRecovery が参照する

# --- リアクション制御 ---
var _pending_reaction: String = ""
var _reaction_timer: float = 0.0

# --- コンボ制御 ---
var _in_combo: bool = false

# --- グラップル制御 ---
var _grapple_mash_timer: float = 0.0
const GRAPPLE_MASH_INTERVAL: float = 0.1    # register_input 呼び出し間隔（秒）

# --- RNG ---
var _rng := RandomNumberGenerator.new()

# ----------------------------------------------------------
# 初期化
# ----------------------------------------------------------

func _ready() -> void:
	_rng.randomize()

	# 子コンポーネント生成
	spatial = SpatialAwareness.new()
	spatial.name = "SpatialAwareness"
	add_child(spatial)

	move_selector = MoveSelector.new()
	move_selector.name = "MoveSelector"
	add_child(move_selector)

	# 戦略ステート生成
	_register_strategy("aggressive",    AIStateAggressive.new())
	_register_strategy("defensive",     AIStateDefensive.new())
	_register_strategy("opportunistic", AIStateOpportunistic.new())
	_register_strategy("recovery",      AIStateRecovery.new())

	_current_strategy = _strategy_states["opportunistic"]
	_current_strategy.enter()

func initialize(
	p_owner: CharacterBody3D,
	p_opponent: CharacterBody3D,
	p_combat_ctrl: Node,
	p_opponent_combat_ctrl: Node,
	p_ai_profile: AIProfile,
	p_difficulty: DifficultyProfile
) -> void:
	owner_body               = p_owner
	opponent_body            = p_opponent
	combat_controller        = p_combat_ctrl
	opponent_combat_controller = p_opponent_combat_ctrl
	ai_profile               = p_ai_profile
	difficulty_profile       = p_difficulty

	spatial.owner_body    = p_owner
	spatial.opponent_body = p_opponent

	move_selector.ai_profile  = p_ai_profile
	move_selector.difficulty  = p_difficulty
	move_selector.spatial     = spatial

	_next_think_interval = _rng.randf_range(
		difficulty_profile.think_interval_min,
		difficulty_profile.think_interval_max
	)

	# 相手のステート変化を検知してリアクティブ応答
	if p_opponent_combat_ctrl.has_signal("state_changed"):
		p_opponent_combat_ctrl.state_changed.connect(_on_opponent_state_changed)

	# コンボリセットの検知
	var combo_mgr := p_combat_ctrl.get_node_or_null("ComboManager")
	if combo_mgr and combo_mgr.has_signal("combo_reset"):
		combo_mgr.combo_reset.connect(_on_combo_reset)

	if GameManager.debug_mode:
		print("AIBrain initialized: profile=", p_ai_profile.resource_path,
			  " difficulty=", p_difficulty.resource_path)

# ----------------------------------------------------------
# メインループ
# ----------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not owner_body or not opponent_body:
		return

	var own_state := _get_own_state()

	# KO / ダウン系は何もしない
	if own_state in [
		GameEnums.CharacterState.KO,
		GameEnums.CharacterState.KNOCKDOWN,
		GameEnums.CharacterState.GETTING_UP,
		GameEnums.CharacterState.INCAPACITATED
	]:
		return

	# グラップル中の特殊処理
	if own_state in [
		GameEnums.CharacterState.GRAPPLING,
		GameEnums.CharacterState.GRAPPLED
	]:
		_handle_grapple_mashing(delta)
		return

	# リアクション待機中
	if _pending_reaction != "":
		_reaction_timer -= delta
		if _reaction_timer <= 0.0:
			_execute_reaction(_pending_reaction)
			_pending_reaction = ""
		return

	# 思考サイクル
	_think_timer += delta
	if _think_timer >= _next_think_interval:
		last_think_delta     = _think_timer
		_think_timer         = 0.0
		_next_think_interval = _rng.randf_range(
			difficulty_profile.think_interval_min,
			difficulty_profile.think_interval_max
		)
		_think_cycle()

# ----------------------------------------------------------
# 思考サイクル
# ----------------------------------------------------------

func _think_cycle() -> void:
	_update_move_selector_context()
	_update_strategy()

	# 戦略ステートの重み補正を MoveSelector にセット
	move_selector.set_strategy_modifiers(_current_strategy.get_weight_modifiers())

	# コンボウィンドウ中の継続判定
	var own_state := _get_own_state()
	if _in_combo and own_state == GameEnums.CharacterState.IDLE:
		var continuation = move_selector.decide_combo_continuation()
		if continuation != null:
			move_selector.advance_combo()
			action_decided.emit(_action_type_to_key(continuation))
			return
		else:
			_in_combo = false
			move_selector.reset_combo()

	# 通常の行動選択（IDLE / WALKING / RUNNING のみ）
	if own_state in [
		GameEnums.CharacterState.IDLE,
		GameEnums.CharacterState.WALKING,
		GameEnums.CharacterState.RUNNING
	]:
		var action_key := move_selector.select_action()
		move_selector.record_action(action_key)
		_execute_action(action_key)

# ----------------------------------------------------------
# コンテキスト更新
# ----------------------------------------------------------

func _update_move_selector_context() -> void:
	# 相手のダメージ割合
	var opp_health := opponent_combat_controller.get_node_or_null("HealthComponent")
	if opp_health:
		var rec_hp:  float = opp_health.current_recoverable_hp if "current_recoverable_hp" in opp_health else 100.0
		var rec_max: float = opp_health.max_recoverable_hp     if "max_recoverable_hp"     in opp_health else 100.0
		var perm_hp:  float = opp_health.current_permanent_hp  if "current_permanent_hp"   in opp_health else 100.0
		var perm_max: float = opp_health.max_permanent_hp      if "max_permanent_hp"       in opp_health else 100.0
		var total_max     := rec_max + perm_max
		var total_current := rec_hp + perm_hp
		move_selector.opponent_damage_ratio = 1.0 - (total_current / maxf(total_max, 1.0))

	# 自身の回復可能HP割合
	var own_health := combat_controller.get_node_or_null("HealthComponent")
	if own_health:
		var rec_hp:  float = own_health.current_recoverable_hp if "current_recoverable_hp" in own_health else 100.0
		var rec_max: float = own_health.max_recoverable_hp     if "max_recoverable_hp"     in own_health else 100.0
		move_selector.own_recoverable_hp_ratio = rec_hp / maxf(rec_max, 1.0)

	# 相手・自身のステート
	move_selector.opponent_state = _get_opponent_state()
	move_selector.own_state      = _get_own_state()

	# dominance（GrappleManager から取得）
	var grapple_mgr := _get_grapple_manager()
	if grapple_mgr and grapple_mgr.is_active:
		move_selector.current_dominance = grapple_mgr.dominance if "dominance" in grapple_mgr else 0.5

# ----------------------------------------------------------
# 戦略ステートマシン
# ----------------------------------------------------------

func _update_strategy() -> void:
	var next := _current_strategy.check_transition()
	if next != "" and next != _current_strategy_name and next in _strategy_states:
		_current_strategy.exit()
		_current_strategy_name = next
		_current_strategy      = _strategy_states[next]
		_current_strategy.enter()
		if GameManager.debug_mode:
			print("AIBrain strategy -> ", next)

# ----------------------------------------------------------
# 行動実行
# ----------------------------------------------------------

func _execute_action(action_key: String) -> void:
	match action_key:
		"punch_light", "punch_heavy", "kick_light", "kick_heavy", "grapple", "guard":
			if action_key == "grapple" and not spatial.is_opponent_in_grapple_range:
				# グラップル射程外なら接近
				movement_decided.emit(spatial.direction_to_opponent, true)
			else:
				action_decided.emit(action_key)
		"circle":
			movement_decided.emit(spatial.direction_to_opponent, false)
		"stall":
			movement_decided.emit(-spatial.direction_to_opponent, false)

# ----------------------------------------------------------
# リアクティブ応答
# ----------------------------------------------------------

func _on_opponent_state_changed(new_state: GameEnums.CharacterState) -> void:
	match new_state:
		GameEnums.CharacterState.ATTACKING:
			if _rng.randf() < difficulty_profile.counter_probability:
				_queue_reaction("guard")
		GameEnums.CharacterState.GRAPPLING:
			if _rng.randf() < difficulty_profile.grapple_counter_probability:
				_queue_reaction("guard")

func _queue_reaction(reaction: String) -> void:
	if _pending_reaction != "":
		return
	_pending_reaction = reaction
	_reaction_timer = _rng.randf_range(
		difficulty_profile.reaction_delay_min,
		difficulty_profile.reaction_delay_max
	)

func _execute_reaction(reaction: String) -> void:
	match reaction:
		"guard":
			action_decided.emit("guard")

# ----------------------------------------------------------
# グラップル中の連打処理
# ----------------------------------------------------------

func _handle_grapple_mashing(delta: float) -> void:
	_grapple_mash_timer += delta
	if _grapple_mash_timer >= GRAPPLE_MASH_INTERVAL:
		_grapple_mash_timer = 0.0
		if _rng.randf() < difficulty_profile.grapple_mash_rate:
			var grapple_mgr := _get_grapple_manager()
			if grapple_mgr and grapple_mgr.is_active:
				grapple_mgr.register_input(owner_body.player_id)

# ----------------------------------------------------------
# コンボリセット
# ----------------------------------------------------------

func _on_combo_reset() -> void:
	_in_combo = false
	move_selector.reset_combo()

# ----------------------------------------------------------
# ヘルパー
# ----------------------------------------------------------

func _get_own_state() -> GameEnums.CharacterState:
	if combat_controller and combat_controller.has_method("get_current_state"):
		return combat_controller.get_current_state()
	return GameEnums.CharacterState.IDLE

func _get_opponent_state() -> GameEnums.CharacterState:
	if opponent_combat_controller and opponent_combat_controller.has_method("get_current_state"):
		return opponent_combat_controller.get_current_state()
	return GameEnums.CharacterState.IDLE

func _get_grapple_manager() -> Node:
	var fm := owner_body.get_tree().get_first_node_in_group("fight_manager")
	if fm:
		return fm.get_node_or_null("GrappleManager")
	return null

func _action_type_to_key(action_type: GameEnums.ActionType) -> String:
	match action_type:
		GameEnums.ActionType.PUNCH:  return "punch_light"
		GameEnums.ActionType.KICK:   return "kick_light"
		GameEnums.ActionType.GRAPPLE: return "grapple"
		GameEnums.ActionType.GUARD:  return "guard"
		_: return "stall"

func _register_strategy(sname: String, state: AIStateBase) -> void:
	state.brain = self
	state.name  = "AIState_" + sname
	add_child(state)
	_strategy_states[sname] = state
