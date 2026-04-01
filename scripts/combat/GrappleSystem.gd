extends Node

# ============================================================
#  GrappleSystem.gd
#  AutoLoad として登録。組み状態の管理と技の派生を行う。
# ============================================================

enum GrappleState { IDLE, LOCKUP, EXECUTING }
var current_state : GrappleState = GrappleState.IDLE

var _initiator : Node3D = null
var _receiver : Node3D = null
var _input_timer : float = 0.0

const INPUT_WINDOW : float = 1.5

# ----------------------------------------------------------
# テキストエフェクト（ビルボード機能付き）
# ----------------------------------------------------------
func _spawn_text_effect(text: String, pos: Vector3, color: Color = Color.WHITE) -> void:
	var label = Label3D.new()
	label.text = text
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.pixel_size = 0.05
	label.modulate = color
	label.outline_render_priority = 0
	label.outline_size = 8
	label.no_depth_test = true
	get_tree().root.add_child(label)
	label.global_position = pos
	
	var tween = create_tween()
	tween.tween_property(label, "global_position:y", pos.y + 2.0, 1.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 1.0)
	tween.tween_callback(label.queue_free)

# ----------------------------------------------------------
# 組み開始
# ----------------------------------------------------------
func start_grapple(initiator: Node3D, receiver: Node3D) -> void:
	if current_state != GrappleState.IDLE:
		return
		
	_initiator = initiator
	_receiver = receiver
	current_state = GrappleState.LOCKUP
	_input_timer = INPUT_WINDOW
	
	_spawn_text_effect("GRABBED!", _initiator.global_position + Vector3(0, 2.5, 0), Color.YELLOW)
	
	if _initiator.has_method("enter_grapple_lock"):
		_initiator.enter_grapple_lock(true)
	if _receiver.has_method("enter_grapple_lock"):
		_receiver.enter_grapple_lock(false)
		
	var dir_to_receiver = (_receiver.global_position - _initiator.global_position)
	dir_to_receiver.y = 0
	if dir_to_receiver.length() < 0.1:
		dir_to_receiver = -_initiator.global_transform.basis.z
	dir_to_receiver = dir_to_receiver.normalized()
	
	_receiver.global_position = _initiator.global_position + dir_to_receiver * 0.8
	_initiator.rotation.y = atan2(dir_to_receiver.x, dir_to_receiver.z)
	_receiver.rotation.y = atan2(-dir_to_receiver.x, -dir_to_receiver.z)
	
	# 時間経過で自動解除するタイマー
	await get_tree().create_timer(INPUT_WINDOW).timeout
	if current_state == GrappleState.LOCKUP and _initiator == initiator:
		_break_grapple()

# ----------------------------------------------------------
# 追加入力による技の派生
# ----------------------------------------------------------
func receive_input(initiator: Node3D, attack_type: String) -> void:
	if current_state != GrappleState.LOCKUP or initiator != _initiator:
		return
	
	current_state = GrappleState.EXECUTING
	match attack_type:
		"light": _do_body_slam()
		"heavy": _do_suplex()
		_:       _break_grapple()

func _do_body_slam() -> void:
	_spawn_text_effect("BODY SLAM!", _initiator.global_position + Vector3(0, 2.5, 0), Color.RED)
	if _initiator.has_method("play_grapple_attack_anim"):
		_initiator.play_grapple_attack_anim("AttackLight")
		
	var tween = create_tween()
	var lift_pos = _initiator.global_position + Vector3(0, 2.0, 0) + _initiator.global_transform.basis.z * 0.5
	tween.tween_property(_receiver, "global_position", lift_pos, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	
	var slam_pos = _initiator.global_position + _initiator.global_transform.basis.z * 1.5
	slam_pos.y = 0.0
	tween.tween_property(_receiver, "global_position", slam_pos, 0.15).set_delay(0.1).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	
	tween.tween_callback(func():
		var knockback = _initiator.global_transform.basis.z.normalized() * 3.0
		knockback.y = 8.0 # 大きくバステンド
		if _receiver.has_method("take_damage"):
			_receiver.take_damage(15, knockback)
		_end_grapple()
	)

func _do_suplex() -> void:
	_spawn_text_effect("SUPLEX!", _initiator.global_position + Vector3(0, 2.5, 0), Color.MAGENTA)
	if _initiator.has_method("play_grapple_attack_anim"):
		_initiator.play_grapple_attack_anim("AttackHeavy")
		
	var tween = create_tween()
	
	var apex_pos = _initiator.global_position + Vector3(0, 3.0, 0)
	tween.tween_property(_receiver, "global_position", apex_pos, 0.25).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(_receiver, "rotation:x", deg_to_rad(-180), 0.25)
	
	var slam_pos = _initiator.global_position - _initiator.global_transform.basis.z * 2.0
	slam_pos.y = 0.0
	tween.tween_property(_receiver, "global_position", slam_pos, 0.2).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	
	tween.tween_callback(func():
		_receiver.rotation.x = 0
		var knockback = -_initiator.global_transform.basis.z.normalized() * 5.0
		knockback.y = 4.0
		if _receiver.has_method("take_damage"):
			_receiver.take_damage(25, knockback)
		_end_grapple()
	)

func _break_grapple() -> void:
	_spawn_text_effect("BREAK!", _initiator.global_position + Vector3(0, 2.5, 0), Color.GRAY)
	var dir = (_receiver.global_position - _initiator.global_position).normalized()
	dir.y = 0
	if _receiver.has_method("take_damage"): _receiver.take_damage(0, dir * 2.0)
	if _initiator.has_method("take_damage"): _initiator.take_damage(0, -dir * 2.0)
	_end_grapple()

func _end_grapple() -> void:
	if _initiator and _initiator.has_method("exit_grapple_lock"):
		_initiator.exit_grapple_lock()
	if _receiver and _receiver.has_method("exit_grapple_lock"):
		_receiver.exit_grapple_lock()
	_initiator = null
	_receiver = null
	current_state = GrappleState.IDLE
