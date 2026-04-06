class_name SpatialAwareness
extends Node

# ============================================================
#  SpatialAwareness.gd
#  AI用の空間認識コンポーネント。
#  距離計算・リングゾーン判定を毎フレーム更新し、
#  AIBrain や MoveSelector がポーリングで参照する。
# ============================================================

# --- 外部参照（AIBrain.initialize() で代入） ---
var owner_body: CharacterBody3D
var opponent_body: CharacterBody3D

# --- 公開プロパティ（毎フレーム更新） ---
var distance_to_opponent: float = 999.0
var direction_to_opponent: Vector3 = Vector3.ZERO
var is_opponent_in_strike_range: bool = false
var is_opponent_in_grapple_range: bool = false
var is_near_ropes: bool = false
var is_in_corner: bool = false
var is_opponent_near_ropes: bool = false
var is_opponent_in_corner: bool = false
var ring_center_distance: float = 0.0
var opponent_facing_us: bool = false

# --- 定数 ---
const STRIKE_RANGE: float = 2.0
const GRAPPLE_RANGE: float = 1.2
const ROPE_DISTANCE: float = 1.5   # リング端から何m以内で「ロープ際」判定
const CORNER_DISTANCE: float = 2.0 # コーナーから何m以内で「コーナー」判定
const RING_CENTER: Vector3 = Vector3.ZERO
const RING_HALF_SIZE: float = 6.0  # リングの半径（正方形想定）

func _physics_process(_delta: float) -> void:
	if not owner_body or not opponent_body:
		return
	_update_distances()
	_update_ring_zones()
	_update_opponent_facing()

func _update_distances() -> void:
	var diff := opponent_body.global_position - owner_body.global_position
	diff.y = 0.0
	distance_to_opponent = diff.length()
	direction_to_opponent = diff.normalized() if distance_to_opponent > 0.01 else Vector3.ZERO
	is_opponent_in_strike_range = distance_to_opponent <= STRIKE_RANGE
	is_opponent_in_grapple_range = distance_to_opponent <= GRAPPLE_RANGE

func _update_ring_zones() -> void:
	var own_pos := owner_body.global_position
	var opp_pos := opponent_body.global_position
	ring_center_distance = Vector2(own_pos.x, own_pos.z).length()

	var own_edge_dist := RING_HALF_SIZE - maxf(absf(own_pos.x), absf(own_pos.z))
	is_near_ropes = own_edge_dist < ROPE_DISTANCE

	var opp_edge_dist := RING_HALF_SIZE - maxf(absf(opp_pos.x), absf(opp_pos.z))
	is_opponent_near_ropes = opp_edge_dist < ROPE_DISTANCE

	is_in_corner = _is_near_any_corner(own_pos)
	is_opponent_in_corner = _is_near_any_corner(opp_pos)

func _is_near_any_corner(pos: Vector3) -> bool:
	var hs := RING_HALF_SIZE
	for corner in [Vector3(hs, 0, hs), Vector3(hs, 0, -hs), Vector3(-hs, 0, hs), Vector3(-hs, 0, -hs)]:
		if pos.distance_to(corner) < CORNER_DISTANCE:
			return true
	return false

func _update_opponent_facing() -> void:
	var opp_forward := -opponent_body.global_transform.basis.z
	var to_us := (owner_body.global_position - opponent_body.global_position).normalized()
	opponent_facing_us = opp_forward.dot(to_us) > 0.3
