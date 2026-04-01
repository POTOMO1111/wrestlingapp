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

@export var light_attack_cooldown : float = 0.5
@export var heavy_attack_cooldown : float = 0.9
@export var grapple_cooldown      : float = 1.2

@export var is_dummy : bool = false

# ----------------------------------------------------------
# 内部変数
# ----------------------------------------------------------
var gravity : float = ProjectSettings.get_setting("physics/3d/default_gravity")

enum State { IDLE, WALK, RUN, JUMP, FALL, ATTACK_LIGHT, ATTACK_HEAVY, GRAPPLE, BLOCK, HIT, DOWN, GRAPPLE_LOCK }
var current_state : State = State.IDLE

var _light_cd   : float = 0.0
var _heavy_cd   : float = 0.0
var _grapple_cd : float = 0.0
var _attack_pending : bool = false
var _is_grapple_initiator : bool = false
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
@onready var hitbox_right = null # Area3D型指定を外してduck typingさせ、カスタムプロパティへの代入エラーを防ぐ
@onready var hitbox_left  = null

# ----------------------------------------------------------
# 初期化
# ----------------------------------------------------------
func _ready() -> void:
	if has_node("AnimationTree"):
		anim_tree = $AnimationTree
		anim_tree.active = true
		if anim_tree.tree_root:
			anim_state = anim_tree.get("parameters/playback")

	if has_node("HitboxRight"):
		hitbox_right = $HitboxRight
		hitbox_right.monitoring = false
		if not hitbox_right.grapple_connected.is_connected(_on_grapple_connected):
			hitbox_right.grapple_connected.connect(_on_grapple_connected)

	if has_node("HitboxLeft"):
		hitbox_left = $HitboxLeft
		hitbox_left.monitoring = false

	# SpringArm をキャラ本体から完全に切り離す（180度反転時のガタつき防止）
	if spring_arm:
		call_deferred("_defer_detach_camera")

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
# 攻撃・アクション入力
# ----------------------------------------------------------
func _handle_actions() -> void:
	if is_dummy: return
	if current_state == State.GRAPPLE_LOCK:
		if _is_grapple_initiator:
			if Input.is_action_just_pressed("attack light"):
				GrappleSystem.receive_input(self, "light")
			elif Input.is_action_just_pressed("attack heavy"):
				GrappleSystem.receive_input(self, "heavy")
		return

	var is_busy := current_state in [
		State.ATTACK_LIGHT, State.ATTACK_HEAVY,
		State.GRAPPLE, State.HIT, State.DOWN, State.BLOCK, State.GRAPPLE_LOCK
	]
	if is_busy:
		return

	if Input.is_action_just_pressed("attack light") and _light_cd <= 0.0:
		if consume_stamina(15.0):
			_start_attack(State.ATTACK_LIGHT)
			_light_cd = light_attack_cooldown

	elif Input.is_action_just_pressed("attack heavy") and _heavy_cd <= 0.0:
		if consume_stamina(30.0):
			_start_attack(State.ATTACK_HEAVY)
			_heavy_cd = heavy_attack_cooldown

	elif Input.is_action_just_pressed("grapple") and _grapple_cd <= 0.0:
		if consume_stamina(20.0):
			_start_attack(State.GRAPPLE)
			_grapple_cd = grapple_cooldown

# ----------------------------------------------------------
# 攻撃開始
# ----------------------------------------------------------
func _start_attack(state: State) -> void:
	_change_state(state)
	
	if hitbox_right:
		# HitboxController の設定を動的に変更して弱攻撃・強攻撃・掴みを作り分ける
		if state == State.GRAPPLE:
			hitbox_right.attack_type = 2
		elif state == State.ATTACK_HEAVY:
			hitbox_right.attack_type = 1
			hitbox_right.damage = 20
			hitbox_right.knockback_force = 10.0
			velocity = global_transform.basis.z * -6.0 # 攻撃時に前へ鋭く踏み込む
		else:
			hitbox_right.attack_type = 0
			hitbox_right.damage = 10
			hitbox_right.knockback_force = 3.0
			velocity = global_transform.basis.z * -3.0 # 少し踏み込む
			
	_enable_hitbox(state)
	_attack_pending = true

# ----------------------------------------------------------
# 状態変更
# ----------------------------------------------------------
func _change_state(new_state: State) -> void:
	if current_state == new_state:
		return
	if current_state in [State.ATTACK_LIGHT, State.ATTACK_HEAVY, State.GRAPPLE]:
		_disable_all_hitboxes()
		_attack_pending = false
	current_state = new_state
	_state_timer = 0.0
	
	# アクション中はスタミナ回復を停止
	is_stamina_regen_active = not (current_state in [State.ATTACK_LIGHT, State.ATTACK_HEAVY, State.GRAPPLE, State.RUN])

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
		State.JUMP:         anim_state.travel("Jump")
		State.FALL:         anim_state.travel("Fall")
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
	_light_cd   = max(0.0, _light_cd   - delta)
	_heavy_cd   = max(0.0, _heavy_cd   - delta)
	_grapple_cd = max(0.0, _grapple_cd - delta)
	
	_state_timer += delta
	
	# 攻撃状態の安全装置＆踏み込みの摩擦処理
	if current_state in [State.ATTACK_LIGHT, State.ATTACK_HEAVY, State.GRAPPLE]:
		velocity.x = move_toward(velocity.x, 0, 20.0 * delta)
		velocity.z = move_toward(velocity.z, 0, 20.0 * delta)
		
		# 0.45秒で問答無用に基本状態へ強制復帰
		if _state_timer >= 0.45:
			_attack_pending = false
			_disable_all_hitboxes()
			_change_state(State.IDLE)

# ----------------------------------------------------------
# ヒットボックス制御
# ----------------------------------------------------------
func _enable_hitbox(state: State) -> void:
	if hitbox_right and state in [State.ATTACK_LIGHT, State.ATTACK_HEAVY, State.GRAPPLE]:
		if hitbox_right.has_method("activate"):
			hitbox_right.activate()
		else:
			hitbox_right.monitoring = true

func _disable_all_hitboxes() -> void:
	if hitbox_right: 
		if hitbox_right.has_method("deactivate"): hitbox_right.deactivate()
		else: hitbox_right.monitoring = false
	if hitbox_left:
		if hitbox_left.has_method("deactivate"): hitbox_left.deactivate()
		else: hitbox_left.monitoring = false

# ----------------------------------------------------------
# ダメージ受け取り（外部から呼ばれる）
# ----------------------------------------------------------
func take_damage(amount: int, knockback_dir: Vector3 = Vector3.ZERO) -> void:
	if current_state == State.BLOCK:
		amount = int(amount * 0.2)

	super.take_damage(amount, knockback_dir) # 親クラスのHP減少処理を呼び出す

	if knockback_dir != Vector3.ZERO:
		velocity += knockback_dir * 4.0

	_change_state(State.HIT)
	await get_tree().create_timer(0.4).timeout
	if current_state == State.HIT or current_state == State.GRAPPLE_LOCK:
		_change_state(State.IDLE)

# ----------------------------------------------------------
# 掴み・グラップル用インターフェース
# ----------------------------------------------------------
func _on_grapple_connected(target: Node3D) -> void:
	if target == self: return
	if GrappleSystem.current_state == GrappleSystem.GrappleState.IDLE:
		GrappleSystem.start_grapple(self, target)

func enter_grapple_lock(is_initiator: bool) -> void:
	_change_state(State.GRAPPLE_LOCK)
	_is_grapple_initiator = is_initiator
	velocity = Vector3.ZERO
	if anim_state:
		anim_state.travel("Idle")

func exit_grapple_lock() -> void:
	_is_grapple_initiator = false
	if current_state == State.GRAPPLE_LOCK:
		_change_state(State.IDLE)

func play_grapple_attack_anim(anim_name: String) -> void:
	_change_state(State.ATTACK_LIGHT)
	if anim_state:
		anim_state.travel(anim_name)
	_attack_pending = true

# ----------------------------------------------------------
# デバッグ
# ----------------------------------------------------------
func _process(_delta: float) -> void:
	pass
