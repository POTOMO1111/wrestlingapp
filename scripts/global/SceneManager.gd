extends Node

# ============================================================
#  SceneManager.gd
#  AutoLoad として登録し、全シーンの遷移（フェード）を管理する
# ============================================================

var _canvas : CanvasLayer = null
var _color_rect : ColorRect = null
var is_transitioning : bool = false

func _ready() -> void:
	_canvas = CanvasLayer.new()
	_canvas.layer = 100 # 最前面
	add_child(_canvas)
	
	_color_rect = ColorRect.new()
	_color_rect.color = Color(0, 0, 0, 0)
	_color_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_color_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(_color_rect)

func change_scene_to_file(path: String, fade_in_time: float = 0.5, fade_out_time: float = 0.5) -> void:
	if is_transitioning:
		return
	is_transitioning = true
	
	# フェードアウト（画面暗転）
	_color_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	var tween = create_tween()
	tween.tween_property(_color_rect, "color:a", 1.0, fade_out_time)
	await tween.finished
	
	# シーン切り替え
	var err = get_tree().change_scene_to_file(path)
	if err != OK:
		push_error("Failed to load scene: %s" % path)
	
	# ちょっとだけ間を置く
	await get_tree().create_timer(0.1).timeout
	
	# フェードイン（画面明転）
	tween = create_tween()
	tween.tween_property(_color_rect, "color:a", 0.0, fade_in_time)
	tween.tween_callback(func():
		_color_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		is_transitioning = false
	)
