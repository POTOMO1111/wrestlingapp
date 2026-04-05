class_name KOSequenceManager
extends Node

# ============================================================
#  KOSequenceManager.gd
#  main.tscn の子ノードとしてアタッチ。
#  KO演出（ヒットストップ → スローモーション → KOテキスト）を管理。
# ============================================================

@export var fight_manager: FightManager

const FREEZE_DURATION:    float = 0.3
const SLOWMO_DURATION:    float = 0.8
const SLOWMO_TIME_SCALE:  float = 0.15
const KO_TEXT_DURATION:   float = 2.0
const NEXT_ROUND_DELAY:   float = 3.0

# KO_Overlay CanvasLayer を子ノードに持つこと
@onready var ko_overlay: CanvasLayer = $KO_Overlay
@onready var ko_label:   Label       = $KO_Overlay/KO_Label

var _match_ended: bool = false

func _ready() -> void:
	ko_overlay.visible = false
	# fight_manager は main.gd から setup() で設定される
	if fight_manager != null:
		_connect_signals()

## main.gd から呼び出してシグナルを接続する
func setup(fm: FightManager) -> void:
	fight_manager = fm
	_connect_signals()

func _connect_signals() -> void:
	if fight_manager == null:
		push_error("KOSequenceManager: fight_manager が未割り当てです")
		return
	if not fight_manager.ko_triggered.is_connected(_on_ko_triggered):
		fight_manager.ko_triggered.connect(_on_ko_triggered)
	if not fight_manager.round_ended.is_connected(_on_round_ended):
		fight_manager.round_ended.connect(_on_round_ended)
	if not fight_manager.match_ended.is_connected(_on_match_ended):
		fight_manager.match_ended.connect(_on_match_ended)

func _on_ko_triggered(_loser: Node) -> void:
	# Step 1: ヒットストップ（完全停止）
	Engine.time_scale = 0.0
	await get_tree().create_timer(FREEZE_DURATION, true, false, true).timeout

	# Step 2: スローモーション
	Engine.time_scale = SLOWMO_TIME_SCALE
	await get_tree().create_timer(SLOWMO_DURATION, true, false, true).timeout
	Engine.time_scale = 1.0

	# Step 3: KOテキスト表示
	if not _match_ended:
		ko_label.text = "K.O."
		ko_overlay.visible = true
		var tween = create_tween()
		tween.tween_property(ko_label, "scale", Vector2(1.5, 1.5), 0.3).from(Vector2(0.3, 0.3))
		await get_tree().create_timer(KO_TEXT_DURATION).timeout
		ko_overlay.visible = false

func _on_round_ended(_winner_id: GameEnums.PlayerID) -> void:
	if _match_ended:
		return
	await get_tree().create_timer(NEXT_ROUND_DELAY).timeout
	if not _match_ended and fight_manager:
		fight_manager.start_round()

func _on_match_ended(winner_id: GameEnums.PlayerID) -> void:
	_match_ended = true
	var winner_num = 1 if winner_id == GameEnums.PlayerID.PLAYER_ONE else 2
	ko_label.text = "PLAYER %d\nWINS!" % winner_num
	ko_overlay.visible = true
	var tween = create_tween()
	tween.tween_property(ko_label, "scale", Vector2(1.3, 1.3), 0.5).from(Vector2(0.2, 0.2))
	# 少し待ってから GameManager に通知して結果メニュー（キャラ選択ボタン等）を表示
	await get_tree().create_timer(2.0).timeout
	var loser_num = 3 - winner_num  # 1→2, 2→1
	var gm = get_node_or_null("/root/GameManager")
	if gm and gm.has_method("on_fighter_down"):
		gm.on_fighter_down(loser_num)
