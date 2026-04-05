class_name DebugOverlay
extends CanvasLayer

# ============================================================
#  DebugOverlay.gd
#  戦闘デバッグ用オーバーレイ。
#  main.gd から setup() を呼ぶことで各種シグナルと接続する。
#  GameManager.debug_mode が true の場合のみ表示される。
# ============================================================

const MAX_LOG = 25          # ログ最大行数
const LOG_COLOR_DEFAULT  := Color(0.9, 0.9, 0.9)
const LOG_COLOR_DAMAGE   := Color(1.0, 0.4, 0.3)
const LOG_COLOR_SYSTEM   := Color(0.4, 0.9, 1.0)
const LOG_COLOR_STATE    := Color(0.8, 1.0, 0.4)
const LOG_COLOR_KO       := Color(1.0, 0.9, 0.1)

var _log_label: RichTextLabel
var _p1_label: Label
var _p2_label: Label
var _frame_label: Label

var _log_entries: Array[String] = []

# キャラクターの HealthComponent 参照（ライブ更新用）
var _p1_health: HealthComponent = null
var _p2_health: HealthComponent = null
var _p1_ctrl: CombatController = null
var _p2_ctrl: CombatController = null

# フレームカウンタ（ログのタイムスタンプ代わり）
var _frame: int = 0

func _ready() -> void:
	layer = 100  # 最前面に描画
	_build_ui()

func _process(_delta: float) -> void:
	_frame += 1
	# 毎フレームライブステータスを更新
	if _frame % 6 == 0:  # 6フレームに1回（パフォーマンス考慮）
		_refresh_status()

# ----------------------------------------------------------
# UI 構築
# ----------------------------------------------------------
func _build_ui() -> void:
	# 背景パネル（左下：ログ）
	var log_panel = PanelContainer.new()
	log_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	log_panel.offset_left = 8
	log_panel.offset_top = -480
	log_panel.offset_right = 520
	log_panel.offset_bottom = -8
	var log_style = StyleBoxFlat.new()
	log_style.bg_color = Color(0, 0, 0, 0.72)
	log_style.border_width_left = 2
	log_style.border_color = Color(0.3, 0.6, 1.0, 0.8)
	log_panel.add_theme_stylebox_override("panel", log_style)
	add_child(log_panel)

	var log_margin = MarginContainer.new()
	log_margin.add_theme_constant_override("margin_left", 8)
	log_margin.add_theme_constant_override("margin_right", 8)
	log_margin.add_theme_constant_override("margin_top", 6)
	log_margin.add_theme_constant_override("margin_bottom", 6)
	log_panel.add_child(log_margin)

	_log_label = RichTextLabel.new()
	_log_label.bbcode_enabled = true
	_log_label.scroll_active = false
	_log_label.fit_content = false
	_log_label.add_theme_font_size_override("normal_font_size", 13)
	_log_label.add_theme_font_size_override("bold_font_size", 13)
	log_margin.add_child(_log_label)

	# 上部：ライブステータス（HP等）
	var status_panel = PanelContainer.new()
	status_panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	status_panel.offset_top = 100
	status_panel.offset_bottom = 175
	status_panel.offset_left = 20
	status_panel.offset_right = -20
	var st_style = StyleBoxFlat.new()
	st_style.bg_color = Color(0, 0, 0, 0.65)
	st_style.border_width_bottom = 2
	st_style.border_color = Color(1.0, 0.6, 0.1, 0.8)
	status_panel.add_theme_stylebox_override("panel", st_style)
	add_child(status_panel)

	var st_hbox = HBoxContainer.new()
	st_hbox.add_theme_constant_override("separation", 20)
	status_panel.add_child(st_hbox)

	_p1_label = Label.new()
	_p1_label.add_theme_font_size_override("font_size", 14)
	_p1_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_p1_label.text = "P1: ---"
	st_hbox.add_child(_p1_label)

	_p2_label = Label.new()
	_p2_label.add_theme_font_size_override("font_size", 14)
	_p2_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_p2_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_p2_label.text = "P2: ---"
	st_hbox.add_child(_p2_label)

# ----------------------------------------------------------
# 外部から呼ぶ接続処理
# ----------------------------------------------------------
func setup(fight_mgr: FightManager) -> void:
	if fight_mgr == null:
		log_event("[DebugOverlay] ERROR: fight_manager is null", LOG_COLOR_DAMAGE)
		return

	var p1 = fight_mgr.player1
	var p2 = fight_mgr.player2

	_p1_health = p1.get_node_or_null("CombatController/HealthComponent") if p1 else null
	_p2_health = p2.get_node_or_null("CombatController/HealthComponent") if p2 else null
	_p1_ctrl   = p1.get_node_or_null("CombatController") if p1 else null
	_p2_ctrl   = p2.get_node_or_null("CombatController") if p2 else null

	_connect_character(p1, "P1")
	_connect_character(p2, "P2")

	fight_mgr.round_started.connect(func(rn): log_event("=== ROUND %d START ===" % rn, LOG_COLOR_SYSTEM))
	fight_mgr.round_ended.connect(func(w): log_event("=== ROUND END (w:%s) ===" % _pid(w), LOG_COLOR_SYSTEM))
	fight_mgr.match_ended.connect(func(w): log_event("=== MATCH END — %s WINS ===" % _pid(w), LOG_COLOR_KO))

	log_event("[DebugOverlay] 接続完了 p1=%s p2=%s" % [
		p1.name if p1 else "null",
		p2.name if p2 else "null"
	], LOG_COLOR_SYSTEM)

func _connect_character(char_node: Node, label: String) -> void:
	if char_node == null:
		log_event("[DebugOverlay] %s: char_node is null" % label, LOG_COLOR_DAMAGE)
		return

	var ctrl: CombatController = char_node.get_node_or_null("CombatController")
	var hc:   HealthComponent  = char_node.get_node_or_null("CombatController/HealthComponent")
	var hbm:  HitboxManager    = char_node.get_node_or_null("CombatController/HitboxManager")
	var ih:   InputHandler     = char_node.get_node_or_null("InputHandler")

	log_event("[%s] ctrl=%s hc=%s hbm=%s ih=%s" % [label,
		"OK" if ctrl else "NULL",
		"OK" if hc  else "NULL",
		"OK" if hbm else "NULL",
		"OK" if ih  else "none"
	], LOG_COLOR_SYSTEM)

	# キャラクターの子ノード一覧をコンソールに出力（詳細診断）
	print("[DebugOverlay] %s children:" % label)
	for c in char_node.get_children():
		print("  - %s (%s)" % [c.name, c.get_class()])
		for cc in c.get_children():
			print("    - %s (%s)" % [cc.name, cc.get_class()])

	if ctrl == null:
		log_event("[DebugOverlay] %s: CombatController not found!" % label, LOG_COLOR_DAMAGE)
	else:
		ctrl.state_changed.connect(func(s):
			log_event("[%s] state → [b]%s[/b]" % [label, _state_name(s)], LOG_COLOR_STATE)
		)

	# InputHandler シグナル接続（P1 のみ存在する）
	if ih:
		ih.input_received.connect(func(a):
			log_event("[%s] INPUT → %s" % [label, GameEnums.ActionType.keys()[a]], LOG_COLOR_SYSTEM)
		)

	if hc == null:
		log_event("[DebugOverlay] %s: HealthComponent not found!" % label, LOG_COLOR_DAMAGE)
	else:
		hc.permanent_hp_changed.connect(func(v, mx):
			log_event("[%s] perm HP: [b]%.0f / %.0f[/b]" % [label, v, mx], LOG_COLOR_DAMAGE)
		)
		hc.recoverable_hp_changed.connect(func(v, mx):
			log_event("[%s] rec HP:  %.0f / %.0f" % [label, v, mx], LOG_COLOR_DEFAULT)
		)
		hc.permanent_hp_depleted.connect(func():
			log_event("[b][%s] ★ KO ★[/b]" % label, LOG_COLOR_KO)
		)
		hc.recoverable_hp_depleted.connect(func():
			log_event("[%s] incapacitated!" % label, LOG_COLOR_DAMAGE)
		)

	if hbm == null:
		log_event("[DebugOverlay] %s: HitboxManager not found!" % label, LOG_COLOR_DAMAGE)
	else:
		hbm.hit_landed.connect(func(target, atk, res):
			var tname = target.name if target else "?"
			var aname = (atk.attack_name if atk.attack_name != "" else "???") if atk else "null"
			log_event("[%s→%s] HIT [b]%s[/b] | %s  rec:%.0f  perm:%.0f" % [
				label, tname, aname, _hit_result_name(res),
				atk.recoverable_damage if atk else 0.0,
				atk.permanent_damage if atk else 0.0
			], LOG_COLOR_DAMAGE)
		)
		hbm.grapple_initiated.connect(func(target, _gd):
			var tname = target.name if target else "?"
			log_event("[%s→%s] GRAPPLE initiated" % [label, tname], LOG_COLOR_STATE)
		)

# ----------------------------------------------------------
# ログ追加
# ----------------------------------------------------------
func log_event(text: String, color: Color = LOG_COLOR_DEFAULT) -> void:
	var hex = "#%02x%02x%02x" % [
		int(color.r * 255), int(color.g * 255), int(color.b * 255)
	]
	var f = _frame
	var entry = "[color=%s][f%05d] %s[/color]" % [hex, f, text]
	_log_entries.append(entry)
	if _log_entries.size() > MAX_LOG:
		_log_entries.pop_front()
	_log_label.text = "\n".join(_log_entries)

# ----------------------------------------------------------
# ライブステータス更新
# ----------------------------------------------------------
func _refresh_status() -> void:
	if _p1_health and _p1_ctrl:
		_p1_label.text = "P1 | perm:%.0f/%.0f  rec:%.0f/%.0f  state:%s" % [
			_p1_health.current_permanent_hp, _p1_health.stats.max_permanent_hp if _p1_health.stats else 0,
			_p1_health.current_recoverable_hp, _p1_health.stats.max_recoverable_hp if _p1_health.stats else 0,
			_state_name(_p1_ctrl.get_current_state())
		]
	if _p2_health and _p2_ctrl:
		_p2_label.text = "P2 | perm:%.0f/%.0f  rec:%.0f/%.0f  state:%s" % [
			_p2_health.current_permanent_hp, _p2_health.stats.max_permanent_hp if _p2_health.stats else 0,
			_p2_health.current_recoverable_hp, _p2_health.stats.max_recoverable_hp if _p2_health.stats else 0,
			_state_name(_p2_ctrl.get_current_state())
		]

# ----------------------------------------------------------
# ユーティリティ
# ----------------------------------------------------------
func _state_name(s: GameEnums.CharacterState) -> String:
	match s:
		GameEnums.CharacterState.IDLE:          return "IDLE"
		GameEnums.CharacterState.WALKING:       return "WALKING"
		GameEnums.CharacterState.RUNNING:       return "RUNNING"
		GameEnums.CharacterState.ATTACKING:     return "ATTACKING"
		GameEnums.CharacterState.GUARDING:      return "GUARDING"
		GameEnums.CharacterState.GRAPPLING:     return "GRAPPLING"
		GameEnums.CharacterState.GRAPPLED:      return "GRAPPLED"
		GameEnums.CharacterState.HIT_STUN:      return "HIT_STUN"
		GameEnums.CharacterState.KNOCKDOWN:     return "KNOCKDOWN"
		GameEnums.CharacterState.GETTING_UP:    return "GETTING_UP"
		GameEnums.CharacterState.INCAPACITATED: return "INCAP"
		GameEnums.CharacterState.KO:            return "KO"
	return "?"

func _hit_result_name(r: GameEnums.HitResult) -> String:
	match r:
		GameEnums.HitResult.HIT:             return "HIT"
		GameEnums.HitResult.COUNTER_HIT:     return "COUNTER"
		GameEnums.HitResult.BLOCKED:         return "BLOCK"
		GameEnums.HitResult.GRAPPLE_SUCCESS: return "GRAPPLE"
	return "?"

func _pid(p: GameEnums.PlayerID) -> String:
	return "P1" if p == GameEnums.PlayerID.PLAYER_ONE else "P2"
