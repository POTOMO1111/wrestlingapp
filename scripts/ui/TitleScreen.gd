extends Control

func _ready() -> void:
	AudioManager.play_bgm("title")
	GameManager.hide_battle_ui()
	# コントローラー/キーボード操作のためにデフォルトフォーカスを設定
	var start_btn := get_node_or_null("Menu/VBoxContainer/StartButton")
	if start_btn:
		start_btn.grab_focus()

func _on_start_button_pressed() -> void:
	SceneManager.change_scene_to_file("res://scenes/ui/char_select.tscn")

func _on_settings_button_pressed() -> void:
	SceneManager.change_scene_to_file("res://scenes/ui/settings.tscn")

func _on_quit_button_pressed() -> void:
	get_tree().quit()
