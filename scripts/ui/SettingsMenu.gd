extends Control

var master_bus_idx : int
var bgm_bus_idx    : int
var sfx_bus_idx    : int

func _ready() -> void:
	master_bus_idx = AudioServer.get_bus_index("Master")
	bgm_bus_idx    = AudioServer.get_bus_index("BGM")
	sfx_bus_idx    = AudioServer.get_bus_index("SFX")

	var vol_slider := get_node_or_null("Margin/VBox/VolumeHBox/VolumeSlider")
	if vol_slider:
		vol_slider.value = db_to_linear(AudioServer.get_bus_volume_db(master_bus_idx)) * 100.0

	var bgm_slider := get_node_or_null("Margin/VBox/BGMHBox/BGMSlider")
	if bgm_slider:
		bgm_slider.value = db_to_linear(AudioServer.get_bus_volume_db(bgm_bus_idx)) * 100.0

	var sfx_slider := get_node_or_null("Margin/VBox/SFXHBox/SFXSlider")
	if sfx_slider:
		sfx_slider.value = db_to_linear(AudioServer.get_bus_volume_db(sfx_bus_idx)) * 100.0

	var fs_check := get_node_or_null("Margin/VBox/FullscreenHBox/FullscreenCheck")
	if fs_check:
		fs_check.button_pressed = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN

	var dbg_check := get_node_or_null("Margin/VBox/DebugHBox/DebugCheck")
	if dbg_check:
		dbg_check.button_pressed = GameManager.debug_mode

	# コントローラー/キーボード操作のためにデフォルトフォーカスを設定
	var back_btn := get_node_or_null("Margin/VBox/BackButton")
	if back_btn:
		back_btn.grab_focus()

func _on_volume_slider_value_changed(value: float) -> void:
	AudioServer.set_bus_volume_db(master_bus_idx, linear_to_db(value / 100.0))

func _on_bgm_slider_value_changed(value: float) -> void:
	AudioServer.set_bus_volume_db(bgm_bus_idx, linear_to_db(value / 100.0))

func _on_sfx_slider_value_changed(value: float) -> void:
	AudioServer.set_bus_volume_db(sfx_bus_idx, linear_to_db(value / 100.0))

func _on_fullscreen_check_toggled(toggled_on: bool) -> void:
	if toggled_on:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)

func _on_debug_check_toggled(toggled_on: bool) -> void:
	GameManager.debug_mode = toggled_on

func _on_back_button_pressed() -> void:
	GameManager.save_config()
	SceneManager.change_scene_to_file("res://scenes/ui/title.tscn")
