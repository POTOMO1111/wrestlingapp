extends "res://scripts/characters/CharacterBase.gd"

# ============================================================
#  PlayerController.gd
#  - WASD: 移動（常に相手方向基準）
#  - Shift: ステップ回避（一瞬だけ高速移動、前半無敵）
#  - Space: ジャンプ
#  - J/K/L: 弱攻撃/強攻撃/掴み
#  - I: ブロック
# ============================================================

# ----------------------------------------------------------
# エクスポート変数（インスペクターから調整可能）
# ----------------------------------------------------------
@export var walk_speed    : float = 2.0
@export var gravity_scale : float = 2.0

# カメラ設定
@export var camera_distance    : float = 1.5   # SpringArm 長さ(m)
@export var camera_side_offset : float = 0.7   # 右オフセット(m): 正値でプレイヤーが画面左寄りに

# ステップ設定
@export var step_distance     : float = 1.2   # 移動距離(m)≒キャラ1体分
@export var step_duration     : float = 0.15  # 所要時間(秒)
@export var step_cooldown     : float = 0.4   # 連続発動クールダウン(秒)
@export var step_stamina_cost : float = 8.0   # 発動ごとの回復可能HP消費

@export var is_dummy : bool = false

# ----------------------------------------------------------
# 内部変数
# ----------------------------------------------------------
var gravity : float = ProjectSettings.get_setting("physics/3d/default_gravity")

enum State { IDLE, WALK, RUN, JUMP, FALL, ATTACK_LIGHT, ATTACK_HEAVY, GRAPPLE, BLOCK, HIT, DOWN, GRAPPLE_LOCK, STEP }
var current_state : State = State.IDLE

var _attack_pending : bool = false
var _state_timer : float = 0.0

# ステップ管理
var _step_timer         : float   = 0.0          # 残りステップ時間
var _step_cooldown_timer: float   = 0.0          # クールダウン残り
var _step_direction     : Vector3 = Vector3.ZERO # ステップ方向（ワールド座標）

# 相手キャラへの参照（常時相手方向を向く制御に使用）。main.gd で代入。
var opponent: CharacterBody3D = null

# カメラのY軸回転角度（ラジアン）— 毎フレーム rotation.y に追従する
var _camera_yaw : float = 0.0
var _spring_arm_pitch : float = deg_to_rad(-25.0) # 見下ろし角度(-25度)固定

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
	spring_arm.spring_length = camera_distance

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
	_face_opponent(delta)
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
# 常時相手方向を向く（P1・CPUController 共通）
# ----------------------------------------------------------
func _face_opponent(delta: float) -> void:
	if not opponent:
		return
	var dir := opponent.global_position - global_position
	dir.y = 0.0
	if dir.length_squared() < 0.01:
		return
	var target_angle := atan2(dir.x, dir.z)
	rotation.y = lerp_angle(rotation.y, target_angle, 15.0 * delta)

# ----------------------------------------------------------
# SpringArm をキャラに数学的に追従させる
# ----------------------------------------------------------
func _update_spring_arm_position() -> void:
	if is_dummy or not spring_arm or not spring_arm.is_inside_tree():
		return

	# キャラの向き（常に相手方向）にカメラを追従させる
	# SpringArm は -Z 方向に腕を伸ばすため、キャラ背後に配置するには PI を加算する
	_camera_yaw = rotation.y + PI
	var q_yaw   = Quaternion(Vector3.UP, _camera_yaw)
	var q_pitch = Quaternion(Vector3.RIGHT, _spring_arm_pitch)
	var new_basis = Basis(q_yaw * q_pitch)

	# -basis.x = スクリーン右方向。pivot を右にずらすとプレイヤーが画面左寄りになり
	# 中央〜右に相手キャラが見えるようになる
	var pivot := global_position + Vector3(0, 1.2, 0) \
		+ (-global_transform.basis.x) * camera_side_offset
	spring_arm.global_transform = Transform3D(new_basis, pivot)

# ----------------------------------------------------------
# 移動処理（WASD）
# ----------------------------------------------------------
func _handle_movement(delta: float) -> void:
	if is_dummy:
		_apply_gravity(delta)
		return

	# 戦闘アクション中は移動禁止（グラップル・攻撃）
	var cc := get_node_or_null("CombatController")
	if cc and cc.has_method("get_current_state"):
		var cc_state: GameEnums.CharacterState = cc.get_current_state()
		if cc_state in [
			GameEnums.CharacterState.GRAPPLING,
			GameEnums.CharacterState.GRAPPLED,
			GameEnums.CharacterState.ATTACKING
		]:
			velocity.x = 0
			velocity.z = 0
			return

	# ――― ステップ実行中 ―――
	if current_state == State.STEP:
		_step_timer -= delta
		# 前半は無敵（Hurtbox を無効化）、後半は有効に戻す
		_set_hurtbox_enabled(_step_timer <= step_duration * 0.5)
		var step_speed := step_distance / step_duration
		velocity.x = _step_direction.x * step_speed
		velocity.z = _step_direction.z * step_speed
		if _step_timer <= 0.0:
			_set_hurtbox_enabled(true)
			var end_input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
			if end_input.length_squared() > 0.01:
				_change_state(State.WALK)
			else:
				velocity.x = 0
				velocity.z = 0
				_change_state(State.IDLE)
		return

	var is_busy := current_state in [
		State.ATTACK_LIGHT, State.ATTACK_HEAVY,
		State.GRAPPLE, State.HIT, State.DOWN, State.GRAPPLE_LOCK
	]

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

	# ――― ステップ発動チェック ―――
	if Input.is_action_just_pressed("run") and _step_cooldown_timer <= 0.0:
		# スタミナ（回復可能HP）が足りる場合のみ発動
		if consume_stamina(step_stamina_cost):
			var forward := global_transform.basis.z
			var right   := -global_transform.basis.x
			if input_dir.length_squared() > 0.01:
				# 移動キーがある → その方向にステップ
				_step_direction = (forward * (-input_dir.y) + right * input_dir.x).normalized()
			else:
				# 移動キーなし → 後方（相手から離れる方向）にステップ
				_step_direction = -forward
			_step_timer = step_duration
			_step_cooldown_timer = step_cooldown
			_set_hurtbox_enabled(false)  # 即座に無敵開始
			_spawn_step_effect(global_position, _step_direction)
			_change_state(State.STEP)
			return

	# ――― 通常移動 ―――
	if input_dir.length_squared() < 0.01:
		velocity.x = 0
		velocity.z = 0
		if is_on_floor():
			_change_state(State.IDLE)
		return

	# キャラは常に相手を向いているため、キャラ自身のbasisを移動基準に使う
	# basis.z = モデル前方（相手方向）、-basis.x = 画面上の右方向
	var forward  := global_transform.basis.z
	var right    := -global_transform.basis.x
	var move_dir := (forward * (-input_dir.y) + right * input_dir.x).normalized()

	velocity.x = move_dir.x * walk_speed
	velocity.z = move_dir.z * walk_speed

	if is_on_floor():
		_change_state(State.WALK)
	elif velocity.y < 0:
		_change_state(State.FALL)

# ----------------------------------------------------------
# ステップ無敵：HitboxManager の Hurtbox の monitorable を切り替える
# ----------------------------------------------------------
func _set_hurtbox_enabled(enabled: bool) -> void:
	var hurtbox := get_node_or_null("CombatController/HitboxManager/Hurtbox")
	if hurtbox is Area3D:
		(hurtbox as Area3D).monitorable = enabled

# ----------------------------------------------------------
# ステップエフェクト
# 将来の本格エフェクト差し替えポイント：
#   _spawn_step_trail() を差し替えるか、3Dモデルを別途 add_child するだけで対応可能
# ----------------------------------------------------------
func _spawn_step_effect(pos: Vector3, dir: Vector3) -> void:
	_spawn_step_trail(pos, dir)

func _spawn_step_trail(pos: Vector3, dir: Vector3) -> void:
	if dir.length_squared() < 0.01:
		return

	# キャラの右方向（ラインを左右にオフセットするため）
	var right := dir.cross(Vector3.UP).normalized()

	# 3本の残像ラインを左・中・右にオフセットして生成（index 0,1,2 → offset -0.18, 0.0, +0.18）
	for idx in 3:
		var off: float = (idx - 1) * 0.18

		var mesh_inst := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.03, 0.03, 0.45)  # 細長い箱（移動線）
		mesh_inst.mesh = box

		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.75, 0.9, 1.0, 0.65)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.cull_mode    = BaseMaterial3D.CULL_DISABLED
		mesh_inst.material_override = mat

		get_tree().root.add_child(mesh_inst)

		# ステップ方向の後方からやや浮かせた位置に配置
		var spawn_pos := pos + Vector3(0, 1.0, 0) + right * off - dir * 0.3
		mesh_inst.global_position = spawn_pos

		# 移動方向を向かせる
		mesh_inst.look_at(spawn_pos + dir, Vector3.UP)

		# 0.2秒でフェードアウトして自動削除
		var tween := mesh_inst.create_tween()
		tween.tween_property(mat, "albedo_color:a", 0.0, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tween.tween_callback(mesh_inst.queue_free)

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

	# STEP 中はスタミナ回復を停止
	is_stamina_regen_active = not (current_state == State.STEP)

# ----------------------------------------------------------
# アニメーション更新
# ----------------------------------------------------------
func _update_animation() -> void:
	if anim_state == null:
		return

	# CombatController が IDLE/WALKING/RUNNING 以外のステートを持つ場合は
	# アニメーション制御を CombatController に委ねる（毎フレーム上書きを防ぐ）
	var ctrl = get_node_or_null("CombatController")
	if ctrl and ctrl.has_method("get_current_state"):
		var cs: int = ctrl.get_current_state()
		if cs != GameEnums.CharacterState.IDLE and \
		   cs != GameEnums.CharacterState.WALKING and \
		   cs != GameEnums.CharacterState.RUNNING:
			return

	match current_state:
		State.IDLE: anim_state.travel("Idle")
		State.WALK: anim_state.travel("Walk")
		State.STEP: anim_state.travel("Walk")  # 専用モーション追加まで Walk 流用
		State.RUN:  anim_state.travel("Run")

# ----------------------------------------------------------
# クールダウン
# ----------------------------------------------------------
func _tick_cooldowns(delta: float) -> void:
	_state_timer += delta

	if _step_cooldown_timer > 0.0:
		_step_cooldown_timer -= delta

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
func is_stepping() -> bool:
	return current_state == State.STEP

func exit_grapple_lock() -> void:
	# FightManager._on_grapple_ended() から呼ばれる旧互換インターフェース
	if current_state == State.GRAPPLE_LOCK:
		_change_state(State.IDLE)

# ----------------------------------------------------------
# 毎フレーム処理（親クラスのスタミナ回復を通すため必須）
# ----------------------------------------------------------
func _process(delta: float) -> void:
	super._process(delta)
