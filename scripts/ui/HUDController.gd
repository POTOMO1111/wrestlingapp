class_name HUDController
extends CanvasLayer

# ============================================================
#  HUDController.gd
#  hud.tscn のルートノードにアタッチ。
#  FightManager / GrappleManager のシグナルを受けて表示を更新する。
#
#  【ドミナンスバーの方向】
#    常に「左=プレイヤー（青）, 右=CPU（赤）」で固定。
#    P2 がグラップルを起こした場合は dominance 値を反転して表示。
# ============================================================

@onready var p1_panel_bg:         PanelContainer = $TopBar/P1_PanelBG
@onready var p2_panel_bg:         PanelContainer = $TopBar/P2_PanelBG
@onready var p1_permanent_bar:    ProgressBar    = $TopBar/P1_PanelBG/P1_Panel/P1_PermanentHP
@onready var p1_recoverable_bar:  ProgressBar    = $TopBar/P1_PanelBG/P1_Panel/P1_RecoverableHP
@onready var p2_permanent_bar:    ProgressBar    = $TopBar/P2_PanelBG/P2_Panel/P2_PermanentHP
@onready var p2_recoverable_bar:  ProgressBar    = $TopBar/P2_PanelBG/P2_Panel/P2_RecoverableHP
@onready var p1_name_label:       Label          = $TopBar/P1_PanelBG/P1_Panel/P1_Name
@onready var p2_name_label:       Label          = $TopBar/P2_PanelBG/P2_Panel/P2_Name
@onready var round_timer_label:   Label          = $TopBar/CenterPanel/RoundTimer
@onready var round_counter_label: Label          = $TopBar/CenterPanel/RoundCounter
@onready var grapple_panel:       Control        = $GrapplePanel
@onready var dominance_bar:       ProgressBar    = $GrapplePanel/BarRow/DominanceBar
@onready var initiator_label:     Label          = $GrapplePanel/BarRow/InitiatorLabel
@onready var receiver_label:      Label          = $GrapplePanel/BarRow/ReceiverLabel

var _fight_manager: FightManager = null
var _p1_name: String = "P1"
var _p2_name: String = "CPU"
# P1 がグラップルを起こした側か（false なら値を反転してバー表示）
var _is_p1_initiator: bool = true

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
			_p1_name = p1_hc.stats.character_name

	if p2_hc:
		p2_permanent_bar.max_value   = p2_hc.stats.max_permanent_hp
		p2_recoverable_bar.max_value = p2_hc.stats.max_recoverable_hp
		p2_permanent_bar.value       = p2_hc.current_permanent_hp
		p2_recoverable_bar.value     = p2_hc.current_recoverable_hp
		p2_hc.permanent_hp_changed.connect(func(v, mx): _update_bar(p2_permanent_bar, v, mx))
		p2_hc.recoverable_hp_changed.connect(func(v, mx): _update_bar(p2_recoverable_bar, v, mx))
		if p2_hc.stats:
			p2_name_label.text = p2_hc.stats.character_name
			_p2_name = p2_hc.stats.character_name

	fight_mgr.round_started.connect(func(rn): round_counter_label.text = "ROUND %d" % rn)
	fight_mgr.timer_updated.connect(func(t): round_timer_label.text = "%02d" % int(ceil(t)))

	var grapple_mgr: GrappleManager = fight_mgr.get_node_or_null("GrappleManager")
	if grapple_mgr:
		grapple_mgr.grapple_started.connect(_on_grapple_started)
		grapple_mgr.dominance_changed.connect(_on_dominance_changed)
		grapple_mgr.grapple_ended.connect(func(_w, _l): grapple_panel.visible = false)

func _setup_bars() -> void:
	# ---- P1 パネル背景（青） ----
	var p1_bg := StyleBoxFlat.new()
	p1_bg.bg_color = Color(0.06, 0.14, 0.40, 0.70)
	p1_bg.corner_radius_top_left     = 5
	p1_bg.corner_radius_top_right    = 5
	p1_bg.corner_radius_bottom_left  = 5
	p1_bg.corner_radius_bottom_right = 5
	p1_panel_bg.add_theme_stylebox_override("panel", p1_bg)

	# ---- P2 パネル背景（赤） ----
	var p2_bg := StyleBoxFlat.new()
	p2_bg.bg_color = Color(0.40, 0.06, 0.06, 0.70)
	p2_bg.corner_radius_top_left     = 5
	p2_bg.corner_radius_top_right    = 5
	p2_bg.corner_radius_bottom_left  = 5
	p2_bg.corner_radius_bottom_right = 5
	p2_panel_bg.add_theme_stylebox_override("panel", p2_bg)

	# ---- HP バー共通背景 ----
	var bg := StyleBoxFlat.new()
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
	var perm_fill := StyleBoxFlat.new()
	perm_fill.bg_color = Color(0.9, 0.15, 0.1, 1.0)
	perm_fill.corner_radius_top_left     = 3
	perm_fill.corner_radius_top_right    = 3
	perm_fill.corner_radius_bottom_left  = 3
	perm_fill.corner_radius_bottom_right = 3

	# 回復可能HP（白・細い）
	var rec_fill := StyleBoxFlat.new()
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

	# ---- ドミナンスバー: 左=プレイヤー（青）、右=CPU（赤） ----
	if dominance_bar:
		dominance_bar.min_value = 0.0
		dominance_bar.max_value = 1.0
		dominance_bar.value     = 0.5
		# 背景 = CPU 側（赤）
		var dom_bg := StyleBoxFlat.new()
		dom_bg.bg_color = Color(0.70, 0.10, 0.10, 1.0)
		dom_bg.corner_radius_top_left     = 3
		dom_bg.corner_radius_top_right    = 3
		dom_bg.corner_radius_bottom_left  = 3
		dom_bg.corner_radius_bottom_right = 3
		# フィル = プレイヤー側（青）
		var dom_fill := StyleBoxFlat.new()
		dom_fill.bg_color = Color(0.15, 0.45, 0.90, 1.0)
		dom_fill.corner_radius_top_left     = 3
		dom_fill.corner_radius_top_right    = 3
		dom_fill.corner_radius_bottom_left  = 3
		dom_fill.corner_radius_bottom_right = 3
		dominance_bar.add_theme_stylebox_override("background", dom_bg)
		dominance_bar.add_theme_stylebox_override("fill", dom_fill)

func _update_bar(bar: ProgressBar, value: float, max_value: float) -> void:
	bar.max_value = max_value
	bar.value     = value

func _on_grapple_started(initiator: Node, receiver: Node) -> void:
	var ctrl: Node = initiator.get_node_or_null("CombatController")
	_is_p1_initiator = not ctrl or ctrl.player_id == GameEnums.PlayerID.PLAYER_ONE
	# バーの向きは常に「左=P1（プレイヤー）、右=P2（CPU）」に固定
	initiator_label.text = _p1_name
	receiver_label.text  = _p2_name
	dominance_bar.value  = 0.5
	grapple_panel.visible = true

func _on_dominance_changed(new_dominance: float) -> void:
	# dominance=1.0 → 攻め側勝利。P1 が攻め側なら右に、P2 が攻め側なら左に振れる
	# → 常に「P1 有利なら右（大きい値）」になるよう P2 攻め時は反転
	var player_value: float = new_dominance if _is_p1_initiator else 1.0 - new_dominance
	dominance_bar.value = player_value
