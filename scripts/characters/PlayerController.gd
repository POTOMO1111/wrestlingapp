extends "res://scripts/characters/CharacterBase.gd"

# ============================================================
#  PlayerController.gd  (修正版)
#  - WASD: 移動
#  - ←→キー: カメラ左右回転
#  - Shift: 走る
#  - Space: ジャンプ
#  - J/K/L: 弱攻撃/強攻撃/掴み
#  - I: ブロック
# ============================================================

# ----------------------------------------------------------
# エクスポート変数（インスペクターから調整可能）
# ----------------------------------------------------------
@export var walk_speed    : float = 4.0
@export var run_speed     : float = 8.0
@export var jump_velocity : float = 6.0
@export var gravity_scale : float = 2.0
@export var camera_rotate_speed : float = 90.0  # 度/秒

@export var is_dummy : bool = false

# ----------------------------------------------------------
# 内部変数
# ----------------------------------------------------------
var gravity : float = ProjectSettings.get_setting("physics/3d/default_gravity")

enum State { IDLE, WALK, RUN, JUMP, FALL, ATTACK_LIGHT, ATTACK_HEAVY, GRAPPLE, BLOCK, HIT, DOWN, GRAPPLE_LOCK }
var current_state : State = State.IDLE

var _attack_pending : bool = false
var _state_timer : float = 0.0

# カメラのY軸回転角度（ラジアン）
var _camera_yaw : float = 0.0
var _spring_arm_pitch : float = deg_to_rad(-25.0) # 従来通り見下ろし角度(-25度)を固定でセット

# ----------------------------------------------------------
# ノード参照
# ----------------------------------------------------------
@onready var spring_arm   : SpringArm3D = $SpringArm3D
@onready var anim_tree    : AnimationTree = null
@onready var anim_state   : AnimationNodeStateMachinePlayback = null

# ----------------------------------------------------------
# 初期化
# ----------------------------------------------------------
func _ready() -> void:
	if has_node("AnimationTree"):
		anim_tree = $AnimationTree
		anim_tree.active = true
		if anim_tree.tree_root:
			anim_state = anim_tree.get("parameters/playback")

	# HurtBox が無ければ動的に生成する
	if not has_node("HurtBox"):
		_create_hurtbox()

	# SpringArm をキャラ本体から完全に切り離す（180度反転時のガタつき防止）
	if spring_arm:
		call_deferred("_defer_detach_camera")

# ----------------------------------------------------------
# HurtBox の動的生成（被ダメージ用の当たり判定）
# ----------------------------------------------------------
func _create_hurtbox() -> void:
	var hurtbox := Area3D.new()
	hurtbox.name = "HurtBox"
	hurtbox.add_to_group("hurtbox")
	# HurtBox は検知される側なので monitoring は不要、monitorable を有効に
	hurtbox.monitoring = false
	hurtbox.monitorable = true
	# Layer 5 (hurtbox) に配置。mask は不要（検知される側）
	hurtbox.collision_layer = 16   # Layer 5
	hurtbox.collision_mask  = 0

	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.4
	capsule.height = 1.6
	shape.shape = capsule
	# キャラの中心（腰あたり）に配置
	shape.transform.origin = Vector3(0, 1.0, 0)

	hurtbox.add_child(shape)
	add_child(hurtbox)

func _defer_detach_camera() -> void:
	if not is_inside_tree() or not spring_arm: return
	remove_child(spring_arm)
	get_tree().current_scene.add_child(spring_arm)
	spring_arm.add_excluded_object(self.get_rid())

func _exit_tree() -> void:
	# 孤児になったカメラノードのお掃除
	if spring_arm and spring_arm.get_parent() != self:
		spring_arm.queue_free()

# ----------------------------------------------------------
# メインループ
# ----------------------------------------------------------
func _physics_process(delta: float) -> void:
	if is_dead:
		_apply_gravity(delta)
		move_and_slide()
		_update_spring_arm_position()
		return

	_tick_cooldowns(delta)
	_apply_gravity(delta)
	_handle_camera_rotation(delta)
	_handle_movement(delta)
	_handle_actions()
	move_and_slide()
	_update_spring_arm_position()
	_update_animation()

# ----------------------------------------------------------
# 重力
# ----------------------------------------------------------
func _apply_gravity(delta: float) -> void:
	if current_state == State.GRAPPLE_LOCK: return
	if not is_on_floor():
		velocity.y -= gravity * gravity_scale * delta

# ----------------------------------------------------------
# カメラ回転（右スティック・左右キー）
# ----------------------------------------------------------
func _handle_camera_rotation(delta: float) -> void:
	if is_dummy: return
	if not spring_arm:
		return
	
	var rot_input := 0.0
	if InputMap.has_action("camera_left") and InputMap.has_action("camera_right"):
		rot_input = Input.get_axis("camera_left", "camera_right")
	
	_camera_yaw -= deg_to_rad(rot_input * camera_rotate_speed * delta)

# ----------------------------------------------------------
# SpringArm をキャラに数学的に追従させる
# ----------------------------------------------------------
func _update_spring_arm_position() -> void:
	if is_dummy or not spring_arm or not spring_arm.is_inside_tree():
		return
		
	# Basis（回転行列）をクォータニオンで安全に構築し直し、オイラー角の反転特異点を回避
	var q_yaw = Quaternion(Vector3.UP, _camera_yaw)
	var q_pitch = Quaternion(Vector3.RIGHT, _spring_arm_pitch)
	var new_basis = Basis(q_yaw * q_pitch)
	
	spring_arm.global_transform = Transform3D(new_basis, global_position + Vector3(0, 1.0, 0))

# ----------------------------------------------------------
# 移動処理（WASD）
# ----------------------------------------------------------
func _handle_movement(delta: float) -> void:
	if is_dummy:
		_apply_gravity(delta)
		return

	var is_busy := current_state in [
		State.ATTACK_LIGHT, State.ATTACK_HEAVY,
		State.GRAPPLE, State.HIT, State.DOWN, State.GRAPPLE_LOCK
	]

	# ジャンプ
	if Input.is_action_just_pressed("jump") and is_on_floor() and not is_busy:
		velocity.y = jump_velocity
		_change_state(State.JUMP)
		return

	# ブロック中は移動しない
	if Input.is_action_pressed("block") and is_on_floor() and not is_busy:
		velocity.x = 0
		velocity.z = 0
		_change_state(State.BLOCK)
		return

	if is_busy:
		return

	# WASD / 左スティックの入力を取得 (2D Vector)
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")

	if input_dir.length_squared() < 0.01:
		velocity.x = 0
		velocity.z = 0
		if is_on_floor():
			_change_state(State.IDLE)
		return

	# SpringArm(カメラ)のローカルbasisを使うとプレイヤー自身の回転と干渉してフィードバックループになる問題があったため、
	# 絶対的な _camera_yaw（カメラのY軸回転角）を使用して入力を回転させます。
	# Wキー(前)は -Z 方向なので、 Vector3(x, 0, y) がそのまま適用されます。
	var move_dir := Vector3(input_dir.x, 0, input_dir.y).rotated(Vector3.UP, _camera_yaw).normalized()
	
	var is_running := false
	if Input.is_action_pressed("run") and input_dir.length_squared() > 0.01:
		if consume_stamina(20.0 * delta):
			is_running = true
			
	var speed = run_speed if is_running else walk_speed

	velocity.x = move_dir.x * speed
	velocity.z = move_dir.z * speed

	# キャラの向きを進行方向に向ける
	if move_dir.length_squared() > 0.01:
		var target_angle := atan2(move_dir.x, move_dir.z)
		rotation.y = lerp_angle(rotation.y, target_angle, 10.0 * delta)

	if is_on_floor():
		_change_state(State.RUN if is_running else State.WALK)
	elif velocity.y < 0:
		_change_state(State.FALL)

# ----------------------------------------------------------
# 攻撃・アクション入力（戦闘アクションは InputHandler → CombatController で処理）
# ----------------------------------------------------------
func _handle_actions() -> void:
	pass  # 攻撃入力は InputHandler._input() が一元処理する

# ----------------------------------------------------------
# 状態変更
# ----------------------------------------------------------
func _change_state(new_state: State) -> void:
	if current_state == new_state:
		return
	if current_state in [State.ATTACK_LIGHT, State.ATTACK_HEAVY, State.GRAPPLE]:
		_attack_pending = false
	current_state = new_state
	_state_timer = 0.0

	# RUN 中はスタミナ回復を停止
	is_stamina_regen_active = not (current_state == State.RUN)

# ----------------------------------------------------------
# アニメーション更新
# ----------------------------------------------------------
func _update_animation() -> void:
	if anim_state == null:
		return

	match current_state:
		State.IDLE:         anim_state.travel("Idle")
		State.WALK:         anim_state.travel("Walk")
		State.RUN:          anim_state.travel("Run")
		State.JUMP:         anim_state.travel("JumpUp")
		State.FALL:         anim_state.travel("JumpDown")
		State.ATTACK_LIGHT: anim_state.travel("AttackLight")
		State.ATTACK_HEAVY: anim_state.travel("AttackHeavy")
		State.GRAPPLE:      anim_state.travel("Grapple")
		State.BLOCK:        anim_state.travel("Block")
		State.HIT:          anim_state.travel("Hit")
		State.DOWN:         anim_state.travel("Down")

	# 着地したら IDLE へ
	if current_state == State.FALL and is_on_floor():
		_change_state(State.IDLE)

# ----------------------------------------------------------
# クールダウン
# ----------------------------------------------------------
func _tick_cooldowns(delta: float) -> void:
	_state_timer += delta

	# 攻撃状態の踏み込み減衰（旧アニメーション互換）
	if current_state in [State.ATTACK_LIGHT, State.ATTACK_HEAVY, State.GRAPPLE]:
		velocity.x = move_toward(velocity.x, 0, 20.0 * delta)
		velocity.z = move_toward(velocity.z, 0, 20.0 * delta)

# ----------------------------------------------------------
# ダメージ受け取り（旧システム互換、新システムは HealthComponent 経由）
# ----------------------------------------------------------
func take_damage(_amount: int, knockback_dir: Vector3 = Vector3.ZERO) -> void:
	# ダメージは新システム（HealthComponent）が処理する。
	# ノックバックのみ適用する。
	if knockback_dir != Vector3.ZERO:
		velocity += knockback_dir

# ----------------------------------------------------------
# 掴み・グラップル用インターフェース
# ----------------------------------------------------------
func exit_grapple_lock() -> void:
	# FightManager._on_grapple_ended() から呼ばれる旧互換インターフェース
	if current_state == State.GRAPPLE_LOCK:
		_change_state(State.IDLE)

# ----------------------------------------------------------
# 毎フレーム処理（親クラスのスタミナ回復を通すため必須）
# ----------------------------------------------------------
func _process(delta: float) -> void:
	super._process(delta)
