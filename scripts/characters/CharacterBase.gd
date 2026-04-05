extends CharacterBody3D

# ============================================================
#  CharacterBase.gd
#  Player・CPU 共通の移動・物理基盤。
#  HP/ダメージ管理は CombatController/HealthComponent が担当する。
# ============================================================

@export var player_id : int = 1   # 1 か 2

# 旧システム互換: CombatController の KO 状態を参照する
var is_dead: bool:
	get:
		var ctrl = get_node_or_null("CombatController")
		if ctrl and ctrl.has_method("get_current_state"):
			return ctrl.get_current_state() == GameEnums.CharacterState.KO
		return false

var is_stamina_regen_active : bool = true

func _ready() -> void:
	add_to_group("fighter")
	collision_layer = 1
	collision_mask  = 1

func _process(_delta: float) -> void:
	pass

# ----------------------------------------------------------
# スタミナ消費（旧互換ラッパー → 新HealthComponent に委譲）
# ----------------------------------------------------------
func consume_stamina(amount: float) -> bool:
	var hc: HealthComponent = get_node_or_null("CombatController/HealthComponent")
	if hc:
		return hc.consume_stamina(amount)
	return false

# ----------------------------------------------------------
# ノックバック（サブクラスで override 可）
# ----------------------------------------------------------
func _apply_knockback(knockback_dir: Vector3) -> void:
	velocity += knockback_dir

# ----------------------------------------------------------
# 旧互換: take_damage は新システム（HealthComponent）が処理するため何もしない
# ----------------------------------------------------------
func take_damage(_amount: int, _knockback_dir: Vector3 = Vector3.ZERO) -> void:
	pass
