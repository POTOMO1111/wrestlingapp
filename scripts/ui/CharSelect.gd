extends Control

# ============================================================
#  CharSelect.gd
#  キャラクター選択画面。
#  P2_Panel 内に CPU プロファイル・難易度の選択UIを動的構築する。
# ============================================================

const AI_PROFILES   : Array[String] = ["balanced", "striker", "grappler"]
const DIFFICULTIES  : Array[String] = ["easy", "normal", "hard", "expert", "legend"]
const PROFILE_LABEL : Dictionary    = {
	"balanced": "バランス型",
	"striker":  "打撃特化",
	"grappler": "組み技特化"
}
const DIFFICULTY_LABEL : Dictionary = {
	"easy":   "EASY",
	"normal": "NORMAL",
	"hard":   "HARD",
	"expert": "EXPERT",
	"legend": "LEGEND"
}

var _profile_idx    : int = 0
var _difficulty_idx : int = 1   # デフォルト: "normal"

var _profile_value_label    : Label
var _difficulty_value_label : Label

# ----------------------------------------------------------
# 初期化
# ----------------------------------------------------------
func _ready() -> void:
	AudioManager.play_bgm("select")
	GameManager.hide_battle_ui()

	# GameManager に保存済みの選択を復元
	var saved_profile := GameManager.cpu_ai_profile
	var saved_diff    := GameManager.cpu_difficulty
	if saved_profile in AI_PROFILES:
		_profile_idx = AI_PROFILES.find(saved_profile)
	if saved_diff in DIFFICULTIES:
		_difficulty_idx = DIFFICULTIES.find(saved_diff)

	# P2_Panel 内に選択UIを構築
	var p2_panel := get_node_or_null("HBox/P2_Panel")
	if p2_panel:
		_build_cpu_selector(p2_panel)

	var fight_btn := get_node_or_null("VBox/FightButton")
	if fight_btn:
		fight_btn.grab_focus()

# ----------------------------------------------------------
# CPU選択UI構築（P2_Panel内に動的追加）
# ----------------------------------------------------------
func _build_cpu_selector(panel: Control) -> void:
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 12)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(vbox)

	# --- プロファイル選択 ---
	var prof_title := Label.new()
	prof_title.text = "CPU スタイル"
	prof_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prof_title.add_theme_font_size_override("font_size", 18)
	vbox.add_child(prof_title)

	var prof_row := HBoxContainer.new()
	prof_row.alignment = BoxContainer.ALIGNMENT_CENTER
	prof_row.add_theme_constant_override("separation", 8)
	vbox.add_child(prof_row)

	var prof_prev := _make_arrow_button("<", func(): _cycle_profile(-1))
	_profile_value_label = _make_value_label(PROFILE_LABEL[AI_PROFILES[_profile_idx]])
	var prof_next := _make_arrow_button(">", func(): _cycle_profile(1))
	prof_row.add_child(prof_prev)
	prof_row.add_child(_profile_value_label)
	prof_row.add_child(prof_next)

	# --- 難易度選択 ---
	var diff_title := Label.new()
	diff_title.text = "難易度"
	diff_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	diff_title.add_theme_font_size_override("font_size", 18)
	vbox.add_child(diff_title)

	var diff_row := HBoxContainer.new()
	diff_row.alignment = BoxContainer.ALIGNMENT_CENTER
	diff_row.add_theme_constant_override("separation", 8)
	vbox.add_child(diff_row)

	var diff_prev := _make_arrow_button("<", func(): _cycle_difficulty(-1))
	_difficulty_value_label = _make_value_label(DIFFICULTY_LABEL[DIFFICULTIES[_difficulty_idx]])
	var diff_next := _make_arrow_button(">", func(): _cycle_difficulty(1))
	diff_row.add_child(diff_prev)
	diff_row.add_child(_difficulty_value_label)
	diff_row.add_child(diff_next)

func _make_arrow_button(label_text: String, callback: Callable) -> Button:
	var btn := Button.new()
	btn.text = label_text
	btn.custom_minimum_size = Vector2(36, 36)
	btn.add_theme_font_size_override("font_size", 20)
	btn.pressed.connect(callback)
	return btn

func _make_value_label(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.custom_minimum_size = Vector2(120, 36)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 20)
	return lbl

# ----------------------------------------------------------
# サイクル処理
# ----------------------------------------------------------
func _cycle_profile(dir: int) -> void:
	_profile_idx = (_profile_idx + dir + AI_PROFILES.size()) % AI_PROFILES.size()
	_profile_value_label.text = PROFILE_LABEL[AI_PROFILES[_profile_idx]]

func _cycle_difficulty(dir: int) -> void:
	_difficulty_idx = (_difficulty_idx + dir + DIFFICULTIES.size()) % DIFFICULTIES.size()
	_difficulty_value_label.text = DIFFICULTY_LABEL[DIFFICULTIES[_difficulty_idx]]

# ----------------------------------------------------------
# ボタン処理
# ----------------------------------------------------------
func _on_fight_button_pressed() -> void:
	GameManager.p1_character_id = "Player"
	GameManager.p2_character_id = "CPU"
	GameManager.cpu_ai_profile  = AI_PROFILES[_profile_idx]
	GameManager.cpu_difficulty  = DIFFICULTIES[_difficulty_idx]
	SceneManager.change_scene_to_file("res://scenes/game/main.tscn")

func _on_back_button_pressed() -> void:
	SceneManager.change_scene_to_file("res://scenes/ui/title.tscn")
