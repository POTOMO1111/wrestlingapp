class_name FightManager
extends Node

# ============================================================
#  FightManager.gd
#  main.tscn の子ノードとしてアタッチ。
#  グループ "fight_manager" に追加すること。
#  試合・ラウンドの進行とヒット処理を一元管理する。
# ============================================================

@export var max_rounds: int = 1
@export var round_time: float = 99.0

# キャラクターノード（main.gd が動的生成後に set_fighters() で渡す）
var player1: Node = null
var player2: Node = null

@onready var grapple_manager: GrappleManager = $GrappleManager

var current_round: int = 1
var round_state: GameEnums.RoundState = GameEnums.RoundState.WAITING
var round_timer: float = 0.0
var p1_wins: int = 0
var p2_wins: int = 0

signal round_started(round_number: int)
signal round_ended(winner_id: GameEnums.PlayerID)
signal match_ended(winner_id: GameEnums.PlayerID)
signal ko_triggered(loser: Node)
signal timer_updated(time_remaining: float)

func _ready() -> void:
	add_to_group("fight_manager")
	grapple_manager.grapple_ended.connect(_on_grapple_ended)

func _physics_process(delta: float) -> void:
	if round_state != GameEnums.RoundState.FIGHTING:
		return
	round_timer = max(0.0, round_timer - delta)
	timer_updated.emit(round_timer)
	if round_timer <= 0.0:
		_on_round_timeout()

## キャラクターを登録して試合開始（main.gd から呼ぶ）
func set_fighters(p1: Node, p2: Node) -> void:
	player1 = p1
	player2 = p2

	var p1_health: HealthComponent = p1.get_node_or_null("CombatController/HealthComponent")
	var p2_health: HealthComponent = p2.get_node_or_null("CombatController/HealthComponent")

	if p1_health:
		p1_health.permanent_hp_depleted.connect(func(): _on_ko(p1, p2))
	if p2_health:
		p2_health.permanent_hp_depleted.connect(func(): _on_ko(p2, p1))

	start_round()

func start_round() -> void:
	round_timer = round_time
	round_state = GameEnums.RoundState.FIGHTING

	_reset_character(player1)
	_reset_character(player2)

	# スポーン位置リセット（リング上）
	player1.global_position = Vector3(0, 1.2, 2.0)
	player2.global_position = Vector3(0, 1.2, -2.0)
	player2.look_at(player1.global_position, Vector3.UP)

	round_started.emit(current_round)

# ----------------------------------------------------------
# ヒット処理（CombatController._on_hit_landed から呼ばれる）
# ----------------------------------------------------------

func process_hit(
	attacker_ctrl: Node,
	target: Node,
	attack: AttackData,
	result: GameEnums.HitResult
) -> void:
	if round_state != GameEnums.RoundState.FIGHTING:
		return

	var attacker_char = attacker_ctrl.get_parent()
	var attacker_health: HealthComponent = attacker_ctrl.get_node_or_null("HealthComponent")
	var target_ctrl:     CombatController = target.get_node_or_null("CombatController")
	var target_health:   HealthComponent  = target_ctrl.get_node_or_null("HealthComponent") if target_ctrl else null

	if attacker_health == null or target_health == null or target_ctrl == null:
		if GameManager.debug_mode:
			print("[FightManager.process_hit] EARLY RETURN — attacker_health=%s target_ctrl=%s target_health=%s | target.name=%s" % [
				str(attacker_health), str(target_ctrl), str(target_health), target.name if target else "null"
			])
		return

	# コンボエンダー倍率を取得してリセット（コンボ3ヒット目のみ 1.3 倍等が入る）
	var ender_mult: float = attacker_ctrl._ender_damage_multiplier
	attacker_ctrl._ender_damage_multiplier = 1.0

	# ダメージ計算
	var dmg = DamageCalculator.calculate_attack_damage(
		attack, result, attacker_health.stats, target_health.stats
	)
	dmg["recoverable"] *= ender_mult
	dmg["permanent"]   *= ender_mult

	if GameManager.debug_mode:
		print("[FightManager.process_hit] attacker=%s target=%s rec=%.1f perm=%.1f" % [
			attacker_char.name if attacker_char else "?", target.name, dmg["recoverable"], dmg["permanent"]
		])
	if dmg["recoverable"] > 0.0:
		target_health.take_damage(dmg["recoverable"], GameEnums.DamageLayer.RECOVERABLE)
	if dmg["permanent"] > 0.0:
		target_health.take_damage(dmg["permanent"], GameEnums.DamageLayer.PERMANENT)

	# ヒットスタン or ブロックスタン
	target_ctrl._pending_hit_stun_frames = attack.hit_stun_frames if result != GameEnums.HitResult.BLOCKED else attack.block_stun_frames
	target_ctrl.transition_to(GameEnums.CharacterState.HIT_STUN)

# ----------------------------------------------------------
# グラップル開始処理（CombatController._on_grapple_initiated から呼ばれる）
# ----------------------------------------------------------

func process_grapple_start(initiator_ctrl: CombatController, target: Node, grapple: GrappleData) -> void:
	if round_state != GameEnums.RoundState.FIGHTING:
		return
	if grapple_manager.is_active:
		return

	var initiator_char = initiator_ctrl.get_parent()
	var target_ctrl: CombatController = target.get_node_or_null("CombatController")
	if target_ctrl == null:
		return

	grapple_manager.start_grapple(initiator_char, target, grapple)
	initiator_ctrl.transition_to(GameEnums.CharacterState.GRAPPLING)
	target_ctrl.transition_to(GameEnums.CharacterState.GRAPPLED)

# ----------------------------------------------------------
# シグナルハンドラ
# ----------------------------------------------------------

func _on_grapple_ended(_winner: Node, _loser: Node) -> void:
	for p in [player1, player2]:
		if p == null:
			continue
		var ctrl: CombatController = p.get_node_or_null("CombatController")
		if ctrl:
			var st = ctrl.get_current_state()
			if st == GameEnums.CharacterState.GRAPPLING or st == GameEnums.CharacterState.GRAPPLED:
				ctrl.transition_to(GameEnums.CharacterState.IDLE)
		# 旧 PlayerController の GRAPPLE_LOCK 状態も確実にリセットする
		if p.has_method("exit_grapple_lock"):
			p.exit_grapple_lock()

func _on_ko(loser: Node, winner: Node) -> void:
	if round_state != GameEnums.RoundState.FIGHTING:
		return
	round_state = GameEnums.RoundState.ROUND_END
	ko_triggered.emit(loser)

	var winner_id = GameEnums.PlayerID.PLAYER_ONE if winner == player1 else GameEnums.PlayerID.PLAYER_TWO
	if winner == player1:
		p1_wins += 1
	else:
		p2_wins += 1
	round_ended.emit(winner_id)

	var wins_needed = (max_rounds / 2) + 1
	if p1_wins >= wins_needed:
		match_ended.emit(GameEnums.PlayerID.PLAYER_ONE)
	elif p2_wins >= wins_needed:
		match_ended.emit(GameEnums.PlayerID.PLAYER_TWO)
	else:
		current_round += 1
		# KOSequenceManager が演出後に start_round() を呼ぶ

func _on_round_timeout() -> void:
	if round_state != GameEnums.RoundState.FIGHTING:
		return
	round_state = GameEnums.RoundState.ROUND_END
	var p1_hp = _get_permanent_hp(player1)
	var p2_hp = _get_permanent_hp(player2)
	var winner_id = GameEnums.PlayerID.PLAYER_ONE if p1_hp >= p2_hp else GameEnums.PlayerID.PLAYER_TWO

	if winner_id == GameEnums.PlayerID.PLAYER_ONE:
		p1_wins += 1
	else:
		p2_wins += 1
	round_ended.emit(winner_id)

	var wins_needed = (max_rounds / 2) + 1
	if p1_wins >= wins_needed:
		match_ended.emit(GameEnums.PlayerID.PLAYER_ONE)
	elif p2_wins >= wins_needed:
		match_ended.emit(GameEnums.PlayerID.PLAYER_TWO)
	else:
		current_round += 1
		# KOSequenceManager が演出後に start_round() を呼ぶ

func _reset_character(character: Node) -> void:
	if character == null:
		return
	var ctrl:   CombatController = character.get_node_or_null("CombatController")
	var health: HealthComponent  = character.get_node_or_null("CombatController/HealthComponent")
	var combo:  ComboManager     = character.get_node_or_null("CombatController/ComboManager")
	if health: health.reset()
	if ctrl:   ctrl.transition_to(GameEnums.CharacterState.IDLE)
	if combo:  combo.reset_combo()

func _get_permanent_hp(character: Node) -> float:
	if character == null:
		return 0.0
	var h: HealthComponent = character.get_node_or_null("CombatController/HealthComponent")
	return h.current_permanent_hp if h else 0.0
