class_name BattleSetupInputsValidator
extends RefCounted

const INPUT_INVALID: StringName = &"BATTLE_INPUT_INVALID"
const PREVIEW_MISMATCH: StringName = &"BATTLE_PREVIEW_MISMATCH"
const _ABILITY_TARGETS: Array[StringName] = [&"self", &"current_target", &"nearest_enemy", &"random_enemy", &"lowest_health_ally"]
const _TRIGGERS: Array[StringName] = [&"battle_start", &"attack", &"hit", &"damaged", &"cast", &"kill", &"death", &"periodic", &"battle_end"]
const _STACKING: Array[StringName] = [&"replace", &"refresh_duration", &"add_stacks", &"independent"]
const _OPERATION_TARGETS: Array[StringName] = [&"self", &"target", &"all_allies", &"all_enemies"]

var _stable_ids := StableIdValidator.new()
static var _trusted_authority: BattleSetupValidationAuthority = \
	BattleSetupValidationAuthority.new()

func validate_for_build(inputs: BattleSetupInputs) -> BattleInputValidationResult:
	var validation := validate(inputs)
	if not validation.ok:
		return validation
	var encoded := _codec_for_schema(inputs.setup_schema_version).encode(inputs)
	if not encoded.ok:
		return BattleInputValidationResult.failure(
			encoded.error.code,
			encoded.error.field_path
		)
	var digest := _sha256_hex(encoded.canonical_bytes)
	if digest.is_empty():
		return BattleInputValidationResult.failure(INPUT_INVALID, &"sha256")
	var receipt := _trusted_authority._issue_validated(StringName(digest))
	if receipt == null:
		return BattleInputValidationResult.failure(
			INPUT_INVALID,
			&"validation_receipt"
		)
	return BattleInputValidationResult.success(receipt)

static func _verifies_receipt(
	receipt: BattleSetupValidationReceipt,
	expected_digest: StringName
) -> bool:
	return _trusted_authority._verifies(receipt, expected_digest)

static func _sha256_hex(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	if context.update(bytes) != OK:
		return ""
	return context.finish().hex_encode()

static func _codec_for_schema(schema_version: int) -> CanonicalBattleCodecV1:
	return CanonicalBattleCodecV2.new() if schema_version == 2 else CanonicalBattleCodecV1.new()

func validate(inputs: BattleSetupInputs) -> BattleInputValidationResult:
	if inputs == null:
		return BattleInputValidationResult.failure(INPUT_INVALID, &"inputs")
	if inputs.setup_schema_version not in [1, 2]:
		return BattleInputValidationResult.failure(INPUT_INVALID, &"setup_schema_version")
	if inputs.content_version.is_empty() or not _ascii_nonempty(inputs.content_version):
		return BattleInputValidationResult.failure(INPUT_INVALID, &"content_version")
	if not _digest(inputs.manifest_digest):
		return BattleInputValidationResult.failure(INPUT_INVALID, &"manifest_digest")
	if inputs.encounter_snapshot == null:
		return BattleInputValidationResult.failure(INPUT_INVALID, &"encounter_snapshot")
	var encounter_result := _validate_encounter(
		inputs.encounter_snapshot,
		inputs.manifest_digest,
		inputs.setup_schema_version
	)
	if not encounter_result.ok:
		return encounter_result
	var units_result := _validate_units(
		inputs.player_units, &"player_units", &"player", inputs.setup_schema_version
	)
	if not units_result.ok:
		return units_result
	var trait_result := _validate_traits(
		inputs.player_active_traits,
		&"player_active_traits",
		&"player",
		inputs.setup_schema_version
	)
	if not trait_result.ok:
		return trait_result
	var effect_result := _validate_effects(
		inputs.player_equipment_effects,
		&"player_equipment_effects",
		inputs.setup_schema_version
	)
	if not effect_result.ok:
		return effect_result
	effect_result = _validate_effects(
		inputs.player_relic_effects,
		&"player_relic_effects",
		inputs.setup_schema_version
	)
	if not effect_result.ok:
		return effect_result
	effect_result = _validate_effects(
		inputs.commander_effects, &"commander_effects", inputs.setup_schema_version
	)
	if not effect_result.ok:
		return effect_result
	effect_result = _validate_effects(
		inputs.challenge_modifiers,
		&"challenge_modifiers",
		inputs.setup_schema_version
	)
	if not effect_result.ok:
		return effect_result
	if inputs.battle_rules == null:
		return BattleInputValidationResult.failure(INPUT_INVALID, &"battle_rules")
	var rules_result := _validate_rules(inputs.battle_rules, inputs.setup_schema_version)
	if not rules_result.ok:
		return rules_result
	var all_instances: Array[StringName] = []
	for unit: UnitBattleSnapshot in inputs.player_units:
		all_instances.append(unit.instance_id)
	for unit: UnitBattleSnapshot in inputs.encounter_snapshot.enemy_units:
		if all_instances.has(unit.instance_id):
			return BattleInputValidationResult.failure(INPUT_INVALID, &"encounter_snapshot.enemy_units.instance_id")
		all_instances.append(unit.instance_id)
	if inputs.setup_schema_version == 2:
		var source_result := _validate_v2_source_graph(inputs)
		if not source_result.ok:
			return source_result
		var reference_result := _validate_rule_references(inputs)
		if not reference_result.ok:
			return reference_result
	return BattleInputValidationResult.success()

func _validate_encounter(
	preview: EncounterPreviewSnapshot,
	expected_digest: StringName,
	setup_schema_version: int
) -> BattleInputValidationResult:
	if preview.preview_schema_version != 1:
		return BattleInputValidationResult.failure(INPUT_INVALID, &"encounter_snapshot.preview_schema_version")
	if not _stable_ids.is_valid(preview.encounter_id):
		return BattleInputValidationResult.failure(INPUT_INVALID, &"encounter_snapshot.encounter_id")
	if preview.manifest_digest != expected_digest:
		return BattleInputValidationResult.failure(PREVIEW_MISMATCH, &"encounter_snapshot.manifest_digest")
	var units_result := _validate_units(
		preview.enemy_units,
		&"encounter_snapshot.enemy_units",
		&"enemy",
		setup_schema_version
	)
	if not units_result.ok:
		return units_result
	var traits_result := _validate_traits(
		preview.active_traits,
		&"encounter_snapshot.active_traits",
		&"enemy",
		setup_schema_version
	)
	if not traits_result.ok:
		return traits_result
	var effects_result := _validate_effects(
		preview.affix_effects,
		&"encounter_snapshot.affix_effects",
		setup_schema_version
	)
	if not effects_result.ok:
		return effects_result
	var previous_phase := -1
	for index: int in range(preview.boss_phases.size()):
		var phase := preview.boss_phases[index]
		if phase == null or not _nonnegative_i32(phase.phase_index) or phase.phase_index <= previous_phase or phase.hp_threshold_bps < 0 or phase.hp_threshold_bps > 10000:
			return BattleInputValidationResult.failure(INPUT_INVALID, StringName("encounter_snapshot.boss_phases.%d" % index))
		if not _sorted_unique_ids(phase.effect_ids, true):
			return BattleInputValidationResult.failure(INPUT_INVALID, StringName("encounter_snapshot.boss_phases.%d.effect_ids" % index))
		if setup_schema_version == 2:
			if not _ascii_nonempty(String(phase.source_instance_id)) \
				or not _unit_instance_exists(preview.enemy_units, phase.source_instance_id):
				return BattleInputValidationResult.failure(
					INPUT_INVALID,
					StringName("encounter_snapshot.boss_phases.%d.source_instance_id" % index)
				)
		elif not phase.source_instance_id.is_empty():
			return BattleInputValidationResult.failure(
				INPUT_INVALID,
				StringName("encounter_snapshot.boss_phases.%d.source_instance_id" % index)
			)
		previous_phase = phase.phase_index
	return BattleInputValidationResult.success()

func _validate_units(
	units: Array[UnitBattleSnapshot],
	path: StringName,
	required_side: StringName,
	setup_schema_version: int
) -> BattleInputValidationResult:
	var previous: UnitBattleSnapshot = null
	var seen: Array[StringName] = []
	for index: int in range(units.size()):
		var unit := units[index]
		var item_path := StringName("%s.%d" % [path, index])
		if unit == null or unit.side != required_side:
			return BattleInputValidationResult.failure(INPUT_INVALID, item_path)
		if not _ascii_nonempty(String(unit.instance_id)) or seen.has(unit.instance_id):
			return BattleInputValidationResult.failure(INPUT_INVALID, StringName("%s.instance_id" % item_path))
		if not _stable_ids.is_valid(unit.unit_id):
			return BattleInputValidationResult.failure(INPUT_INVALID, StringName("%s.unit_id" % item_path))
		if unit.logical_x < 0 or unit.logical_x > 7 or unit.logical_y < 0 or unit.logical_y > 7 or unit.star < 1 or unit.star > 3:
			return BattleInputValidationResult.failure(INPUT_INVALID, item_path)
		if not _positive_i32(unit.health) or not _nonnegative_i32(unit.attack) or not _i32(unit.armor) or not _i32(unit.magic_resist):
			return BattleInputValidationResult.failure(INPUT_INVALID, item_path)
		if not _positive_i32(unit.attack_speed_milli) or unit.attack_range_cells < 0 or unit.attack_range_cells > 7:
			return BattleInputValidationResult.failure(INPUT_INVALID, item_path)
		if not _nonnegative_i32(unit.start_mana) or not _nonnegative_i32(unit.max_mana) or unit.max_mana < unit.start_mana or not _positive_i32(unit.move_speed_milli):
			return BattleInputValidationResult.failure(INPUT_INVALID, item_path)
		if setup_schema_version == 2 and unit.basic_attack_profile not in [
			&"melee", &"ranged", &"magic_projectile"
		]:
			return BattleInputValidationResult.failure(
				INPUT_INVALID, StringName("%s.basic_attack_profile" % item_path)
			)
		if unit.ability_id != null and not _stable_ids.is_valid(unit.ability_id.value):
			return BattleInputValidationResult.failure(INPUT_INVALID, StringName("%s.ability_id" % item_path))
		if not _sorted_unique_ids(unit.effect_ids, true):
			return BattleInputValidationResult.failure(INPUT_INVALID, StringName("%s.effect_ids" % item_path))
		if setup_schema_version == 1 and not unit.effect_assignments.is_empty():
			return BattleInputValidationResult.failure(
				INPUT_INVALID, StringName("%s.effect_assignments" % item_path)
			)
		var assignments_result := _validate_effects(
			unit.effect_assignments,
			StringName("%s.effect_assignments" % item_path),
			setup_schema_version
		)
		if not assignments_result.ok:
			return assignments_result
		if previous != null and not _unit_before(previous, unit):
			return BattleInputValidationResult.failure(INPUT_INVALID, path)
		seen.append(unit.instance_id)
		previous = unit
	return BattleInputValidationResult.success()

func _validate_traits(
	traits: Array[TraitBattleSnapshot],
	path: StringName,
	_required_side: StringName,
	setup_schema_version: int
) -> BattleInputValidationResult:
	var previous_id := ""
	for index: int in range(traits.size()):
		var trait_snapshot := traits[index]
		if trait_snapshot == null or not _stable_ids.is_valid(trait_snapshot.trait_id) or not _positive_i32(trait_snapshot.tier):
			return BattleInputValidationResult.failure(INPUT_INVALID, StringName("%s.%d" % [path, index]))
		if index > 0 and previous_id >= String(trait_snapshot.trait_id):
			return BattleInputValidationResult.failure(INPUT_INVALID, path)
		if not _sorted_unique_ids(trait_snapshot.member_instance_ids, false):
			return BattleInputValidationResult.failure(INPUT_INVALID, StringName("%s.%d.member_instance_ids" % [path, index]))
		if setup_schema_version == 1 and not trait_snapshot.effect_assignments.is_empty():
			return BattleInputValidationResult.failure(
				INPUT_INVALID,
				StringName("%s.%d.effect_assignments" % [path, index])
			)
		var assignments_result := _validate_effects(
			trait_snapshot.effect_assignments,
			StringName("%s.%d.effect_assignments" % [path, index]),
			setup_schema_version
		)
		if not assignments_result.ok:
			return assignments_result
		previous_id = String(trait_snapshot.trait_id)
	return BattleInputValidationResult.success()

func _validate_effects(
	effects: Array[BattleEffectSnapshot],
	path: StringName,
	setup_schema_version: int
) -> BattleInputValidationResult:
	var previous: BattleEffectSnapshot = null
	for index: int in range(effects.size()):
		var effect := effects[index]
		var item_path := StringName("%s.%d" % [path, index])
		if effect == null or not _i32(effect.priority) or not _nonnegative_i32(effect.effect_index) or not _stable_ids.is_valid(effect.source_stable_id) or not _stable_ids.is_valid(effect.effect_id):
			return BattleInputValidationResult.failure(INPUT_INVALID, item_path)
		if effect.source_instance_id != null and not _ascii_nonempty(String(effect.source_instance_id.value)):
			return BattleInputValidationResult.failure(INPUT_INVALID, StringName("%s.source_instance_id" % item_path))
		if setup_schema_version == 2:
			if effect.source_category not in [
				&"challenge", &"commander", &"relic", &"trait",
				&"encounter_affix", &"equipment", &"unit"
			] or effect.source_side not in [&"player", &"enemy", &"system"] \
				or not _nonnegative_i32(effect.source_slot):
				return BattleInputValidationResult.failure(
					INPUT_INVALID, StringName("%s.source" % item_path)
				)
		elif not effect.source_category.is_empty() or not effect.source_side.is_empty() \
			or effect.source_slot != 0:
			return BattleInputValidationResult.failure(
				INPUT_INVALID, StringName("%s.v2_source" % item_path)
			)
		if (setup_schema_version == 1 \
			and not _sorted_unique_ids(effect.target_ids, false)) \
			or (setup_schema_version == 2 \
				and not _unique_ascii_ids(effect.target_ids)):
			return BattleInputValidationResult.failure(INPUT_INVALID, StringName("%s.target_ids" % item_path))
		var previous_key := ""
		for parameter_index: int in range(effect.integer_params.size()):
			var parameter := effect.integer_params[parameter_index]
			if parameter == null or not _enum_token(String(parameter.key)) or not _i32(parameter.value) or (parameter_index > 0 and previous_key >= String(parameter.key)):
				return BattleInputValidationResult.failure(INPUT_INVALID, StringName("%s.integer_params" % item_path))
			previous_key = String(parameter.key)
		previous_key = ""
		for parameter_index: int in range(effect.id_params.size()):
			var parameter := effect.id_params[parameter_index]
			if parameter == null or not _enum_token(String(parameter.key)) or not _stable_ids.is_valid(parameter.value) or (parameter_index > 0 and previous_key >= String(parameter.key)):
				return BattleInputValidationResult.failure(INPUT_INVALID, StringName("%s.id_params" % item_path))
			previous_key = String(parameter.key)
		if setup_schema_version == 1 and previous != null \
			and not _effect_before(previous, effect):
			return BattleInputValidationResult.failure(INPUT_INVALID, path)
		previous = effect
	return BattleInputValidationResult.success()

func _validate_rules(
	rules: BattleRulesSnapshot,
	setup_schema_version: int
) -> BattleInputValidationResult:
	if rules == null:
		return BattleInputValidationResult.failure(INPUT_INVALID, &"battle_rules")
	if rules.tick_rate != 20 or rules.board_width != 8 or rules.board_height != 8:
		return BattleInputValidationResult.failure(INPUT_INVALID, &"battle_rules")
	if not _positive_i32(rules.soft_limit_ticks) \
		or not _positive_i32(rules.hard_limit_ticks) \
		or rules.hard_limit_ticks <= rules.soft_limit_ticks:
		return BattleInputValidationResult.failure(INPUT_INVALID, &"battle_rules.hard_limit_ticks")
	if setup_schema_version == 1:
		if not rules.ability_rules.is_empty() \
			or not rules.effect_rules.is_empty() \
			or not rules.summoned_unit_templates.is_empty():
			return BattleInputValidationResult.failure(INPUT_INVALID, &"battle_rules.v1_extensions")
		return BattleInputValidationResult.success()
	var fixed := PackedInt32Array([
		rules.simulation_version, rules.event_codec_version, rules.result_codec_version,
		rules.tick_rate, rules.board_width, rules.board_height, rules.soft_limit_ticks,
		rules.hard_limit_ticks, rules.progress_scale, rules.resistance_base,
		rules.basis_points, rules.overtime_interval_ticks, rules.main_actions_per_tick,
	])
	if fixed != PackedInt32Array([1, 1, 1, 20, 8, 8, 1200, 1800, 1000, 100, 10000, 20, 1]) \
		or rules.combat_config_id != &"config.combat_default":
		return BattleInputValidationResult.failure(INPUT_INVALID, &"battle_rules.version_or_fixed")
	if rules.attack_mana_gain < 0 or rules.attack_mana_gain > 100 \
		or rules.damage_mana_factor < 1 or rules.damage_mana_factor > 100 \
		or rules.damage_mana_min < 0 or rules.damage_mana_max > 100 \
		or rules.damage_mana_min > rules.damage_mana_max:
		return BattleInputValidationResult.failure(INPUT_INVALID, &"battle_rules.mana")
	if rules.overtime_step_bps < 1 or rules.overtime_step_bps > 1000 \
		or rules.overtime_cap_bps < rules.overtime_step_bps \
		or rules.overtime_cap_bps > 10000:
		return BattleInputValidationResult.failure(INPUT_INVALID, &"battle_rules.overtime")
	if rules.act_index < 1 or rules.act_index > 3 \
		or rules.encounter_kind not in [&"normal", &"elite", &"boss"]:
		return BattleInputValidationResult.failure(INPUT_INVALID, &"battle_rules.encounter")
	for value: int in [rules.act1_base_damage, rules.act2_base_damage, rules.act3_base_damage]:
		if value < 1 or value > 100:
			return BattleInputValidationResult.failure(INPUT_INVALID, &"battle_rules.act_base_damage")
	if rules.survivor_damage < 0 or rules.survivor_damage > 100 \
		or rules.boss_damage < 0 or rules.boss_damage > 100:
		return BattleInputValidationResult.failure(INPUT_INVALID, &"battle_rules.expedition_damage")
	if rules.effect_resolution_budget < 64 or rules.effect_resolution_budget > 65535 \
		or rules.operation_budget < rules.effect_resolution_budget \
		or rules.operation_budget > 65535 \
		or rules.event_budget < 64 or rules.event_budget > 65535 \
		or rules.entity_budget < 64 or rules.entity_budget > 1024:
		return BattleInputValidationResult.failure(INPUT_INVALID, &"battle_rules.budgets")
	var previous_id := ""
	for index: int in range(rules.ability_rules.size()):
		var ability: BattleAbilityRuleSnapshot = rules.ability_rules[index]
		if ability == null or not _stable_ids.is_valid(ability.ability_id) \
			or String(ability.ability_id) <= previous_id \
			or ability.target_rule not in _ABILITY_TARGETS \
			or ability.cast_ticks < 1 or ability.cast_ticks > 1800 \
			or not _ordered_unique_stable_ids(ability.effect_ids):
			return BattleInputValidationResult.failure(INPUT_INVALID, &"battle_rules.ability_rules")
		previous_id = String(ability.ability_id)
	previous_id = ""
	for index: int in range(rules.effect_rules.size()):
		var effect: BattleEffectRuleSnapshot = rules.effect_rules[index]
		if effect == null or not _stable_ids.is_valid(effect.effect_id) \
			or String(effect.effect_id) <= previous_id \
			or effect.trigger not in _TRIGGERS or effect.stacking not in _STACKING \
			or effect.max_stacks < 1 or effect.max_stacks > 99 \
			or effect.duration_ticks < 1 or effect.duration_ticks > 1800:
			return BattleInputValidationResult.failure(INPUT_INVALID, &"battle_rules.effect_rules")
		if (effect.trigger == &"periodic" and (effect.periodic_interval_ticks < 1 or effect.periodic_interval_ticks > 1800)) \
			or (effect.trigger != &"periodic" and effect.periodic_interval_ticks != 0):
			return BattleInputValidationResult.failure(INPUT_INVALID, &"battle_rules.effect_rules.periodic_interval_ticks")
		if not _conditions_valid(effect.conditions) \
			or not _operations_valid(effect.battle_operations) \
			or not _run_operations_valid(effect.run_operations):
			return BattleInputValidationResult.failure(INPUT_INVALID, &"battle_rules.effect_rules.payload")
		previous_id = String(effect.effect_id)
	previous_id = ""
	for template: SummonedUnitRuleSnapshot in rules.summoned_unit_templates:
		if template == null or not _stable_ids.is_valid(template.unit_id) \
			or String(template.unit_id) <= previous_id \
			or template.star != 1 or not _sorted_unique_ids(template.trait_ids, true) \
			or template.health < 1 or template.attack < 0 \
			or template.attack_speed_milli < 1 or template.move_speed_milli < 1 \
			or template.attack_range_cells < 0 or template.attack_range_cells > 7 \
			or template.start_mana < 0 or template.max_mana < template.start_mana \
			or template.ai_profile != &"frontline" \
			or template.basic_attack_profile not in [&"melee", &"ranged", &"magic_projectile"]:
			return BattleInputValidationResult.failure(INPUT_INVALID, &"battle_rules.summoned_unit_templates")
		if template.ability_id != null and not _stable_ids.is_valid(template.ability_id.value):
			return BattleInputValidationResult.failure(INPUT_INVALID, &"battle_rules.summoned_unit_templates.ability_id")
		if not _assignments_valid(template.unit_effect_assignments):
			return BattleInputValidationResult.failure(INPUT_INVALID, &"battle_rules.summoned_unit_templates.assignments")
		previous_id = String(template.unit_id)
	if rules.summoned_unit_templates.size() > rules.entity_budget:
		return BattleInputValidationResult.failure(INPUT_INVALID, &"battle_rules.summoned_unit_templates")
	return BattleInputValidationResult.success()

func _conditions_valid(values: Array[BattleConditionRule]) -> bool:
	var previous := ""
	for value: BattleConditionRule in values:
		if value == null or value.kind not in [
			&"source_tag", &"target_tag", &"health_below_bps", &"health_above_bps",
			&"distance_at_most", &"distance_at_least", &"has_status", &"lacks_status",
			&"has_equipment", &"max_uses_per_battle"
		]: return false
		var valid := false
		match value.kind:
			&"source_tag": valid = _condition_stable(value, &"source", &"has")
			&"target_tag": valid = _condition_stable(value, &"target", &"has")
			&"health_below_bps": valid = _condition_int(value, [&"source", &"target"], &"lt", 0, 10000)
			&"health_above_bps": valid = _condition_int(value, [&"source", &"target"], &"gt", 0, 10000)
			&"distance_at_most": valid = _condition_int(value, [&"source_target"], &"lte", 0, 7)
			&"distance_at_least": valid = _condition_int(value, [&"source_target"], &"gte", 0, 7)
			&"has_status": valid = _condition_stable(value, value.subject, &"has") and value.subject in [&"source", &"target"]
			&"lacks_status": valid = _condition_stable(value, value.subject, &"not_has") and value.subject in [&"source", &"target"]
			&"has_equipment": valid = _condition_stable(value, value.subject, &"has") and value.subject in [&"source", &"target"]
			&"max_uses_per_battle":
				valid = value.subject == &"effect" and value.comparator == &"lt" \
					and value.int_value == null and value.stable_id_value == null \
					and value.max_uses_per_battle != null \
					and value.max_uses_per_battle.value >= 1 and value.max_uses_per_battle.value <= 99
		if not valid: return false
		var key := _condition_sort_key(value)
		if not previous.is_empty() and key <= previous: return false
		previous = key
	return true

func _condition_stable(value: BattleConditionRule, subject: StringName, comparator: StringName) -> bool:
	return value.subject == subject and value.comparator == comparator \
		and value.int_value == null and value.max_uses_per_battle == null \
		and value.stable_id_value != null \
		and _stable_ids.is_valid(value.stable_id_value.value)

func _condition_int(
	value: BattleConditionRule,
	subjects: Array[StringName],
	comparator: StringName,
	minimum: int,
	maximum: int
) -> bool:
	return value.subject in subjects and value.comparator == comparator \
		and value.int_value != null and value.stable_id_value == null \
		and value.max_uses_per_battle == null \
		and value.int_value.value >= minimum and value.int_value.value <= maximum

func _condition_sort_key(value: BattleConditionRule) -> String:
	return "%s/%s/%s/%012d/%s/%012d" % [
		String(value.kind), String(value.subject), String(value.comparator),
		value.int_value.value if value.int_value != null else -1,
		String(value.stable_id_value.value) if value.stable_id_value != null else "",
		value.max_uses_per_battle.value if value.max_uses_per_battle != null else -1,
	]

func _operations_valid(values: Array[BattleOperationRule]) -> bool:
	for index: int in range(values.size()):
		var value: BattleOperationRule = values[index]
		if value == null or value.operation_index != index or not _operation_valid(value):
			return false
	return true

func _operation_valid(value: BattleOperationRule) -> bool:
	var canonical := BattleOperationRule.new()
	canonical.operation_index = value.operation_index
	canonical.kind = value.kind
	match value.kind:
		&"damage":
			canonical.base_amount = value.base_amount; canonical.scaling = value.scaling
			canonical.damage_type = value.damage_type; canonical.target = value.target
			if value.base_amount < 0 or value.scaling not in [&"flat", &"attack"] \
				or value.damage_type not in [&"physical", &"magical", &"true"] \
				or value.target not in _OPERATION_TARGETS: return false
		&"heal":
			canonical.base_amount = value.base_amount; canonical.scaling = value.scaling; canonical.target = value.target
			if value.base_amount < 0 or value.scaling not in [&"flat", &"attack"] or value.target not in _OPERATION_TARGETS: return false
		&"shield":
			canonical.amount = value.amount; canonical.duration_ticks = value.duration_ticks; canonical.target = value.target
			if value.amount < 0 or value.duration_ticks < 1 or value.duration_ticks > 1800 or value.target not in _OPERATION_TARGETS: return false
		&"modify_stat":
			canonical.stat = value.stat; canonical.mode = value.mode; canonical.amount = value.amount
			canonical.duration_ticks = value.duration_ticks; canonical.target = value.target
			if value.stat not in [&"attack", &"armor", &"magic_resist", &"attack_speed_milli", &"move_speed_milli"] \
				or value.mode not in [&"add", &"multiply_bps"] \
				or (value.mode == &"multiply_bps" and (value.amount < 0 or value.amount > 100000)) \
				or value.duration_ticks < 1 or value.duration_ticks > 1800 \
				or value.target not in _OPERATION_TARGETS: return false
		&"apply_status":
			canonical.status_id = value.status_id.deep_clone() if value.status_id != null else null
			canonical.stacks = value.stacks; canonical.duration_ticks = value.duration_ticks; canonical.target = value.target
			if value.status_id == null or not _stable_ids.is_valid(value.status_id.value) \
				or value.stacks < 1 or value.stacks > 99 \
				or value.duration_ticks < 1 or value.duration_ticks > 1800 \
				or value.target not in _OPERATION_TARGETS: return false
		&"remove_status":
			canonical.status_id = value.status_id.deep_clone() if value.status_id != null else null; canonical.target = value.target
			if value.status_id == null or not _stable_ids.is_valid(value.status_id.value) or value.target not in _OPERATION_TARGETS: return false
		&"move":
			canonical.direction = value.direction; canonical.cells = value.cells
			if value.direction not in [&"forward", &"toward_target", &"away_from_target"] or value.cells < 1 or value.cells > 7: return false
		&"summon":
			canonical.unit_id = value.unit_id.deep_clone() if value.unit_id != null else null
			canonical.count = value.count; canonical.max_active_per_source = value.max_active_per_source
			canonical.placement_rule = value.placement_rule
			if value.unit_id == null or not _stable_ids.is_valid(value.unit_id.value) \
				or value.count < 1 or value.count > 64 \
				or value.max_active_per_source < 1 or value.max_active_per_source > 64 \
				or value.placement_rule != &"adjacent": return false
		&"grant_mana":
			canonical.amount = value.amount; canonical.target = value.target
			if value.amount < 0 or value.target not in _OPERATION_TARGETS: return false
		_: return false
	return _operation_equal(value, canonical)

func _operation_equal(left: BattleOperationRule, right: BattleOperationRule) -> bool:
	return left.operation_index == right.operation_index and left.kind == right.kind \
		and left.base_amount == right.base_amount and left.amount == right.amount \
		and left.scaling == right.scaling and left.damage_type == right.damage_type \
		and left.target == right.target and left.duration_ticks == right.duration_ticks \
		and left.stat == right.stat and left.mode == right.mode \
		and _optional_name_equal(left.status_id, right.status_id) \
		and left.stacks == right.stacks and left.direction == right.direction \
		and left.cells == right.cells and _optional_name_equal(left.unit_id, right.unit_id) \
		and left.count == right.count and left.max_active_per_source == right.max_active_per_source \
		and left.placement_rule == right.placement_rule

func _run_operations_valid(values: Array[BattleRunOperationRule]) -> bool:
	for index: int in range(values.size()):
		var value: BattleRunOperationRule = values[index]
		if value == null or value.operation_index != index \
			or value.kind not in [&"add_gold", &"add_xp", &"heal_expedition_hp"] \
			or value.amount < 0 \
			or value.claim_scope not in [&"once_per_node", &"on_first_clear"]:
			return false
	return true

func _assignments_valid(values: Array[UnitEffectAssignmentSnapshot]) -> bool:
	var previous := ""
	var identities: Dictionary = {}
	for value: UnitEffectAssignmentSnapshot in values:
		if value == null or not _i32(value.priority) or value.effect_index < 0 \
			or not _stable_ids.is_valid(value.source_stable_id) \
			or not _stable_ids.is_valid(value.effect_id): return false
		var identity := "%s/%010d" % [String(value.source_stable_id), value.effect_index]
		if identities.has(identity): return false
		identities[identity] = true
		var key := "%012d/%s/%010d/%s" % [value.priority, String(value.source_stable_id), value.effect_index, String(value.effect_id)]
		if not previous.is_empty() and key <= previous: return false
		previous = key
	return true

func _validate_v2_source_graph(inputs: BattleSetupInputs) -> BattleInputValidationResult:
	var all_units: Array[UnitBattleSnapshot] = []
	for unit: UnitBattleSnapshot in inputs.player_units:
		all_units.append(unit)
	for unit: UnitBattleSnapshot in inputs.encounter_snapshot.enemy_units:
		all_units.append(unit)
	var identities: Dictionary = {}
	var result := _validate_source_list(
		inputs.challenge_modifiers,
		&"challenge_modifiers",
		&"challenge",
		&"player",
		all_units,
		inputs.player_units,
		identities,
		&"null",
		&"",
		&"",
		0
	)
	if not result.ok: return result
	result = _validate_source_list(
		inputs.commander_effects,
		&"commander_effects",
		&"commander",
		&"player",
		all_units,
		inputs.player_units,
		identities,
		&"null",
		&"",
		&"",
		0
	)
	if not result.ok: return result
	result = _validate_source_list(
		inputs.player_relic_effects,
		&"player_relic_effects",
		&"relic",
		&"player",
		all_units,
		inputs.player_units,
		identities,
		&"null",
		&"",
		&"",
		4
	)
	if not result.ok: return result
	result = _validate_source_list(
		inputs.encounter_snapshot.affix_effects,
		&"encounter_snapshot.affix_effects",
		&"encounter_affix",
		&"enemy",
		all_units,
		inputs.player_units,
		identities,
		&"null",
		&"",
		&"",
		0
	)
	if not result.ok: return result
	result = _validate_source_list(
		inputs.player_equipment_effects,
		&"player_equipment_effects",
		&"equipment",
		&"player",
		all_units,
		inputs.player_units,
		identities,
		&"player_unit",
		&"",
		&"",
		2
	)
	if not result.ok: return result
	for unit_index: int in range(inputs.player_units.size()):
		var unit: UnitBattleSnapshot = inputs.player_units[unit_index]
		result = _validate_unit_source_assignments(
			unit,
			StringName("player_units.%d.effect_assignments" % unit_index),
			all_units,
			inputs.player_units,
			identities
		)
		if not result.ok: return result
	for unit_index: int in range(inputs.encounter_snapshot.enemy_units.size()):
		var unit: UnitBattleSnapshot = inputs.encounter_snapshot.enemy_units[unit_index]
		result = _validate_unit_source_assignments(
			unit,
			StringName("encounter_snapshot.enemy_units.%d.effect_assignments" % unit_index),
			all_units,
			inputs.player_units,
			identities
		)
		if not result.ok: return result
	for trait_index: int in range(inputs.player_active_traits.size()):
		var trait_snapshot: TraitBattleSnapshot = inputs.player_active_traits[trait_index]
		result = _validate_source_list(
			trait_snapshot.effect_assignments,
			StringName("player_active_traits.%d.effect_assignments" % trait_index),
			&"trait", &"player", all_units, inputs.player_units, identities,
			&"null", &"", trait_snapshot.trait_id, 0
		)
		if not result.ok: return result
	for trait_index: int in range(inputs.encounter_snapshot.active_traits.size()):
		var trait_snapshot: TraitBattleSnapshot = inputs.encounter_snapshot.active_traits[trait_index]
		result = _validate_source_list(
			trait_snapshot.effect_assignments,
			StringName("encounter_snapshot.active_traits.%d.effect_assignments" % trait_index),
			&"trait", &"enemy", all_units, inputs.player_units, identities,
			&"null", &"", trait_snapshot.trait_id, 0
		)
		if not result.ok: return result
	return BattleInputValidationResult.success()

func _validate_unit_source_assignments(
	unit: UnitBattleSnapshot,
	path: StringName,
	all_units: Array[UnitBattleSnapshot],
	player_units: Array[UnitBattleSnapshot],
	identities: Dictionary
) -> BattleInputValidationResult:
	var result := _validate_source_list(
		unit.effect_assignments,
		path,
		&"unit",
		unit.side,
		all_units,
		player_units,
		identities,
		&"exact",
		unit.instance_id,
		unit.unit_id,
		0
	)
	if not result.ok:
		return result
	if unit.effect_assignments.size() != unit.effect_ids.size():
		return BattleInputValidationResult.failure(INPUT_INVALID, path)
	for assignment: BattleEffectSnapshot in unit.effect_assignments:
		if not unit.effect_ids.has(assignment.effect_id):
			return BattleInputValidationResult.failure(INPUT_INVALID, path)
	return BattleInputValidationResult.success()

func _validate_source_list(
	effects: Array[BattleEffectSnapshot],
	path: StringName,
	expected_category: StringName,
	expected_side: StringName,
	all_units: Array[UnitBattleSnapshot],
	player_units: Array[UnitBattleSnapshot],
	identities: Dictionary,
	owner_mode: StringName,
	expected_owner: StringName,
	expected_stable_id: StringName,
	maximum_slot: int
) -> BattleInputValidationResult:
	var previous: BattleEffectSnapshot = null
	for index: int in range(effects.size()):
		var effect: BattleEffectSnapshot = effects[index]
		var item_path := StringName("%s.%d" % [path, index])
		if effect.source_category != expected_category \
			or effect.source_side != expected_side \
			or effect.source_slot < 0 or effect.source_slot > maximum_slot \
			or (not expected_stable_id.is_empty() \
				and effect.source_stable_id != expected_stable_id):
			return BattleInputValidationResult.failure(INPUT_INVALID, StringName("%s.source" % item_path))
		match owner_mode:
			&"null":
				if effect.source_instance_id != null:
					return BattleInputValidationResult.failure(INPUT_INVALID, StringName("%s.source_instance_id" % item_path))
			&"player_unit":
				if effect.source_instance_id == null \
					or _find_unit(player_units, effect.source_instance_id.value) == null:
					return BattleInputValidationResult.failure(INPUT_INVALID, StringName("%s.source_instance_id" % item_path))
			&"exact":
				if effect.source_instance_id == null \
					or effect.source_instance_id.value != expected_owner:
					return BattleInputValidationResult.failure(INPUT_INVALID, StringName("%s.source_instance_id" % item_path))
			_:
				return BattleInputValidationResult.failure(INPUT_INVALID, &"source.owner_mode")
		if not _targets_in_cell_order(effect.target_ids, all_units):
			return BattleInputValidationResult.failure(INPUT_INVALID, StringName("%s.target_ids" % item_path))
		var identity := _source_identity(effect)
		if identities.has(identity):
			return BattleInputValidationResult.failure(INPUT_INVALID, StringName("%s.identity" % item_path))
		identities[identity] = true
		if previous != null and not _source_assignment_before(
			previous, effect, expected_category, all_units
		):
			return BattleInputValidationResult.failure(INPUT_INVALID, path)
		previous = effect
	return BattleInputValidationResult.success()

func _source_identity(value: BattleEffectSnapshot) -> String:
	var owner := "" if value.source_instance_id == null else String(value.source_instance_id.value)
	return "%s|%s|%s|%s|%d|%d" % [
		String(value.source_category), String(value.source_side),
		String(value.source_stable_id), owner, value.source_slot, value.effect_index,
	]

func _source_assignment_before(
	left: BattleEffectSnapshot,
	right: BattleEffectSnapshot,
	category: StringName,
	all_units: Array[UnitBattleSnapshot]
) -> bool:
	if category == &"relic" and left.source_slot != right.source_slot:
		return left.source_slot < right.source_slot
	if category == &"equipment":
		var left_unit := _find_unit(all_units, left.source_instance_id.value)
		var right_unit := _find_unit(all_units, right.source_instance_id.value)
		var left_cell := left_unit.logical_y * 8 + left_unit.logical_x
		var right_cell := right_unit.logical_y * 8 + right_unit.logical_x
		if left_cell != right_cell: return left_cell < right_cell
		if left.source_slot != right.source_slot: return left.source_slot < right.source_slot
		if left.source_instance_id.value != right.source_instance_id.value:
			return String(left.source_instance_id.value) < String(right.source_instance_id.value)
	if category in [&"challenge", &"commander", &"trait", &"encounter_affix"] \
		and left.source_stable_id != right.source_stable_id:
		return String(left.source_stable_id) < String(right.source_stable_id)
	if left.priority != right.priority: return left.priority < right.priority
	if left.source_stable_id != right.source_stable_id:
		return String(left.source_stable_id) < String(right.source_stable_id)
	if left.effect_index != right.effect_index: return left.effect_index < right.effect_index
	if left.effect_id != right.effect_id: return String(left.effect_id) < String(right.effect_id)
	return _id_array_before(left.target_ids, right.target_ids)

func _targets_in_cell_order(
	target_ids: Array[StringName],
	all_units: Array[UnitBattleSnapshot]
) -> bool:
	var previous: UnitBattleSnapshot = null
	for target_id: StringName in target_ids:
		var target := _find_unit(all_units, target_id)
		if target == null: return false
		if previous != null:
			var previous_cell := previous.logical_y * 8 + previous.logical_x
			var current_cell := target.logical_y * 8 + target.logical_x
			if previous_cell > current_cell \
				or (previous_cell == current_cell \
					and String(previous.instance_id) >= String(target.instance_id)):
				return false
		previous = target
	return true

func _find_unit(
	units: Array[UnitBattleSnapshot],
	instance_id: StringName
) -> UnitBattleSnapshot:
	for unit: UnitBattleSnapshot in units:
		if unit.instance_id == instance_id: return unit
	return null

func _id_array_before(left: Array[StringName], right: Array[StringName]) -> bool:
	var count := mini(left.size(), right.size())
	for index: int in range(count):
		if left[index] != right[index]: return String(left[index]) < String(right[index])
	return left.size() < right.size()

func _validate_rule_references(inputs: BattleSetupInputs) -> BattleInputValidationResult:
	var ability_ids: Array[StringName] = []
	var effect_ids: Array[StringName] = []
	var template_ids: Array[StringName] = []
	for rule: BattleAbilityRuleSnapshot in inputs.battle_rules.ability_rules: ability_ids.append(rule.ability_id)
	for rule: BattleEffectRuleSnapshot in inputs.battle_rules.effect_rules: effect_ids.append(rule.effect_id)
	for template: SummonedUnitRuleSnapshot in inputs.battle_rules.summoned_unit_templates: template_ids.append(template.unit_id)
	for unit: UnitBattleSnapshot in inputs.player_units:
		if unit.ability_id != null and not ability_ids.has(unit.ability_id.value): return _reference_failure(&"player_units.ability_id")
		for effect_id: StringName in unit.effect_ids:
			if not effect_ids.has(effect_id): return _reference_failure(&"player_units.effect_ids")
		if not _effect_assignments_reference(unit.effect_assignments, effect_ids):
			return _reference_failure(&"player_units.effect_assignments")
	for unit: UnitBattleSnapshot in inputs.encounter_snapshot.enemy_units:
		if unit.ability_id != null and not ability_ids.has(unit.ability_id.value): return _reference_failure(&"enemy_units.ability_id")
		for effect_id: StringName in unit.effect_ids:
			if not effect_ids.has(effect_id): return _reference_failure(&"enemy_units.effect_ids")
		if not _effect_assignments_reference(unit.effect_assignments, effect_ids):
			return _reference_failure(&"enemy_units.effect_assignments")
	for trait_snapshot: TraitBattleSnapshot in inputs.player_active_traits:
		if not _effect_assignments_reference(trait_snapshot.effect_assignments, effect_ids):
			return _reference_failure(&"player_traits.effect_assignments")
	for trait_snapshot: TraitBattleSnapshot in inputs.encounter_snapshot.active_traits:
		if not _effect_assignments_reference(trait_snapshot.effect_assignments, effect_ids):
			return _reference_failure(&"enemy_traits.effect_assignments")
	if not _effect_assignments_reference(inputs.player_equipment_effects, effect_ids) \
		or not _effect_assignments_reference(inputs.player_relic_effects, effect_ids) \
		or not _effect_assignments_reference(inputs.commander_effects, effect_ids) \
		or not _effect_assignments_reference(inputs.challenge_modifiers, effect_ids) \
		or not _effect_assignments_reference(
			inputs.encounter_snapshot.affix_effects, effect_ids
		):
		return _reference_failure(&"source_assignments.effect_id")
	for rule: BattleAbilityRuleSnapshot in inputs.battle_rules.ability_rules:
		for effect_id: StringName in rule.effect_ids:
			if not effect_ids.has(effect_id): return _reference_failure(&"ability_rules.effect_ids")
	for rule: BattleEffectRuleSnapshot in inputs.battle_rules.effect_rules:
		for operation: BattleOperationRule in rule.battle_operations:
			if operation.kind == &"summon" and (operation.unit_id == null or not template_ids.has(operation.unit_id.value)):
				return _reference_failure(&"effect_rules.summon.unit_id")
			if operation.status_id != null and not effect_ids.has(operation.status_id.value):
				return _reference_failure(&"effect_rules.status_id")
	for template: SummonedUnitRuleSnapshot in inputs.battle_rules.summoned_unit_templates:
		if template.ability_id != null and not ability_ids.has(template.ability_id.value): return _reference_failure(&"templates.ability_id")
		for assignment: UnitEffectAssignmentSnapshot in template.unit_effect_assignments:
			if not effect_ids.has(assignment.effect_id): return _reference_failure(&"templates.effect_id")
	return BattleInputValidationResult.success()

func _effect_assignments_reference(
	assignments: Array[BattleEffectSnapshot],
	effect_ids: Array[StringName]
) -> bool:
	for assignment: BattleEffectSnapshot in assignments:
		if not effect_ids.has(assignment.effect_id): return false
	return true

func _reference_failure(path: StringName) -> BattleInputValidationResult:
	return BattleInputValidationResult.failure(INPUT_INVALID, StringName("battle_rules.%s" % path))

func _optional_name_equal(left: OptionalStringNameValue, right: OptionalStringNameValue) -> bool:
	return (left == null and right == null) \
		or (left != null and right != null and left.value == right.value)

func _ordered_unique_stable_ids(values: Array[StringName]) -> bool:
	var seen: Dictionary = {}
	for value: StringName in values:
		if not _stable_ids.is_valid(value) or seen.has(value): return false
		seen[value] = true
	return true

func _unit_instance_exists(values: Array[UnitBattleSnapshot], target: StringName) -> bool:
	for value: UnitBattleSnapshot in values:
		if value.instance_id == target: return true
	return false

func _unit_before(left: UnitBattleSnapshot, right: UnitBattleSnapshot) -> bool:
	var left_side := 0 if left.side == &"player" else 1
	var right_side := 0 if right.side == &"player" else 1
	if left_side != right_side: return left_side < right_side
	if left.logical_y != right.logical_y: return left.logical_y < right.logical_y
	if left.logical_x != right.logical_x: return left.logical_x < right.logical_x
	return String(left.instance_id) < String(right.instance_id)

func _effect_before(left: BattleEffectSnapshot, right: BattleEffectSnapshot) -> bool:
	if left.priority != right.priority: return left.priority < right.priority
	if left.source_stable_id != right.source_stable_id: return String(left.source_stable_id) < String(right.source_stable_id)
	return left.effect_index < right.effect_index

func _sorted_unique_ids(values: Array[StringName], require_stable: bool) -> bool:
	var previous := ""
	for index: int in range(values.size()):
		var current := String(values[index])
		if (require_stable and not _stable_ids.is_valid(values[index])) or (not require_stable and not _ascii_nonempty(current)):
			return false
		if index > 0 and previous >= current:
			return false
		previous = current
	return true

func _unique_ascii_ids(values: Array[StringName]) -> bool:
	var seen: Dictionary = {}
	for value: StringName in values:
		if not _ascii_nonempty(String(value)) or seen.has(value): return false
		seen[value] = true
	return true

func _digest(value: StringName) -> bool:
	var text := String(value)
	if text.length() != 64: return false
	for index: int in range(text.length()):
		var code := text.unicode_at(index)
		if not (code >= 48 and code <= 57) and not (code >= 97 and code <= 102): return false
	return true

func _ascii_nonempty(value: String) -> bool:
	if value.is_empty(): return false
	for byte: int in value.to_utf8_buffer():
		if byte < 33 or byte > 126: return false
	return true

func _enum_token(value: String) -> bool:
	if value.is_empty(): return false
	for index: int in range(value.length()):
		var code := value.unicode_at(index)
		if index == 0:
			if code < 97 or code > 122: return false
		elif not (code >= 97 and code <= 122) and not (code >= 48 and code <= 57) and code != 95:
			return false
	return true

func _i32(value: int) -> bool:
	return value >= -2147483648 and value <= 2147483647

func _nonnegative_i32(value: int) -> bool:
	return value >= 0 and value <= 2147483647

func _positive_i32(value: int) -> bool:
	return value > 0 and value <= 2147483647
