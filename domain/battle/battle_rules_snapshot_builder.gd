class_name BattleRulesSnapshotBuilder
extends RefCounted

const _BASIS_POINTS: int = 10000

func build(
	catalog: BattleRuleCatalog,
	inputs: BattleSetupInputs,
	act_index: int,
	encounter_kind: StringName
) -> BattleRulesSnapshotBuildResult:
	if catalog == null or inputs == null or inputs.encounter_snapshot == null \
		or act_index < 1 or act_index > 3 \
		or encounter_kind not in [&"normal", &"elite", &"boss"]:
		return BattleRulesSnapshotBuildResult.failure(
			BattleRulesSnapshotBuildError.INPUT_INVALID,
			&"inputs"
		)
	if catalog.manifest_digest_value() != String(inputs.manifest_digest):
		return BattleRulesSnapshotBuildResult.failure(
			BattleRulesSnapshotBuildError.GENERATION_MISMATCH,
			&"manifest_digest"
		)
	var config := catalog.try_combat_config_rule(&"config.combat_default")
	if config == null:
		return BattleRulesSnapshotBuildResult.failure(
			BattleRulesSnapshotBuildError.REFERENCE_MISSING,
			&"combat_config_id",
			&"config.combat_default"
		)
	var ability_pending: Array[StringName] = []
	var effect_pending: Array[StringName] = []
	for unit: UnitBattleSnapshot in inputs.player_units:
		_collect_unit_roots(unit, ability_pending, effect_pending)
	for unit: UnitBattleSnapshot in inputs.encounter_snapshot.enemy_units:
		_collect_unit_roots(unit, ability_pending, effect_pending)
	for trait_snapshot: TraitBattleSnapshot in inputs.player_active_traits:
		_collect_effect_roots(trait_snapshot.effect_assignments, effect_pending)
	for trait_snapshot: TraitBattleSnapshot in inputs.encounter_snapshot.active_traits:
		_collect_effect_roots(trait_snapshot.effect_assignments, effect_pending)
	_collect_effect_roots(inputs.player_equipment_effects, effect_pending)
	_collect_effect_roots(inputs.player_relic_effects, effect_pending)
	_collect_effect_roots(inputs.commander_effects, effect_pending)
	_collect_effect_roots(inputs.challenge_modifiers, effect_pending)
	_collect_effect_roots(inputs.encounter_snapshot.affix_effects, effect_pending)
	for phase: BossPhaseSnapshot in inputs.encounter_snapshot.boss_phases:
		for effect_id: StringName in phase.effect_ids: effect_pending.append(effect_id)
	var seen_abilities: Dictionary = {}
	var seen_effects: Dictionary = {}
	var seen_summons: Dictionary = {}
	var ability_rules: Array[BattleAbilityRuleSnapshot] = []
	var effect_rules: Array[BattleEffectRuleSnapshot] = []
	var templates: Array[SummonedUnitRuleSnapshot] = []
	while not ability_pending.is_empty() or not effect_pending.is_empty():
		ability_pending.sort_custom(_name_less)
		effect_pending.sort_custom(_name_less)
		if not ability_pending.is_empty():
			var ability_id: StringName = ability_pending.pop_front()
			if seen_abilities.has(ability_id): continue
			seen_abilities[ability_id] = true
			var ability := catalog.try_ability_rule(ability_id)
			if ability == null:
				return _missing(&"ability_rules", ability_id)
			if _has_duplicates(ability.effect_ids):
				return BattleRulesSnapshotBuildResult.failure(
					BattleRulesSnapshotBuildError.DUPLICATE_ASSIGNMENT,
					&"ability.effect_ids",
					ability_id
				)
			var ability_snapshot := BattleAbilityRuleSnapshot.new()
			ability_snapshot.ability_id = ability.ability_id
			ability_snapshot.target_rule = ability.target_rule
			ability_snapshot.cast_ticks = ability.cast_ticks
			ability_snapshot.effect_ids = ability.effect_ids.duplicate()
			ability_rules.append(ability_snapshot)
			for effect_id: StringName in ability.effect_ids: effect_pending.append(effect_id)
			continue
		var effect_id: StringName = effect_pending.pop_front()
		if seen_effects.has(effect_id): continue
		seen_effects[effect_id] = true
		var effect := catalog.try_effect_rule(effect_id)
		if effect == null:
			return _missing(&"effect_rules", effect_id)
		effect_rules.append(_effect_snapshot(effect))
		for operation: BattleOperationRule in effect.battle_operations:
			if operation.status_id != null:
				effect_pending.append(operation.status_id.value)
			if operation.kind != &"summon" or operation.unit_id == null:
				continue
			var summoned_id: StringName = operation.unit_id.value
			if seen_summons.has(summoned_id): continue
			seen_summons[summoned_id] = true
			if seen_summons.size() > config.entity_budget:
				return BattleRulesSnapshotBuildResult.failure(
					BattleRulesSnapshotBuildError.CLOSURE_LIMIT,
					&"summoned_unit_templates",
					summoned_id
				)
			var unit := catalog.try_unit_rule(summoned_id)
			if unit == null:
				return _missing(&"summoned_unit_templates", summoned_id)
			var template_result := _summoned_template(unit)
			if not template_result.ok:
				return template_result
			templates.append(template_result.snapshot.summoned_unit_templates[0])
			if unit.ability_id != null: ability_pending.append(unit.ability_id.value)
			for direct_effect: StringName in unit.effect_ids: effect_pending.append(direct_effect)
	ability_rules.sort_custom(_ability_less)
	effect_rules.sort_custom(_effect_less)
	templates.sort_custom(_template_less)
	var result := _snapshot_from_config(config)
	result.act_index = act_index
	result.encounter_kind = encounter_kind
	result.ability_rules = ability_rules
	result.effect_rules = effect_rules
	result.summoned_unit_templates = templates
	return BattleRulesSnapshotBuildResult.success(result)

func _summoned_template(unit: BattleUnitRule) -> BattleRulesSnapshotBuildResult:
	var scaling: BattleStarScalingRule = null
	for candidate: BattleStarScalingRule in unit.star_scalings:
		if candidate.star == 1: scaling = candidate
	if scaling == null or unit.base_stats == null:
		return _missing(&"summoned_unit_templates.star_scaling", unit.unit_id)
	var template := SummonedUnitRuleSnapshot.new()
	template.unit_id = unit.unit_id
	template.star = 1
	template.trait_ids = unit.trait_ids.duplicate()
	template.health = _scaled(unit.base_stats.health, scaling.health_bps)
	template.attack = _scaled(unit.base_stats.attack, scaling.attack_bps)
	template.armor = _scaled(unit.base_stats.armor, scaling.armor_bps)
	template.magic_resist = _scaled(unit.base_stats.magic_resist, scaling.magic_resist_bps)
	template.attack_speed_milli = _scaled(unit.base_stats.attack_speed_milli, scaling.attack_speed_bps)
	template.attack_range_cells = _scaled(unit.base_stats.attack_range_cells, scaling.attack_range_bps)
	template.start_mana = _scaled(unit.base_stats.start_mana, scaling.start_mana_bps)
	template.max_mana = _scaled(unit.base_stats.max_mana, scaling.max_mana_bps)
	template.move_speed_milli = _scaled(unit.base_stats.move_speed_milli, scaling.move_speed_bps)
	if template.health < 1 or template.max_mana < template.start_mana:
		return BattleRulesSnapshotBuildResult.failure(
			BattleRulesSnapshotBuildError.INTEGER_OVERFLOW,
			&"summoned_unit_templates.stats",
			unit.unit_id
		)
	template.ability_id = unit.ability_id.deep_clone() if unit.ability_id != null else null
	template.ai_profile = unit.ai_profile
	template.basic_attack_profile = unit.basic_attack_profile
	for effect_index: int in range(unit.effect_ids.size()):
		var assignment := UnitEffectAssignmentSnapshot.new()
		assignment.priority = 0
		assignment.source_stable_id = unit.unit_id
		assignment.effect_index = effect_index
		assignment.effect_id = unit.effect_ids[effect_index]
		template.unit_effect_assignments.append(assignment)
	var wrapper := BattleRulesSnapshot.new()
	wrapper.summoned_unit_templates = [template]
	return BattleRulesSnapshotBuildResult.success(wrapper)

func _snapshot_from_config(config: BattleCombatConfigRule) -> BattleRulesSnapshot:
	var result := BattleRulesSnapshot.new()
	result.simulation_version = config.simulation_version
	result.event_codec_version = 1
	result.result_codec_version = 1
	result.combat_config_id = config.config_id
	for property: StringName in BattleCombatConfigRule._integer_properties():
		if property == &"simulation_version": continue
		result.set(property, config.get(property))
	return result

func _effect_snapshot(effect: BattleEffectRule) -> BattleEffectRuleSnapshot:
	var result := BattleEffectRuleSnapshot.new()
	result.effect_id = effect.effect_id
	result.trigger = effect.trigger
	result.periodic_interval_ticks = effect.periodic_interval_ticks
	for condition: BattleConditionRule in effect.conditions:
		result.conditions.append(condition.deep_clone())
	for operation: BattleOperationRule in effect.battle_operations:
		result.battle_operations.append(operation.deep_clone())
	for operation: BattleRunOperationRule in effect.run_operations:
		result.run_operations.append(operation.deep_clone())
	result.stacking = effect.stacking
	result.max_stacks = effect.max_stacks
	result.duration_ticks = effect.duration_ticks
	return result

func _scaled(value: int, basis_points: int) -> int:
	if value > 2147483647 or value < -2147483648 \
		or basis_points < 0 or basis_points > 100000:
		return -2147483648
	var product: int = value * basis_points
	var scaled: int = product / _BASIS_POINTS
	if scaled > 2147483647 or scaled < -2147483648:
		return -2147483648
	return scaled

func _collect_unit_roots(
	unit: UnitBattleSnapshot,
	ability_ids: Array[StringName],
	effect_ids: Array[StringName]
) -> void:
	if unit.ability_id != null: ability_ids.append(unit.ability_id.value)
	for effect_id: StringName in unit.effect_ids: effect_ids.append(effect_id)
	_collect_effect_roots(unit.effect_assignments, effect_ids)

func _collect_effect_roots(
	assignments: Array[BattleEffectSnapshot],
	effect_ids: Array[StringName]
) -> void:
	for assignment: BattleEffectSnapshot in assignments:
		effect_ids.append(assignment.effect_id)

func _has_duplicates(values: Array[StringName]) -> bool:
	var seen: Dictionary = {}
	for value: StringName in values:
		if seen.has(value): return true
		seen[value] = true
	return false

func _missing(path: StringName, source: StringName) -> BattleRulesSnapshotBuildResult:
	return BattleRulesSnapshotBuildResult.failure(
		BattleRulesSnapshotBuildError.REFERENCE_MISSING,
		path,
		source
	)

func _name_less(left: StringName, right: StringName) -> bool:
	return String(left) < String(right)

func _ability_less(left: BattleAbilityRuleSnapshot, right: BattleAbilityRuleSnapshot) -> bool:
	return String(left.ability_id) < String(right.ability_id)

func _effect_less(left: BattleEffectRuleSnapshot, right: BattleEffectRuleSnapshot) -> bool:
	return String(left.effect_id) < String(right.effect_id)

func _template_less(left: SummonedUnitRuleSnapshot, right: SummonedUnitRuleSnapshot) -> bool:
	return String(left.unit_id) < String(right.unit_id)
