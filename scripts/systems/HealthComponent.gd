class_name HealthComponent
extends Node

# ============================================================
#  HealthComponent.gd
#  二層HP（回復可能HP + 回復不可能HP）を管理するコンポーネント。
#  キャラクターノードの子ノードとしてアタッチする。
# ============================================================

@export var stats: CharacterStats

var current_recoverable_hp: float = 0.0
var current_permanent_hp: float = 0.0

var _regen_timer: float = 0.0
var _is_incapacitated: bool = false

signal recoverable_hp_changed(new_value: float, max_value: float)
signal permanent_hp_changed(new_value: float, max_value: float)
signal recoverable_hp_depleted()
signal permanent_hp_depleted()
signal incapacitation_ended()
signal recoverable_hp_recovered(amount: float)

func _ready() -> void:
	if stats == null:
		push_error("HealthComponent: stats が未割り当てです: " + get_parent().name)
		stats = CharacterStats.new()
	reset()

func _physics_process(delta: float) -> void:
	_process_regen(delta)

# ----------------------------------------------------------
# 公開メソッド
# ----------------------------------------------------------

func reset() -> void:
	current_recoverable_hp = stats.max_recoverable_hp
	current_permanent_hp   = stats.max_permanent_hp
	_regen_timer           = 0.0
	_is_incapacitated      = false

## ダメージを受ける。DamageLayer で対象HPが変わる。
func take_damage(amount: float, layer: GameEnums.DamageLayer) -> void:
	_regen_timer = 0.0  # ダメージを受けたら回復タイマーリセット

	match layer:
		GameEnums.DamageLayer.RECOVERABLE:
			if _is_incapacitated:
				return  # 行動不可中は回復可能HPへの追加ダメージなし
			current_recoverable_hp = max(0.0, current_recoverable_hp - amount)
			recoverable_hp_changed.emit(current_recoverable_hp, stats.max_recoverable_hp)
			if current_recoverable_hp <= 0.0 and not _is_incapacitated:
				_on_recoverable_depleted()

		GameEnums.DamageLayer.PERMANENT:
			# 行動不可中は追加ダメージ倍率
			if _is_incapacitated:
				amount *= 1.3
			current_permanent_hp = max(0.0, current_permanent_hp - amount)
			permanent_hp_changed.emit(current_permanent_hp, stats.max_permanent_hp)
			if current_permanent_hp <= 0.0:
				permanent_hp_depleted.emit()

## スタミナ消費（回復可能HPから差し引く）。
## 戻り値: 消費できたか (HP不足の場合 false)
func consume_stamina(amount: float) -> bool:
	if current_recoverable_hp <= amount:
		return false
	current_recoverable_hp -= amount
	recoverable_hp_changed.emit(current_recoverable_hp, stats.max_recoverable_hp)
	return true

func is_incapacitated() -> bool:
	return _is_incapacitated

## グラップル dominance 倍率（行動不可中は低下）
func get_dominance_modifier() -> float:
	return stats.incapacitated_dominance_penalty if _is_incapacitated else 1.0

# ----------------------------------------------------------
# 内部メソッド
# ----------------------------------------------------------

func _on_recoverable_depleted() -> void:
	_is_incapacitated = true
	current_recoverable_hp = 0.0
	recoverable_hp_depleted.emit()
	get_tree().create_timer(stats.incapacitated_duration).timeout.connect(_on_incapacitation_end)

func _on_incapacitation_end() -> void:
	_is_incapacitated = false
	current_recoverable_hp = stats.max_recoverable_hp * 0.2
	recoverable_hp_changed.emit(current_recoverable_hp, stats.max_recoverable_hp)
	incapacitation_ended.emit()

func _process_regen(delta: float) -> void:
	if _is_incapacitated:
		return
	if current_recoverable_hp >= stats.max_recoverable_hp:
		return

	_regen_timer += delta
	if _regen_timer >= stats.recoverable_hp_regen_delay:
		var regen = stats.recoverable_hp_regen_rate * delta
		var old_hp = current_recoverable_hp
		current_recoverable_hp = min(stats.max_recoverable_hp, current_recoverable_hp + regen)
		if current_recoverable_hp != old_hp:
			recoverable_hp_changed.emit(current_recoverable_hp, stats.max_recoverable_hp)
			recoverable_hp_recovered.emit(current_recoverable_hp - old_hp)
