extends Control

func _ready() -> void:
	AudioManager.play_bgm("title")
	GameManager.hide_battle_ui()
	if has_node("Menu/VBoxContainer/StartButton"):
		$Menu/VBoxContainer/StartButton.grab_focus()

func _on_start_button_pressed() -> void:
	SceneManager.change_scene_to_file("res://scenes/ui/char_select.tscn")

func _on_settings_button_pressed() -> void:
	SceneManager.change_scene_to_file("res://scenes/ui/settings.tscn")

func _on_quit_button_pressed() -> void:
	get_tree().quit()
