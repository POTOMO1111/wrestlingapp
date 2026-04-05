class_name HUDController
extends CanvasLayer

# ============================================================
#  HUDController.gd
#  hud.tscn のルートノードにアタッチ。
#  FightManager / GrappleManager のシグナルを受けて表示を更新する。
# ============================================================

@onready var p1_permanent_bar:    ProgressBar = $TopBar/P1_Panel/P1_PermanentHP
@onready var p1_recoverable_bar:  ProgressBar = $TopBar/P1_Panel/P1_RecoverableHP
@onready var p2_permanent_bar:    ProgressBar = $TopBar/P2_Panel/P2_PermanentHP
@onready var p2_recoverable_bar:  ProgressBar = $TopBar/P2_Panel/P2_RecoverableHP
@onready var p1_name_label:       Label       = $TopBar/P1_Panel/P1_Name
@onready var p2_name_label:       Label       = $TopBar/P2_Panel/P2_Name
@onready var round_timer_label:   Label       = $TopBar/CenterPanel/RoundTimer
@onready var round_counter_label: Label       = $TopBar/CenterPanel/RoundCounter
@onready var grapple_panel:       Control     = $GrapplePanel
@onready var dominance_bar:       ProgressBar = $GrapplePanel/DominanceBar

var _fight_manager: FightManager = null

func _ready() -> void:
	_setup_bars()
	grapple_panel.visible = false
	# FightManager は main.gd が生成後に connect_to_fight_manager() を呼ぶ

## FightManager を接続する（main.gd から呼ぶ）
func connect_to_fight_manager(fight_mgr: FightManager) -> void:
	_fight_manager = fight_mgr

	var p1 = fight_mgr.player1
	var p2 = fight_mgr.player2

	var p1_hc: HealthComponent = p1.get_node_or_null("CombatController/HealthComponent") if p1 else null
	var p2_hc: HealthComponent = p2.get_node_or_null("CombatController/HealthComponent") if p2 else null

	if p1_hc:
		p1_permanent_bar.max_value   = p1_hc.stats.max_permanent_hp
		p1_recoverable_bar.max_value = p1_hc.stats.max_recoverable_hp
		p1_permanent_bar.value       = p1_hc.current_permanent_hp
		p1_recoverable_bar.value     = p1_hc.current_recoverable_hp
		p1_hc.permanent_hp_changed.connect(func(v, mx): _update_bar(p1_permanent_bar, v, mx))
		p1_hc.recoverable_hp_changed.connect(func(v, mx): _update_bar(p1_recoverable_bar, v, mx))
		if p1_hc.stats:
			p1_name_label.text = p1_hc.stats.character_name

	if p2_hc:
		p2_permanent_bar.max_value   = p2_hc.stats.max_permanent_hp
		p2_recoverable_bar.max_value = p2_hc.stats.max_recoverable_hp
		p2_permanent_bar.value       = p2_hc.current_permanent_hp
		p2_recoverable_bar.value     = p2_hc.current_recoverable_hp
		p2_hc.permanent_hp_changed.connect(func(v, mx): _update_bar(p2_permanent_bar, v, mx))
		p2_hc.recoverable_hp_changed.connect(func(v, mx): _update_bar(p2_recoverable_bar, v, mx))
		if p2_hc.stats:
			p2_name_label.text = p2_hc.stats.character_name

	fight_mgr.round_started.connect(func(rn): round_counter_label.text = "ROUND %d" % rn)
	fight_mgr.timer_updated.connect(func(t): round_timer_label.text = "%02d" % int(ceil(t)))

	var grapple_mgr: GrappleManager = fight_mgr.get_node_or_null("GrappleManager")
	if grapple_mgr:
		grapple_mgr.dominance_changed.connect(_on_dominance_changed)
		grapple_mgr.grapple_ended.connect(func(_w, _l): grapple_panel.visible = false)

func _setup_bars() -> void:
	# 背景スタイル（全バー共通）
	var bg = StyleBoxFlat.new()
	bg.bg_color = Color(0.08, 0.08, 0.08, 0.9)
	bg.border_width_bottom = 2
	bg.border_width_top    = 2
	bg.border_width_left   = 2
	bg.border_width_right  = 2
	bg.border_color = Color(0.0, 0.0, 0.0, 1.0)
	bg.corner_radius_top_left     = 3
	bg.corner_radius_top_right    = 3
	bg.corner_radius_bottom_left  = 3
	bg.corner_radius_bottom_right = 3

	# 回復不可能HP（赤・太い）
	var perm_fill = StyleBoxFlat.new()
	perm_fill.bg_color = Color(0.9, 0.15, 0.1, 1.0)
	perm_fill.corner_radius_top_left     = 3
	perm_fill.corner_radius_top_right    = 3
	perm_fill.corner_radius_bottom_left  = 3
	perm_fill.corner_radius_bottom_right = 3

	# 回復可能HP（白・細い）
	var rec_fill = StyleBoxFlat.new()
	rec_fill.bg_color = Color(0.95, 0.95, 0.95, 1.0)
	rec_fill.corner_radius_top_left     = 2
	rec_fill.corner_radius_top_right    = 2
	rec_fill.corner_radius_bottom_left  = 2
	rec_fill.corner_radius_bottom_right = 2

	for bar in [p1_permanent_bar, p2_permanent_bar]:
		bar.min_value = 0
		bar.max_value = 100
		bar.value     = 100
		bar.add_theme_stylebox_override("background", bg)
		bar.add_theme_stylebox_override("fill", perm_fill)

	for bar in [p1_recoverable_bar, p2_recoverable_bar]:
		bar.min_value = 0
		bar.max_value = 100
		bar.value     = 100
		bar.add_theme_stylebox_override("background", bg)
		bar.add_theme_stylebox_override("fill", rec_fill)

	if dominance_bar:
		dominance_bar.min_value = 0.0
		dominance_bar.max_value = 1.0
		dominance_bar.value     = 0.5
		var dom_bg = StyleBoxFlat.new()
		dom_bg.bg_color = Color(0.05, 0.05, 0.05, 0.9)
		var dom_fill = StyleBoxFlat.new()
		dom_fill.bg_color = Color(0.2, 0.6, 1.0, 1.0)
		dominance_bar.add_theme_stylebox_override("background", dom_bg)
		dominance_bar.add_theme_stylebox_override("fill", dom_fill)

func _update_bar(bar: ProgressBar, value: float, max_value: float) -> void:
	bar.max_value = max_value
	bar.value     = value

func _on_dominance_changed(new_dominance: float) -> void:
	grapple_panel.visible = true
	dominance_bar.value   = new_dominance
