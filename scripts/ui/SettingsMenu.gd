extends Control

var master_bus_idx : int
var bgm_bus_idx : int
var sfx_bus_idx : int

func _ready() -> void:
	master_bus_idx = AudioServer.get_bus_index("Master")
	bgm_bus_idx = AudioServer.get_bus_index("BGM")
	sfx_bus_idx = AudioServer.get_bus_index("SFX")
	
	if has_node("Margin/VBox/VolumeHBox/VolumeSlider"):
		var master_vol = AudioServer.get_bus_volume_db(master_bus_idx)
		var val = db_to_linear(master_vol) * 100.0
		$Margin/VBox/VolumeHBox/VolumeSlider.value = val

	if has_node("Margin/VBox/BGMHBox/BGMSlider"):
		var bgm_vol = AudioServer.get_bus_volume_db(bgm_bus_idx)
		$Margin/VBox/BGMHBox/BGMSlider.value = db_to_linear(bgm_vol) * 100.0

	if has_node("Margin/VBox/SFXHBox/SFXSlider"):
		var sfx_vol = AudioServer.get_bus_volume_db(sfx_bus_idx)
		$Margin/VBox/SFXHBox/SFXSlider.value = db_to_linear(sfx_vol) * 100.0

	if has_node("Margin/VBox/FullscreenHBox/FullscreenCheck"):
		var is_full = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		$Margin/VBox/FullscreenHBox/FullscreenCheck.button_pressed = is_full

	if has_node("Margin/VBox/BackButton"):
		$Margin/VBox/BackButton.grab_focus()

func _on_volume_slider_value_changed(value: float) -> void:
	var db = linear_to_db(value / 100.0)
	AudioServer.set_bus_volume_db(master_bus_idx, db)

func _on_bgm_slider_value_changed(value: float) -> void:
	var db = linear_to_db(value / 100.0)
	AudioServer.set_bus_volume_db(bgm_bus_idx, db)

func _on_sfx_slider_value_changed(value: float) -> void:
	var db = linear_to_db(value / 100.0)
	AudioServer.set_bus_volume_db(sfx_bus_idx, db)

func _on_fullscreen_check_toggled(toggled_on: bool) -> void:
	if toggled_on:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)

func _on_back_button_pressed() -> void:
	GameManager.save_config()
	SceneManager.change_scene_to_file("res://scenes/ui/title.tscn")
