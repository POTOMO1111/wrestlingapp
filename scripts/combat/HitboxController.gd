extends Area3D

# ============================================================
#  HitboxController.gd
#  攻撃側のヒットボックス。相手のHurtBoxに触れたとき
#  hit_connected シグナルを発火する。
#  player.tscn の HitboxRight（Area3D）にアタッチする。
# ============================================================

## 攻撃の種類
enum AttackType { LIGHT, HEAVY, GRAPPLE }

@export var attack_type : AttackType = AttackType.LIGHT
@export var damage      : int = 10
@export var knockback_force : float = 5.0

## ヒット時に発火するシグナル
signal hit_connected(target, damage, knockback_dir)
signal grapple_connected(target)

# 同一攻撃モーションで複数回ヒットしないようにするセット
var _hit_targets : Array = []
var _debug_mesh : MeshInstance3D = null

func _ready() -> void:
	# HurtBox レイヤー（Layer 5）とだけ重なるよう設定
	# ※ インスペクターで設定してもOK
	monitoring = false
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)
	_setup_debug_mesh()

# ----------------------------------------------------------
# 可視化エフェクト（アニメーションが無い間の措置）
# ----------------------------------------------------------
func _setup_debug_mesh() -> void:
	var shape_node : CollisionShape3D = null
	for child in get_children():
		if child is CollisionShape3D:
			shape_node = child
			break
			
	if shape_node and shape_node.shape:
		_debug_mesh = MeshInstance3D.new()
		var mat = StandardMaterial3D.new()
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(1.0, 0.0, 0.0, 0.5)
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		
		if shape_node.shape is BoxShape3D:
			var box = BoxMesh.new()
			box.size = shape_node.shape.size
			_debug_mesh.mesh = box
		elif shape_node.shape is SphereShape3D:
			var sphere = SphereMesh.new()
			sphere.radius = shape_node.shape.radius
			sphere.height = shape_node.shape.radius * 2
			_debug_mesh.mesh = sphere
			
		_debug_mesh.material_override = mat
		_debug_mesh.transform = shape_node.transform
		_debug_mesh.visible = false
		add_child(_debug_mesh)

# ----------------------------------------------------------
# 攻撃開始時に外部から呼ぶ（PlayerController.gd から）
# ----------------------------------------------------------
func activate() -> void:
	_hit_targets.clear()
	monitoring = true
	
	if _debug_mesh:
		_debug_mesh.visible = true
		var mat = _debug_mesh.material_override as StandardMaterial3D
		if attack_type == AttackType.LIGHT:
			mat.albedo_color = Color(0.2, 0.8, 1.0, 0.6) # 水色 (弱攻撃)
		elif attack_type == AttackType.HEAVY:
			mat.albedo_color = Color(1.0, 0.3, 0.0, 0.6) # オレンジ (強攻撃)
		elif attack_type == AttackType.GRAPPLE:
			mat.albedo_color = Color(0.8, 0.0, 1.0, 0.6) # 紫 (掴み)

func deactivate() -> void:
	monitoring = false
	_hit_targets.clear()
	if _debug_mesh:
		_debug_mesh.visible = false

# ----------------------------------------------------------
# Area3D（HurtBox）に触れたとき
# ----------------------------------------------------------
func _on_area_entered(area: Area3D) -> void:
	if area.is_in_group("hurtbox"):
		var target = area.get_parent()
		if target in _hit_targets:
			return
		if target == get_parent():  # 自分自身には当たらない
			return
		_hit_targets.append(target)

		var knockback_dir : Vector3 = (target.global_position - get_parent().global_position).normalized()
		knockback_dir.y = 0.3  # 少し浮かせる

		if attack_type == AttackType.GRAPPLE:
			grapple_connected.emit(target)
		else:
			hit_connected.emit(target, damage, knockback_dir * knockback_force)
			if target.has_method("take_damage"):
				target.take_damage(damage, knockback_dir * knockback_force)
				
			if attack_type == AttackType.HEAVY:
				GrappleSystem._spawn_text_effect("SMASH!", target.global_position + Vector3(0, 2.0, 0), Color.ORANGE)
			else:
				GrappleSystem._spawn_text_effect("HIT!", target.global_position + Vector3(0, 2.0, 0), Color.WHITE)

# ----------------------------------------------------------
# CharacterBody3D に直接触れたとき（念のため）
# ----------------------------------------------------------
func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("fighter") and body != get_parent():
		if body in _hit_targets:
			return
		_hit_targets.append(body)

		var knockback_dir : Vector3 = (body.global_position - get_parent().global_position).normalized()
		knockback_dir.y = 0.3

		if attack_type == AttackType.GRAPPLE:
			grapple_connected.emit(body)
		else:
			if body.has_method("take_damage"):
				body.take_damage(damage, knockback_dir * knockback_force)
				
			if attack_type == AttackType.HEAVY:
				GrappleSystem._spawn_text_effect("SMASH!", body.global_position + Vector3(0, 2.0, 0), Color.ORANGE)
			else:
				GrappleSystem._spawn_text_effect("HIT!", body.global_position + Vector3(0, 2.0, 0), Color.WHITE)