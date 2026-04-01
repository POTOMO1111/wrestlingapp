extends Control

var characters = ["Player"] # プレースホルダー（将来的にキャラが増える想定）
var p1_selected = "Player"
var p2_selected = "Player"

func _ready() -> void:
	AudioManager.play_bgm("select")
	GameManager.hide_battle_ui()
	if has_node("VBox/FightButton"):
		$VBox/FightButton.grab_focus()

func _on_fight_button_pressed() -> void:
	GameManager.p1_character_id = p1_selected
	GameManager.p2_character_id = p2_selected
	SceneManager.change_scene_to_file("res://scenes/game/main.tscn")

func _on_back_button_pressed() -> void:
	SceneManager.change_scene_to_file("res://scenes/ui/title.tscn")
