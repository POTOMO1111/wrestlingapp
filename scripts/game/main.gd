extends Node3D

# ============================================================
#  main.gd
#  試合シーンのルートスクリプト。
#  キャラクターを動的生成し、新戦闘システムを構築・接続する。
# ============================================================

@onready var fight_manager:      FightManager      = $FightManager
@onready var ko_sequence_manager: KOSequenceManager = $KOSequenceManager

func _ready() -> void:
	AudioManager.play_bgm("battle")
	ko_sequence_manager.setup(fight_manager)
	_spawn_characters()
	# GameManager の match_state を FIGHTING にしてポーズ等が機能するようにする
	if GameManager.has_method("start_match"):
		GameManager.start_match()

func _spawn_characters() -> void:
	var char_scene = load("res://scenes/characters/player.tscn")
	if char_scene == null:
		push_error("main.gd: player.tscn の読み込みに失敗しました")
		return

	# --- Player 1 (人間操作) ---
	var p1 = char_scene.instantiate()
	p1.player_id = 1
	p1.is_dummy  = false
	p1.name      = "Player1"
	p1.transform.origin = Vector3(0, 1.2, 2.0)
	p1.rotation.y = PI  # P2（-Z方向）を向く
	add_child(p1)

	# カメラを有効化
	var cam = p1.get_node_or_null("SpringArm3D/Camera3D")
	if cam:
		cam.current = true

	# --- Player 2 (CPU) ---
	var p2 = char_scene.instantiate()
	var cpu_script = load("res://scripts/characters/CPUController.gd")
	if cpu_script:
		p2.set_script(cpu_script)
	p2.player_id = 2
	p2.name      = "Player2"
	p2.transform.origin = Vector3(0, 1.2, -2.0)
	p2.rotation.y = 0  # P1（+Z方向）を向く
	add_child(p2)

	# 両キャラに CombatController サブツリーを追加
	_attach_combat_system(p1, GameEnums.PlayerID.PLAYER_ONE, "balanced")
	_attach_combat_system(p2, GameEnums.PlayerID.PLAYER_TWO, "balanced")

	# CPU AI の初期化（p2 が CPUController の場合）
	if p2 is CPUController:
		# キャラセレで選択したプロファイル・難易度を反映
		var profile_path := "res://resources/ai_profiles/ai_%s.tres" % GameManager.cpu_ai_profile
		var diff_path    := "res://resources/difficulty/difficulty_%s.tres" % GameManager.cpu_difficulty
		var profile_res  := load(profile_path)
		var diff_res     := load(diff_path)
		if profile_res:
			p2.ai_profile_resource = profile_res
		else:
			push_warning("main.gd: AI プロファイルが見つかりません: " + profile_path)
		if diff_res:
			p2.difficulty_resource = diff_res
		else:
			push_warning("main.gd: 難易度プロファイルが見つかりません: " + diff_path)

		var p1_combat: Node = p1.get_node_or_null("CombatController")
		var p2_combat: Node = p2.get_node_or_null("CombatController")
		if p1_combat and p2_combat:
			p2.initialize_ai(p1, p2_combat, p1_combat)
		else:
			push_error("main.gd: CombatController が見つからず CPU AI を初期化できませんでした")

	# 互いに相手を参照設定（常時相手方向を向く制御のため）
	p1.opponent = p2
	p2.opponent = p1

	# FightManager にキャラクターを登録
	fight_manager.set_fighters(p1, p2)

	# InputHandler を P1 に追加（P2はCPUなので不要）
	_attach_input_handler(p1, GameEnums.PlayerID.PLAYER_ONE)

	# HUD をロードして接続
	_setup_hud()

	# デバッグオーバーレイ（debug_mode が有効な場合のみ）
	_setup_debug_overlay()

# ----------------------------------------------------------
# CombatController サブツリーの動的構築
# ----------------------------------------------------------

func _attach_combat_system(character: Node, pid: GameEnums.PlayerID, stats_name: String) -> void:
	# HealthComponent
	var health_comp = HealthComponent.new()
	health_comp.name = "HealthComponent"
	var stats_path = "res://resources/characters/stats_%s.tres" % stats_name
	var stats = load(stats_path)
	if stats == null:
		push_warning("main.gd: stats ファイルが見つかりません: " + stats_path)
		stats = CharacterStats.new()
	health_comp.stats = stats

	# HitboxManager（子にArea3DとCollisionShape3Dが必要）
	var hbm = HitboxManager.new()
	hbm.name = "HitboxManager"
	_build_hitbox_manager_nodes(hbm)

	# ComboManager
	var combo_mgr = ComboManager.new()
	combo_mgr.name = "ComboManager"
	var combo_tree = load("res://resources/combos/combo_tree_root.tres")
	if combo_tree != null:
		combo_mgr.combo_tree_root = combo_tree
	else:
		push_warning("main.gd: combo_tree_root.tres の読み込みに失敗しました。単発攻撃のみ使用します。")

	# ステートノード群
	var states: Array = [
		["StateIdle",          StateIdle.new()],
		["StateWalking",       StateWalking.new()],
		["StateAttacking",     StateAttacking.new()],
		["StateGuarding",      StateGuarding.new()],
		["StateGrappling",     StateGrappling.new()],
		["StateGrappled",      StateGrappled.new()],
		["StateHitStun",       StateHitStun.new()],
		["StateKnockdown",     StateKnockdown.new()],
		["StateGettingUp",     StateGettingUp.new()],
		["StateIncapacitated", StateIncapacitated.new()],
		["StateKO",            StateKO.new()],
	]

	# CombatController 本体
	var ctrl = CombatController.new()
	ctrl.name      = "CombatController"
	ctrl.player_id = pid

	# 子ノードを追加（CombatController が @onready で参照するため先に add_child）
	ctrl.add_child(health_comp)
	ctrl.add_child(hbm)
	ctrl.add_child(combo_mgr)
	for pair in states:
		pair[1].name = pair[0]
		ctrl.add_child(pair[1])

	character.add_child(ctrl)

func _build_hitbox_manager_nodes(hbm: HitboxManager) -> void:
	# Hitbox
	var hitbox = Area3D.new()
	hitbox.name = "Hitbox"
	hitbox.add_to_group("hitbox")
	var hitbox_shape = CollisionShape3D.new()
	hitbox_shape.name = "CollisionShape3D"
	hitbox_shape.shape = BoxShape3D.new()
	hitbox.add_child(hitbox_shape)
	hbm.add_child(hitbox)

	# Hurtbox
	var hurtbox = Area3D.new()
	hurtbox.name = "Hurtbox"
	hurtbox.add_to_group("hurtbox")
	var hurtbox_shape = CollisionShape3D.new()
	hurtbox_shape.name = "CollisionShape3D"
	hurtbox_shape.shape = CapsuleShape3D.new()
	hurtbox.add_child(hurtbox_shape)
	hbm.add_child(hurtbox)

func _attach_input_handler(character: Node, pid: GameEnums.PlayerID) -> void:
	var ih = InputHandler.new()
	ih.name      = "InputHandler"
	ih.player_id = pid
	character.add_child(ih)

# ----------------------------------------------------------
# HUD セットアップ
# ----------------------------------------------------------

func _setup_hud() -> void:
	var hud_scene = load("res://scenes/ui/hud.tscn")
	if hud_scene == null:
		push_warning("main.gd: hud.tscn が見つかりません")
		return
	var hud = hud_scene.instantiate()
	add_child(hud)
	# FightManager が set_fighters() を終えた後に接続
	call_deferred("_connect_hud", hud)

func _connect_hud(hud: Node) -> void:
	if hud.has_method("connect_to_fight_manager"):
		hud.connect_to_fight_manager(fight_manager)

# ----------------------------------------------------------
# デバッグオーバーレイ
# ----------------------------------------------------------

func _setup_debug_overlay() -> void:
	if not GameManager.debug_mode:
		return
	var overlay = DebugOverlay.new()
	overlay.name = "DebugOverlay"
	add_child(overlay)
	# InputHandler など全ノードが add_child された後に接続（2フレーム後）
	call_deferred("_connect_debug_overlay_deferred", overlay)

func _connect_debug_overlay_deferred(overlay: DebugOverlay) -> void:
	# さらに1フレーム待つことで全 _ready() が確実に完了する
	await get_tree().process_frame
	overlay.setup(fight_manager)
