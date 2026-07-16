class_name BattleCombatMath
extends RefCounted

const MAX_I32: int = 2147483647
const MIN_I32: int = -2147483648

static func threshold(rules: BattleRulesSnapshot) -> int:
	return rules.tick_rate * rules.progress_scale

static func initial_progress(speed: int, rules: BattleRulesSnapshot) -> int:
	return 0 if speed <= 0 else maxi(0, threshold(rules) - speed)

static func advance_progress(current: int, speed: int, rules: BattleRulesSnapshot) -> int:
	if speed <= 0:
		return current
	return mini(2 * threshold(rules), current + speed)

static func post_resistance(
	raw: int,
	resistance: int,
	damage_type: StringName,
	rules: BattleRulesSnapshot
) -> int:
	if raw <= 0:
		return 0
	if damage_type == &"true":
		return raw
	var multiplier := 0
	if resistance >= 0:
		multiplier = 1000000 / (rules.resistance_base + resistance)
	else:
		multiplier = 20000 - 1000000 / (rules.resistance_base - resistance)
	return maxi(1, raw * multiplier / rules.basis_points)

static func overtime_damage(
	max_health: int,
	overtime_index: int,
	rules: BattleRulesSnapshot
) -> int:
	var bps := mini(rules.overtime_step_bps * overtime_index, rules.overtime_cap_bps)
	return ceil_div(max_health * bps, rules.basis_points)

static func damage_mana(
	actual_damage: int,
	max_health: int,
	rules: BattleRulesSnapshot
) -> int:
	if actual_damage <= 0 or max_health <= 0:
		return 0
	return clampi(
		ceil_div(actual_damage * rules.damage_mana_factor, max_health),
		rules.damage_mana_min,
		rules.damage_mana_max
	)

static func recompute_effective_stats(
	entity: BattleEntityState,
	rules: BattleRulesSnapshot
) -> void:
	var ordered: Array[BattleTimedState] = []
	for modifier: BattleTimedState in entity.modifiers:
		ordered.append(modifier)
	ordered.sort_custom(_modifier_precedes)
	entity.attack = _effective(entity.base_attack, &"attack", ordered, rules, true)
	entity.armor = _effective(entity.base_armor, &"armor", ordered, rules, false)
	entity.magic_resist = _effective(entity.base_magic_resist, &"magic_resist", ordered, rules, false)
	entity.attack_speed_milli = _effective(
		entity.base_attack_speed_milli, &"attack_speed_milli", ordered, rules, true
	)
	entity.move_speed_milli = _effective(
		entity.base_move_speed_milli, &"move_speed_milli", ordered, rules, true
	)

static func ceil_div(numerator: int, denominator: int) -> int:
	if numerator <= 0:
		return 0
	return (numerator + denominator - 1) / denominator

static func _effective(
	base: int,
	stat: StringName,
	modifiers: Array[BattleTimedState],
	rules: BattleRulesSnapshot,
	nonnegative: bool
) -> int:
	var add_total := 0
	var multiplier := rules.basis_points
	for modifier: BattleTimedState in modifiers:
		if modifier.stat != stat:
			continue
		if modifier.mode == &"add":
			add_total += modifier.amount
		elif modifier.mode == &"multiply_bps":
			multiplier += modifier.amount - rules.basis_points
	multiplier = clampi(multiplier, 0, 100000)
	var value := (base + add_total) * multiplier / rules.basis_points
	if nonnegative:
		return clampi(value, 0, MAX_I32)
	return clampi(value, MIN_I32, MAX_I32)

static func _modifier_precedes(left: BattleTimedState, right: BattleTimedState) -> bool:
	if left.state_id != right.state_id:
		return String(left.state_id) < String(right.state_id)
	var left_source := "" if left.source_instance_id == null else String(left.source_instance_id.value)
	var right_source := "" if right.source_instance_id == null else String(right.source_instance_id.value)
	if left_source != right_source:
		return left_source < right_source
	if left.operation_index != right.operation_index:
		return left.operation_index < right.operation_index
	return left.applied_sequence < right.applied_sequence
