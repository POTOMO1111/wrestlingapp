extends Node

# ============================================================
#  GameManager.gd
#  AutoLoad として登録して使う。
#  試合状態・UI（ポーズ/試合結果）を一元管理する。
#  HP/ダメージ管理は FightManager + HealthComponent が担当する。
# ============================================================

enum MatchState { MENU, READY, FIGHTING, PAUSE, ROUND_END, MATCH_END }

var match_state     : MatchState = MatchState.MENU
var round_number    : int        = 1
var round_wins      : Dictionary = { 1: 0, 2: 0 }

# 選択されたキャラクターID（キャラセレ画面でセットされる）
var p1_character_id : String = "Player"
var p2_character_id : String = "Dummy"

const CONFIG_PATH = "user://settings.cfg"

## デバッグオーバーレイ表示フラグ
var debug_mode: bool = false

# --- UI ノード（動的生成） ---
var _ui_canvas         : CanvasLayer = null
var _pause_menu        : Control     = null
var _match_end_menu    : Control     = null
var _match_result_label: Label       = null
var _btn_resume_pause  : Button      = null
var _btn_return_select : Button      = null

## シグナル（後方互換用）
signal match_started
signal match_ended(winner_id)

# ----------------------------------------------------------
# 初期化
# ----------------------------------------------------------
func _ready() -> void:
	_setup_ui_inputs()
	_load_config()
	_setup_ui()

	if get_tree().current_scene.name == "Main":
		start_match()

func _setup_ui_inputs() -> void:
	var key_mappings := {
		"ui_up":    KEY_W,
		"ui_down":  KEY_S,
		"ui_left":  KEY_A,
		"ui_right": KEY_D,
		"ui_accept": KEY_J
	}
	for action in key_mappings:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		var ev := InputEventKey.new()
		ev.physical_keycode = key_mappings[action]
		InputMap.action_add_event(action, ev)

	# ジョイパッドの決定ボタン
	for btn_id in [0, 1]:
		var ev_joy := InputEventJoypadButton.new()
		ev_joy.button_index = btn_id
		InputMap.action_add_event("ui_accept", ev_joy)

func _load_config() -> void:
	var config := ConfigFile.new()
	if config.load(CONFIG_PATH) != OK:
		return

	var master_vol: float = config.get_value("audio", "master_volume", 0.0)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), master_vol)

	var bgm_idx := AudioServer.get_bus_index("BGM")
	if bgm_idx != -1:
		AudioServer.set_bus_volume_db(bgm_idx, config.get_value("audio", "bgm_volume", 0.0))

	var sfx_idx := AudioServer.get_bus_index("SFX")
	if sfx_idx != -1:
		AudioServer.set_bus_volume_db(sfx_idx, config.get_value("audio", "sfx_volume", 0.0))

	if config.get_value("video", "fullscreen", false):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)

	debug_mode = config.get_value("debug", "debug_mode", false)

func save_config() -> void:
	var config := ConfigFile.new()
	config.set_value("audio", "master_volume",
		AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Master")))

	var bgm_idx := AudioServer.get_bus_index("BGM")
	if bgm_idx != -1:
		config.set_value("audio", "bgm_volume", AudioServer.get_bus_volume_db(bgm_idx))

	var sfx_idx := AudioServer.get_bus_index("SFX")
	if sfx_idx != -1:
		config.set_value("audio", "sfx_volume", AudioServer.get_bus_volume_db(sfx_idx))

	config.set_value("video", "fullscreen",
		DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN)
	config.set_value("debug", "debug_mode", debug_mode)
	config.save(CONFIG_PATH)

# ----------------------------------------------------------
# UI 構築（ポーズメニュー + 試合結果メニュー）
# ----------------------------------------------------------
func _setup_ui() -> void:
	_ui_canvas = CanvasLayer.new()
	add_child(_ui_canvas)

	# ----- ポーズメニュー -----
	_pause_menu = PanelContainer.new()
	_pause_menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	var p_style := StyleBoxFlat.new()
	p_style.bg_color = Color(0, 0, 0, 0.75)
	_pause_menu.add_theme_stylebox_override("panel", p_style)
	_ui_canvas.add_child(_pause_menu)
	_pause_menu.visible = false
	_pause_menu.process_mode = Node.PROCESS_MODE_ALWAYS

	var p_center := CenterContainer.new()
	_pause_menu.add_child(p_center)
	var p_vbox := VBoxContainer.new()
	p_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	p_vbox.add_theme_constant_override("separation", 30)
	p_center.add_child(p_vbox)

	var lbl_paused := Label.new()
	lbl_paused.text = "PAUSED"
	lbl_paused.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_paused.add_theme_font_size_override("font_size", 64)
	p_vbox.add_child(lbl_paused)

	_btn_resume_pause = _make_button("RESUME", toggle_pause)
	p_vbox.add_child(_btn_resume_pause)
	p_vbox.add_child(_make_button("CHARACTER SELECT", _on_pause_chars_pressed))
	p_vbox.add_child(_make_button("RETURN TO TITLE",  _on_pause_title_pressed))

	# ----- 試合結果メニュー -----
	_match_end_menu = PanelContainer.new()
	_match_end_menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	var end_style := StyleBoxFlat.new()
	end_style.bg_color = Color(0, 0, 0, 0.5)
	_match_end_menu.add_theme_stylebox_override("panel", end_style)
	_ui_canvas.add_child(_match_end_menu)
	_match_end_menu.visible = false
	_match_end_menu.process_mode = Node.PROCESS_MODE_ALWAYS

	var end_center := CenterContainer.new()
	_match_end_menu.add_child(end_center)
	var end_vbox := VBoxContainer.new()
	end_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	end_vbox.add_theme_constant_override("separation", 30)
	end_center.add_child(end_vbox)

	_match_result_label = Label.new()
	_match_result_label.text = "YOU WIN!"
	_match_result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_match_result_label.add_theme_font_size_override("font_size", 90)
	_match_result_label.add_theme_constant_override("outline_size", 8)
	end_vbox.add_child(_match_result_label)

	_btn_return_select = _make_button("キャラ選択へ戻る", _on_pause_chars_pressed)
	end_vbox.add_child(_btn_return_select)

func _make_button(label_text: String, callback: Callable) -> Button:
	var btn := Button.new()
	btn.text = label_text
	btn.custom_minimum_size = Vector2(400, 60)
	btn.add_theme_font_size_override("font_size", 32)
	btn.pressed.connect(callback)
	return btn

# ----------------------------------------------------------
# 試合フロー制御
# ----------------------------------------------------------
func start_match() -> void:
	match_state = MatchState.FIGHTING
	match_started.emit()

# ----------------------------------------------------------
# 試合終了（KOSequenceManager から呼ばれる）
# ----------------------------------------------------------
func on_fighter_down(loser_id: int) -> void:
	if match_state != MatchState.FIGHTING:
		return
	match_state = MatchState.MATCH_END
	var winner_id := 3 - loser_id
	round_wins[winner_id] += 1
	match_ended.emit(winner_id)
	await get_tree().create_timer(1.5).timeout
	_show_match_result(winner_id)

func _show_match_result(winner_id: int) -> void:
	if not _match_end_menu:
		return
	_match_end_menu.visible = true
	var end_style := _match_end_menu.get_theme_stylebox("panel") as StyleBoxFlat
	if winner_id == 1:
		_match_result_label.text = "YOU WIN!"
		end_style.bg_color = Color(0.2, 0.4, 0.8, 0.5)
	else:
		_match_result_label.text = "YOU LOSE..."
		end_style.bg_color = Color(0.8, 0.2, 0.2, 0.5)
	# フォーカスをボタンに当ててコントローラーでも操作できるようにする
	if _btn_return_select:
		_btn_return_select.call_deferred("grab_focus")

# ----------------------------------------------------------
# UI 表示切り替え（後方互換スタブ）
# ----------------------------------------------------------
func show_battle_ui() -> void:
	pass

func hide_battle_ui() -> void:
	pass

# ----------------------------------------------------------
# ポーズ切り替え
# ----------------------------------------------------------
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_pause"):
		if match_state == MatchState.FIGHTING or match_state == MatchState.PAUSE:
			toggle_pause()

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
		if _pause_menu:
			_pause_menu.visible = false
		AudioManager.set_ducking(false)

func _on_pause_chars_pressed() -> void:
	get_tree().paused = false
	match_state = MatchState.MENU
	AudioManager.set_ducking(false)
	if _pause_menu:     _pause_menu.visible = false
	if _match_end_menu: _match_end_menu.visible = false
	SceneManager.change_scene_to_file("res://scenes/ui/char_select.tscn")

func _on_pause_title_pressed() -> void:
	get_tree().paused = false
	match_state = MatchState.MENU
	AudioManager.set_ducking(false)
	if _pause_menu: _pause_menu.visible = false
	SceneManager.change_scene_to_file("res://scenes/ui/title.tscn")
