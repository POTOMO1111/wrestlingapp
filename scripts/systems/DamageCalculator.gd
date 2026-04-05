class_name DamageCalculator
extends RefCounted

# ============================================================
#  DamageCalculator.gd
#  静的クラス。AttackData + HitResult + 両者の CharacterStats から
#  ダメージを計算して返す。
# ============================================================

## 打撃ダメージ計算
## 戻り値: { "recoverable": float, "permanent": float }
static func calculate_attack_damage(
	attack: AttackData,
	result: GameEnums.HitResult,
	attacker_stats: CharacterStats,
	defender_stats: CharacterStats
) -> Dictionary:

	var rec_dmg: float = attack.recoverable_damage
	var perm_dmg: float = attack.permanent_damage

	# 攻撃者のステータス倍率
	match attack.action_type:
		GameEnums.ActionType.PUNCH:
			rec_dmg *= attacker_stats.punch_damage_multiplier
		GameEnums.ActionType.KICK:
			rec_dmg *= attacker_stats.kick_damage_multiplier

	# カウンターヒット倍率
	if result == GameEnums.HitResult.COUNTER_HIT:
		rec_dmg  *= attack.counter_hit_multiplier
		perm_dmg *= attack.counter_hit_multiplier

	# ガード時はダメージなし（ブロックスタンのみ）
	if result == GameEnums.HitResult.BLOCKED:
		return {"recoverable": 0.0, "permanent": 0.0}

	# 防御者のステータス倍率
	rec_dmg  *= defender_stats.defense_multiplier
	perm_dmg *= defender_stats.defense_multiplier

	return {"recoverable": rec_dmg, "permanent": perm_dmg}

## グラップルダメージ計算
static func calculate_grapple_damage(
	grapple: GrappleData,
	dominance: float,
	attacker_stats: CharacterStats,
	defender_stats: CharacterStats
) -> Dictionary:

	var perm_dmg: float = grapple.permanent_damage
	var rec_dmg: float  = grapple.recoverable_damage

	perm_dmg *= attacker_stats.grapple_damage_multiplier

	# dominance が閾値以上の場合のみ倍率適用
	if dominance >= grapple.dominance_damage_threshold:
		perm_dmg *= grapple.dominant_damage_multiplier

	perm_dmg *= defender_stats.defense_multiplier
	rec_dmg  *= defender_stats.defense_multiplier

	return {"recoverable": rec_dmg, "permanent": perm_dmg}
