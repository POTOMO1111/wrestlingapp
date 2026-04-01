extends CharacterBody3D

# ============================================================
#  CharacterBase.gd
#  Player・CPU 共通の体力・ダメージ処理。
#  player.tscn と cpu_opponent.tscn の両方のルートにアタッチする。
#  PlayerController.gd はこのスクリプトを継承して使う。
# ============================================================

@export var max_hp      : int = 100
@export var max_stamina : float = 100.0
@export var player_id   : int = 1   # 1 か 2

var current_hp      : int = max_hp
var current_stamina : float = max_stamina
var is_dead         : bool = false
var is_stamina_regen_active : bool = true

## 体力・スタミナ変化シグナル（HUDが受け取る）
signal hp_changed(player_id, current_hp, max_hp)
signal stamina_changed(player_id, current_stamina, max_stamina)
signal died(player_id)

func _ready() -> void:
	current_hp = max_hp
	current_stamina = max_stamina
	add_to_group("fighter")
	
	# GameManager へ自身を登録（UI連携用）
	if Engine.has_singleton("GameManager") or get_tree().root.has_node("GameManager"):
		var gm = get_node("/root/GameManager")
		if gm.has_method("register_fighter"):
			gm.register_fighter(self)

func _process(delta: float) -> void:
	if is_dead: return
	
	if is_stamina_regen_active:
		# スタミナ自然回復 (1秒間に15回復)
		if current_stamina < max_stamina:
			current_stamina = min(max_stamina, current_stamina + 15.0 * delta)
			stamina_changed.emit(player_id, current_stamina, max_stamina)

# ----------------------------------------------------------
# スタミナ消費
# ----------------------------------------------------------
func consume_stamina(amount: float) -> bool:
	if current_stamina >= amount:
		current_stamina -= amount
		stamina_changed.emit(player_id, current_stamina, max_stamina)
		return true
	return false

# ----------------------------------------------------------
# ダメージ受け取り（HitboxController から呼ばれる）
# ----------------------------------------------------------
func take_damage(amount: int, knockback_dir: Vector3 = Vector3.ZERO) -> void:
	if is_dead:
		return

	current_hp = max(0, current_hp - amount)
	hp_changed.emit(player_id, current_hp, max_hp)

	# ノックバック
	if knockback_dir != Vector3.ZERO:
		velocity += knockback_dir

	# ダウン演出
	if current_hp <= 0:
		_on_death()
		return

	# 被弾アニメーション（PlayerController.gd 側で上書き可）
	_on_hit()

# ----------------------------------------------------------
# 被弾時の処理（サブクラスで override 可）
# ----------------------------------------------------------
func _on_hit() -> void:
	pass

# ----------------------------------------------------------
# 死亡時の処理
# ----------------------------------------------------------
func _on_death() -> void:
	is_dead = true
	died.emit(player_id)
	# GameManager に通知
	if Engine.has_singleton("GameManager") or get_tree().root.has_node("GameManager"):
		get_node("/root/GameManager").on_fighter_down(player_id)