extends Node

# ============================================================
#  GameManager.gd
#  AutoLoad として登録して使う。
#  試合状態・体力・ラウンドを一元管理する。
# ============================================================

enum MatchState { MENU, READY, FIGHTING, PAUSE, ROUND_END, MATCH_END }

var match_state  : MatchState = MatchState.MENU
var round_number : int = 1
var max_rounds   : int = 3
var round_time   : float = 180.0   # 秒
var _timer       : float = 0.0

# 選択されたキャラクターID（キャラセレ画面でセットされる）
var p1_character_id : String = "Player"
var p2_character_id : String = "Dummy"

# 各プレイヤーの体力（CharacterBase.gd から hp_changed シグナルで更新）
var hp : Dictionary = { 1: 100, 2: 100 }
var max_hp : Dictionary = { 1: 100, 2: 100 }

const CONFIG_PATH = "user://settings.cfg"

# ラウンド勝利数
var round_wins : Dictionary = { 1: 0, 2: 0 }

var _ui_canvas : CanvasLayer = null
var _time_label : Label = null
var _hp_bars : Dictionary = {}
var _stamina_bars : Dictionary = {}
var _pause_menu : Control = null
var _match_end_menu : Control = null
var _match_result_label : Label = null
var _btn_resume_pause : Button = null

## シグナル
signal match_started
signal round_ended(winner_id)
signal match_ended(winner_id)
signal timer_updated(remaining)
signal hp_updated(player_id, current, maximum)

# ----------------------------------------------------------
# 初期化
# ----------------------------------------------------------
func _ready() -> void:
	_setup_ui_inputs()
	_load_config()
	_setup_debug_ui()
	hide_battle_ui() # メニュー画面などでは非表示にしておく
	
	# テスト起動用に、メイン画面(main.tscn)から直接起動された場合は自動的に試合開始
	if get_tree().current_scene.name == "Main":
		start_match()

func _setup_ui_inputs() -> void:
	var key_mappings = {
		"ui_up": KEY_W,
		"ui_down": KEY_S,
		"ui_left": KEY_A,
		"ui_right": KEY_D,
		"ui_accept": KEY_J
	}
	for action in key_mappings:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		var ev = InputEventKey.new()
		ev.physical_keycode = key_mappings[action]
		InputMap.action_add_event(action, ev)
		
	# ジョイパッドの決定ボタン (0: Attack Heavy / 1: Jump) を確実に追加
	for btn_id in [0, 1]:
		var ev_joy = InputEventJoypadButton.new()
		ev_joy.button_index = btn_id
		InputMap.action_add_event("ui_accept", ev_joy)

func _load_config() -> void:
	var config = ConfigFile.new()
	var err = config.load(CONFIG_PATH)
	if err == OK:
		var master_vol = config.get_value("audio", "master_volume", 0.0)
		AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), master_vol)
		
		var bgm_idx = AudioServer.get_bus_index("BGM")
		if bgm_idx != -1: AudioServer.set_bus_volume_db(bgm_idx, config.get_value("audio", "bgm_volume", 0.0))
		
		var sfx_idx = AudioServer.get_bus_index("SFX")
		if sfx_idx != -1: AudioServer.set_bus_volume_db(sfx_idx, config.get_value("audio", "sfx_volume", 0.0))
		
		var is_full = config.get_value("video", "fullscreen", false)
		if is_full:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		else:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)

func save_config() -> void:
	var config = ConfigFile.new()
	config.set_value("audio", "master_volume", AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Master")))
	
	var bgm_idx = AudioServer.get_bus_index("BGM")
	if bgm_idx != -1: config.set_value("audio", "bgm_volume", AudioServer.get_bus_volume_db(bgm_idx))
	
	var sfx_idx = AudioServer.get_bus_index("SFX")
	if sfx_idx != -1: config.set_value("audio", "sfx_volume", AudioServer.get_bus_volume_db(sfx_idx))
	
	config.set_value("video", "fullscreen", DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN)
	config.save(CONFIG_PATH)

func _setup_debug_ui() -> void:
	_ui_canvas = CanvasLayer.new()
	add_child(_ui_canvas)
	
	var ui_root = Control.new()
	ui_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui_canvas.add_child(ui_root)
	
	var margin = MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_TOP_WIDE)
	margin.add_theme_constant_override("margin_top", 40)
	margin.add_theme_constant_override("margin_left", 60)
	margin.add_theme_constant_override("margin_right", 60)
	ui_root.add_child(margin)
	
	var hbox = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	margin.add_child(hbox)
	
	# ----- Player 1 (Left) -----
	var p1_vbox = VBoxContainer.new()
	p1_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(p1_vbox)
	
	var p1_name = Label.new()
	p1_name.text = "PLAYER 1"
	p1_name.add_theme_font_size_override("font_size", 28)
	p1_name.add_theme_constant_override("outline_size", 6)
	p1_vbox.add_child(p1_name)
	
	var p1_hp = _create_bar(Color.GREEN)
	p1_vbox.add_child(p1_hp)
	var p1_stamina = _create_bar(Color.YELLOW, 15.0)
	p1_vbox.add_child(p1_stamina)
	
	_hp_bars[1] = p1_hp
	_stamina_bars[1] = p1_stamina
	
	# ----- Center (Timer) -----
	var timer_panel = PanelContainer.new()
	var timer_style = StyleBoxFlat.new()
	timer_style.bg_color = Color(0, 0, 0, 0.7)
	timer_style.border_width_bottom = 4
	timer_style.border_width_top = 4
	timer_style.border_width_left = 4
	timer_style.border_width_right = 4
	timer_style.border_color = Color(0.8, 0.6, 0.0) # ゴールド
	timer_style.corner_radius_top_left = 15
	timer_style.corner_radius_top_right = 15
	timer_style.corner_radius_bottom_left = 15
	timer_style.corner_radius_bottom_right = 15
	timer_style.expand_margin_left = 30
	timer_style.expand_margin_right = 30
	timer_panel.add_theme_stylebox_override("panel", timer_style)
	timer_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	hbox.add_child(timer_panel)
	
	_time_label = Label.new()
	_time_label.add_theme_font_size_override("font_size", 54)
	_time_label.text = "300"
	_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	timer_panel.add_child(_time_label)
	
	# ----- Player 2 (Right) -----
	var p2_vbox = VBoxContainer.new()
	p2_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(p2_vbox)
	
	var p2_name = Label.new()
	p2_name.text = "CPU OPPONENT"
	p2_name.add_theme_font_size_override("font_size", 28)
	p2_name.add_theme_constant_override("outline_size", 6)
	p2_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	p2_vbox.add_child(p2_name)
	
	var p2_hp = _create_bar(Color.RED)
	p2_hp.fill_mode = ProgressBar.FILL_END_TO_BEGIN # 右から減る
	p2_vbox.add_child(p2_hp)
	var p2_stamina = _create_bar(Color.YELLOW, 15.0)
	p2_stamina.fill_mode = ProgressBar.FILL_END_TO_BEGIN
	p2_vbox.add_child(p2_stamina)
	
	_hp_bars[2] = p2_hp
	_stamina_bars[2] = p2_stamina

	# ----- Pause Menu -----
	_pause_menu = PanelContainer.new()
	_pause_menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	var p_style = StyleBoxFlat.new()
	p_style.bg_color = Color(0, 0, 0, 0.75)
	_pause_menu.add_theme_stylebox_override("panel", p_style)
	_ui_canvas.add_child(_pause_menu)
	_pause_menu.visible = false
	_pause_menu.process_mode = Node.PROCESS_MODE_ALWAYS # ポーズ中もボタンを機能させるため
	
	var center = CenterContainer.new()
	_pause_menu.add_child(center)
	
	var p_vbox = VBoxContainer.new()
	p_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	p_vbox.add_theme_constant_override("separation", 30)
	center.add_child(p_vbox)
	
	var label = Label.new()
	label.text = "PAUSED"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 64)
	p_vbox.add_child(label)
	
	_btn_resume_pause = Button.new()
	_btn_resume_pause.text = "RESUME"
	_btn_resume_pause.custom_minimum_size = Vector2(400, 60)
	_btn_resume_pause.add_theme_font_size_override("font_size", 32)
	_btn_resume_pause.pressed.connect(toggle_pause)
	p_vbox.add_child(_btn_resume_pause)
	
	var btn_chars = Button.new()
	btn_chars.text = "CHARACTER SELECT"
	btn_chars.custom_minimum_size = Vector2(400, 60)
	btn_chars.add_theme_font_size_override("font_size", 32)
	btn_chars.pressed.connect(_on_pause_chars_pressed)
	p_vbox.add_child(btn_chars)

	var btn_title = Button.new()
	btn_title.text = "RETURN TO TITLE"
	btn_title.custom_minimum_size = Vector2(400, 60)
	btn_title.add_theme_font_size_override("font_size", 32)
	btn_title.pressed.connect(_on_pause_title_pressed)
	p_vbox.add_child(btn_title)

	# ----- Match End Menu -----
	_match_end_menu = PanelContainer.new()
	_match_end_menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	var end_style = StyleBoxFlat.new()
	end_style.bg_color = Color(0, 0, 0, 0.5)
	_match_end_menu.add_theme_stylebox_override("panel", end_style)
	_ui_canvas.add_child(_match_end_menu)
	_match_end_menu.visible = false
	
	var end_center = CenterContainer.new()
	_match_end_menu.add_child(end_center)
	
	var end_vbox = VBoxContainer.new()
	end_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	end_vbox.add_theme_constant_override("separation", 30)
	end_center.add_child(end_vbox)
	
	_match_result_label = Label.new()
	_match_result_label.text = "YOU WIN!"
	_match_result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_match_result_label.add_theme_font_size_override("font_size", 90)
	_match_result_label.add_theme_constant_override("outline_size", 8)
	end_vbox.add_child(_match_result_label)
	
	var btn_return_select = Button.new()
	btn_return_select.text = "キャラ選択へ戻る"
	btn_return_select.custom_minimum_size = Vector2(400, 60)
	btn_return_select.add_theme_font_size_override("font_size", 32)
	btn_return_select.pressed.connect(_on_pause_chars_pressed)
	end_vbox.add_child(btn_return_select)

func _create_bar(color: Color, height: float = 30.0) -> ProgressBar:
	var bar = ProgressBar.new()
	bar.custom_minimum_size = Vector2(300, height)
	bar.size_flags_horizontal = Control.SIZE_FILL
	bar.show_percentage = false
	bar.max_value = 100
	bar.value = 100
	
	var bg = StyleBoxFlat.new()
	bg.bg_color = Color(0.2, 0.2, 0.2, 0.8)
	bg.border_width_bottom = 2
	bg.border_width_top = 2
	bg.border_width_left = 2
	bg.border_width_right = 2
	bg.border_color = Color.BLACK
	
	var fg = StyleBoxFlat.new()
	fg.bg_color = color
	fg.border_width_bottom = 2
	fg.border_width_top = 2
	fg.border_width_left = 2
	fg.border_width_right = 2
	fg.border_color = Color.BLACK
	
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fg)
	return bar

# ----------------------------------------------------------
# キャラクターのUI登録・イベント連携
# ----------------------------------------------------------
func register_fighter(fighter: Node3D) -> void:
	if fighter.has_signal("hp_changed"):
		fighter.hp_changed.connect(_on_fighter_hp_changed)
	if fighter.has_signal("stamina_changed"):
		fighter.stamina_changed.connect(_on_fighter_stamina_changed)

func _on_fighter_hp_changed(pid: int, current: int, maximum: int) -> void:
	if _hp_bars.has(pid):
		var bar = _hp_bars[pid]
		bar.max_value = maximum
		var tween = create_tween()
		tween.tween_property(bar, "value", float(current), 0.2).set_trans(Tween.TRANS_SINE)

func _on_fighter_stamina_changed(pid: int, current: float, maximum: float) -> void:
	if _stamina_bars.has(pid):
		var bar = _stamina_bars[pid]
		bar.max_value = maximum
		bar.value = current # スタミナは頻繁に動くのでTweenではなく直接反映

# ----------------------------------------------------------
# UI表示切り替え
# ----------------------------------------------------------
func show_battle_ui() -> void:
	if _ui_canvas: _ui_canvas.visible = true

func hide_battle_ui() -> void:
	if _ui_canvas: _ui_canvas.visible = false

# ----------------------------------------------------------
# 試合フロー制御
# ----------------------------------------------------------
func start_match() -> void:
	show_battle_ui()
	match_state = MatchState.FIGHTING
	round_time = 300.0 # 指定された300秒
	_timer = round_time
	match_started.emit()

# ----------------------------------------------------------
# 毎フレーム（タイマー更新）
# ----------------------------------------------------------
func _process(delta: float) -> void:
	if match_state != MatchState.FIGHTING:
		return

	_timer -= delta
	timer_updated.emit(max(0.0, _timer))
	
	if _time_label:
		_time_label.text = "%03d" % int(ceil(max(0.0, _timer)))

	if _timer <= 0.0:
		# 時間切れ → 体力が多い方の勝ち
		var winner := 1 if hp[1] >= hp[2] else 2
		on_fighter_down(3 - winner)  # 負けた方を通知

# ----------------------------------------------------------
# ダメージ適用（HitboxController から直接呼ばれる場合）
# ----------------------------------------------------------
func apply_damage(player_id: int, amount: int) -> void:
	if match_state != MatchState.FIGHTING:
		return
	hp[player_id] = max(0, hp[player_id] - amount)
	hp_updated.emit(player_id, hp[player_id], max_hp[player_id])
	if hp[player_id] <= 0:
		on_fighter_down(player_id)

# ----------------------------------------------------------
# ファイターがダウンしたとき（CharacterBase から呼ばれる）
# ----------------------------------------------------------
func on_fighter_down(loser_id: int) -> void:
	if match_state != MatchState.FIGHTING:
		return
	match_state = MatchState.MATCH_END

	var winner_id := 3 - loser_id  # 1なら2、2なら1
	round_wins[winner_id] += 1
	match_ended.emit(winner_id)
	
	# ダウンモーションを見るために少し待つ
	await get_tree().create_timer(1.5).timeout
	_show_match_result(winner_id)

func _show_match_result(winner_id: int) -> void:
	if not _match_end_menu: return
	_match_end_menu.visible = true
	var end_style = _match_end_menu.get_theme_stylebox("panel") as StyleBoxFlat
	
	if winner_id == 1: # 自分が勝った場合
		_match_result_label.text = "YOU WIN!"
		end_style.bg_color = Color(0.2, 0.4, 0.8, 0.5) # 青み
	else:
		_match_result_label.text = "YOU LOSE..."
		end_style.bg_color = Color(0.8, 0.2, 0.2, 0.5) # 赤み

# ----------------------------------------------------------
# 次のラウンド開始
# ----------------------------------------------------------
func _start_next_round() -> void:
	round_number += 1
	hp[1] = max_hp[1]
	hp[2] = max_hp[2]
	_timer = round_time
	match_state = MatchState.FIGHTING

# ----------------------------------------------------------
# 入力監視（ポーズボタン）
# ----------------------------------------------------------
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_pause"):
		if match_state == MatchState.FIGHTING or match_state == MatchState.PAUSE:
			toggle_pause()

# ----------------------------------------------------------
# ポーズ切り替え
# ----------------------------------------------------------
func toggle_pause() -> void:
	if match_state == MatchState.FIGHTING:
		match_state = MatchState.PAUSE
		get_tree().paused = true
		if _pause_menu: 
			_pause_menu.visible = true
			if _btn_resume_pause:
				_btn_resume_pause.grab_focus()
		AudioManager.set_ducking(true)
	elif match_state == MatchState.PAUSE:
		match_state = MatchState.FIGHTING
		get_tree().paused = false
		if _pause_menu: _pause_menu.visible = false
		AudioManager.set_ducking(false)

func _on_pause_chars_pressed() -> void:
	get_tree().paused = false
	match_state = MatchState.MENU
	AudioManager.set_ducking(false)
	hide_battle_ui()
	if _pause_menu: _pause_menu.visible = false
	if _match_end_menu: _match_end_menu.visible = false
	SceneManager.change_scene_to_file("res://scenes/ui/char_select.tscn")

func _on_pause_title_pressed() -> void:
	get_tree().paused = false
	match_state = MatchState.MENU
	AudioManager.set_ducking(false)
	hide_battle_ui()
	if _pause_menu: _pause_menu.visible = false
	SceneManager.change_scene_to_file("res://scenes/ui/title.tscn")