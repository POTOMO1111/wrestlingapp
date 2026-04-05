class_name HitboxManager
extends Node3D

# ============================================================
#  HitboxManager.gd
#  キャラクターの子ノードとしてアタッチ。
#  攻撃ヒットボックスの有効/無効化とヒット判定を管理する。
#
#  子ノード構成:
#    Hitbox  (Area3D) - 自分の攻撃判定（攻撃中のみ有効）
#      CollisionShape3D
#    Hurtbox (Area3D) - 相手の攻撃を受ける判定（常時有効）
#      CollisionShape3D
# ============================================================

@onready var hitbox:        Area3D           = $Hitbox
@onready var hurtbox:       Area3D           = $Hurtbox
@onready var hitbox_shape:  CollisionShape3D = $Hitbox/CollisionShape3D
@onready var hurtbox_shape: CollisionShape3D = $Hurtbox/CollisionShape3D

var _active_attack:  AttackData  = null
var _active_grapple: GrappleData = null
var _hit_targets: Array = []  # 同一モーションでの多段ヒット防止

signal hit_landed(target: Node, attack_data: AttackData, result: GameEnums.HitResult)
signal grapple_initiated(target: Node, grapple_data: GrappleData)

func _ready() -> void:
	# Hitbox は初期状態で無効、Hurtbox は常時検知される側
	hitbox.monitoring   = false
	hitbox.monitorable  = false
	hitbox.collision_layer = 8   # Layer 4 (hitbox)
	hitbox.collision_mask  = 16  # Layer 5 (hurtbox)

	hurtbox.monitoring   = false
	hurtbox.monitorable  = true
	hurtbox.collision_layer = 16  # Layer 5 (hurtbox)
	hurtbox.collision_mask  = 0

	hitbox.area_entered.connect(_on_hitbox_area_entered)

	# Hurtbox の CollisionShape をカプセルに設定
	var capsule = CapsuleShape3D.new()
	capsule.radius = 0.4
	capsule.height = 1.6
	hurtbox_shape.shape    = capsule
	hurtbox_shape.position = Vector3(0, 1.0, 0)

## 打撃判定を有効化（CombatController の StateAttacking から呼ぶ）
func activate_hitbox(attack: AttackData) -> void:
	_active_attack  = attack
	_active_grapple = null
	_hit_targets.clear()

	var box = BoxShape3D.new()
	box.size = attack.hitbox_size
	hitbox_shape.shape    = box
	hitbox_shape.position = attack.hitbox_offset
	hitbox.monitoring = true
	if GameManager.debug_mode:
		print("[HitboxManager:%s] activate_hitbox size=%s offset=%s global_pos=%s" % [
			_owner_name(), str(attack.hitbox_size), str(attack.hitbox_offset), str(hitbox.global_position)
		])
	# Godot4: monitoring 有効化時点で既に重なっている Area は area_entered を発火しない
	# → 手動でチェックして同じハンドラを呼ぶ
	for area in hitbox.get_overlapping_areas():
		_on_hitbox_area_entered(area)

## グラップル判定を有効化
func activate_grapple_hitbox(grapple: GrappleData) -> void:
	_active_grapple = grapple
	_active_attack  = null
	_hit_targets.clear()

	var box = BoxShape3D.new()
	box.size = grapple.hitbox_size
	hitbox_shape.shape    = box
	hitbox_shape.position = grapple.hitbox_offset
	hitbox.monitoring = true
	for area in hitbox.get_overlapping_areas():
		_on_hitbox_area_entered(area)

## 攻撃判定を無効化
func deactivate_hitbox() -> void:
	hitbox.monitoring = false
	_active_attack    = null
	_active_grapple   = null
	_hit_targets.clear()

# ----------------------------------------------------------
# 内部 - ヒット判定
# ----------------------------------------------------------

func _on_hitbox_area_entered(area: Area3D) -> void:
	if GameManager.debug_mode:
		print("[HitboxManager:%s] area_entered: %s  in_hurtbox=%s" % [
			_owner_name(), area.get_path(), area.is_in_group("hurtbox")
		])
	if not area.is_in_group("hurtbox"):
		return

	# CharacterBody3D の祖先を遡って取得（新旧どちらの Hurtbox 配置にも対応）
	var target_character: Node = area.get_parent()
	while target_character != null and not target_character is CharacterBody3D:
		target_character = target_character.get_parent()

	if target_character == null:
		if GameManager.debug_mode:
			print("[HitboxManager:%s] target CharacterBody3D not found from %s" % [_owner_name(), area.get_path()])
		return

	# 自分自身への当たり防止
	var self_character: Node = get_parent()
	while self_character != null and not self_character is CharacterBody3D:
		self_character = self_character.get_parent()
	if target_character == self_character:
		return

	if target_character in _hit_targets:
		return  # 多段ヒット防止
	_hit_targets.append(target_character)

	if GameManager.debug_mode:
		print("[HitboxManager:%s] HIT DETECTED → target=%s" % [_owner_name(), target_character.name])

	if _active_attack != null:
		var result = _calculate_hit_result(target_character, _active_attack.action_type)
		hit_landed.emit(target_character, _active_attack, result)
		deactivate_hitbox()

	elif _active_grapple != null:
		grapple_initiated.emit(target_character, _active_grapple)
		deactivate_hitbox()

func _calculate_hit_result(target: Node, action_type: GameEnums.ActionType) -> GameEnums.HitResult:
	var combat_ctrl = target.get_node_or_null("CombatController")
	if combat_ctrl == null:
		return GameEnums.HitResult.HIT

	var target_state: GameEnums.CharacterState = combat_ctrl.get_current_state()

	# ガード判定（三すくみ）
	if target_state == GameEnums.CharacterState.GUARDING:
		if action_type == GameEnums.ActionType.GRAPPLE:
			return GameEnums.HitResult.GRAPPLE_SUCCESS  # グラップルはガード貫通
		else:
			return GameEnums.HitResult.BLOCKED

	# カウンターヒット（相手が攻撃 or ヒットスタン or 行動不可中）
	if target_state in [
		GameEnums.CharacterState.ATTACKING,
		GameEnums.CharacterState.HIT_STUN,
		GameEnums.CharacterState.INCAPACITATED
	]:
		return GameEnums.HitResult.COUNTER_HIT

	return GameEnums.HitResult.HIT

func _owner_name() -> String:
	# HitboxManager → CombatController → Character の名前を返す
	var p = get_parent()
	if p and p.get_parent():
		return p.get_parent().name
	return "?"
