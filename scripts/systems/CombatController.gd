class_name CombatController
extends Node3D

# ============================================================
#  CombatController.gd
#  各キャラクターノードの子ノードとしてアタッチ。
#  Node3D を継承することで HitboxManager へキャラクターの
#  ワールド変換（位置・回転）を継承させる。
#  ステートマシン本体。
#
#  子ノード構成（必須）:
#    HealthComponent
#    HitboxManager
#    ComboManager
#    StateIdle / StateWalking / StateAttacking / StateGuarding
#    StateGrappling / StateGrappled / StateHitStun
#    StateKnockdown / StateGettingUp / StateIncapacitated / StateKO
# ============================================================

@export var player_id: GameEnums.PlayerID = GameEnums.PlayerID.PLAYER_ONE

# --- コンポーネント参照 ---
@onready var health:        HealthComponent = $HealthComponent
@onready var hitbox_manager: HitboxManager  = $HitboxManager
@onready var combo_manager: ComboManager    = $ComboManager
var anim_player: AnimationPlayer = null  # キャラのルートから動的に取得
var anim_state: AnimationNodeStateMachinePlayback = null

# --- ステートノード ---
@onready var state_idle:         BaseState = $StateIdle
@onready var state_walking:      BaseState = $StateWalking
@onready var state_attacking:    BaseState = $StateAttacking
@onready var state_guarding:     BaseState = $StateGuarding
@onready var state_grappling:    BaseState = $StateGrappling
@onready var state_grappled:     BaseState = $StateGrappled
@onready var state_hit_stun:     BaseState = $StateHitStun
@onready var state_knockdown:    BaseState = $StateKnockdown
@onready var state_getting_up:   BaseState = $StateGettingUp
@onready var state_incapacitated: BaseState = $StateIncapacitated
@onready var state_ko:           BaseState = $StateKO

# --- 一時データ（ステート間の受け渡し） ---
var _pending_attack:          AttackData  = null
var _pending_grapple_data:    GrappleData = null
var _pending_hit_stun_frames: int         = 0
var _ender_damage_multiplier: float       = 1.0

# --- ステート管理 ---
var _current_state:      GameEnums.CharacterState = GameEnums.CharacterState.IDLE
var _current_state_node: BaseState                = null

signal state_changed(new_state: GameEnums.CharacterState)

func _ready() -> void:
	# AnimationPlayer / AnimationTree を親キャラクター内で検索
	anim_player = _find_anim_player(get_parent())
	var _anim_tree := _find_anim_tree(get_parent())
	if _anim_tree:
		anim_state = _anim_tree.get("parameters/playback")

	# 各ステートに参照を設定
	for child in get_children():
		if child is BaseState:
			child.combat_controller = self

	# HealthComponent シグナル接続
	health.recoverable_hp_depleted.connect(func(): transition_to(GameEnums.CharacterState.INCAPACITATED))
	health.permanent_hp_depleted.connect(func(): transition_to(GameEnums.CharacterState.KO))
	health.incapacitation_ended.connect(func(): transition_to(GameEnums.CharacterState.GETTING_UP))

	# HitboxManager シグナル接続
	hitbox_manager.hit_landed.connect(_on_hit_landed)
	hitbox_manager.grapple_initiated.connect(_on_grapple_initiated)

	transition_to(GameEnums.CharacterState.IDLE)

func _physics_process(delta: float) -> void:
	if _current_state_node:
		_current_state_node.update(delta)

## 外部からの入力受付（InputHandler / CPUCombatAI から呼ぶ）
func receive_input(action: GameEnums.ActionType) -> void:
	if GameManager.debug_mode:
		print("[CombatController:%s] receive_input(%s)  state=%s  state_node=%s" % [
			get_parent().name, GameEnums.ActionType.keys()[action],
			GameEnums.CharacterState.keys()[_current_state], str(_current_state_node)
		])
	if _current_state_node:
		_current_state_node.handle_input(action)

## ステート遷移
func transition_to(new_state: GameEnums.CharacterState) -> void:
	# _current_state_node が null（初期化前）の場合は同一ステートでも通過させる
	if _current_state == new_state and _current_state_node != null:
		return
	var prev = _current_state
	if _current_state_node:
		_current_state_node.exit(new_state)
	_current_state      = new_state
	_current_state_node = _get_state_node(new_state)
	if _current_state_node:
		_current_state_node.enter(prev)
	state_changed.emit(new_state)

func get_current_state() -> GameEnums.CharacterState:
	return _current_state

# ----------------------------------------------------------
# シグナルハンドラ
# ----------------------------------------------------------

func _on_hit_landed(target: Node, attack: AttackData, result: GameEnums.HitResult) -> void:
	var fight_mgr = get_tree().get_first_node_in_group("fight_manager")
	if fight_mgr:
		fight_mgr.process_hit(self, target, attack, result)

func _on_grapple_initiated(target: Node, grapple: GrappleData) -> void:
	var fight_mgr = get_tree().get_first_node_in_group("fight_manager")
	if fight_mgr:
		fight_mgr.process_grapple_start(self, target, grapple)

# ----------------------------------------------------------
# ユーティリティ
# ----------------------------------------------------------

func _get_state_node(state: GameEnums.CharacterState) -> BaseState:
	match state:
		GameEnums.CharacterState.IDLE:           return state_idle
		GameEnums.CharacterState.WALKING:        return state_walking
		GameEnums.CharacterState.RUNNING:        return state_walking  # 走りはWalkingで代用
		GameEnums.CharacterState.ATTACKING:      return state_attacking
		GameEnums.CharacterState.GUARDING:       return state_guarding
		GameEnums.CharacterState.GRAPPLING:      return state_grappling
		GameEnums.CharacterState.GRAPPLED:       return state_grappled
		GameEnums.CharacterState.HIT_STUN:       return state_hit_stun
		GameEnums.CharacterState.KNOCKDOWN:      return state_knockdown
		GameEnums.CharacterState.GETTING_UP:     return state_getting_up
		GameEnums.CharacterState.INCAPACITATED:  return state_incapacitated
		GameEnums.CharacterState.KO:             return state_ko
	return null

func _find_anim_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var result = _find_anim_player(child)
		if result:
			return result
	return null

func _find_anim_tree(node: Node) -> AnimationTree:
	if node is AnimationTree:
		return node
	for child in node.get_children():
		var result = _find_anim_tree(child)
		if result:
			return result
	return null

## アニメーション再生ヘルパー。AnimationTree ステート名へのマッピングを内包する。
func play_anim(anim_name: String) -> void:
	const MAP := {
		"idle": "Idle", "walk": "Walk", "guard": "Block",
		"hit_stun": "Hit", "knockdown": "Down", "ko": "Down",
		"grapple_initiator": "Grapple", "grapple_receiver": "Idle",
		"getting_up": "Idle",
	}
	var mapped: String = MAP.get(anim_name, anim_name)
	if anim_state:
		anim_state.travel(mapped)
	elif anim_player:
		anim_player.play(mapped)
