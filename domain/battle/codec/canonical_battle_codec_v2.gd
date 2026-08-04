class_name CanonicalBattleCodecV2
extends CanonicalBattleCodecV1

func encode(inputs: BattleSetupInputs) -> BattleCodecResult:
	var validation := BattleSetupInputsValidator.new().validate(inputs)
	if not validation.ok:
		return BattleCodecResult.failure(validation.error.code, validation.error.field_path)
	if inputs.setup_schema_version != 2:
		return BattleCodecResult.failure(CODEC_INVALID, &"setup_schema_version")
	return BattleCodecResult.encoded(BattleCanonicalWriterV2.new().write(inputs))

func decode(bytes: PackedByteArray) -> BattleCodecResult:
	if bytes.is_empty():
		return BattleCodecResult.failure(CODEC_INVALID, &"bytes")
	var text_value := bytes.get_string_from_utf8()
	if text_value.to_utf8_buffer() != bytes:
		return BattleCodecResult.failure(CODEC_INVALID, &"bytes")
	var reader := BattleCanonicalReader.new(text_value)
	var inputs := _read_inputs(reader)
	if reader.failed() or not reader.at_end():
		return BattleCodecResult.failure(
			CODEC_INVALID,
			reader.error_path() if reader.failed() else &"trailing_bytes"
		)
	var validation := BattleSetupInputsValidator.new().validate(inputs)
	if not validation.ok or inputs.setup_schema_version != 2:
		return BattleCodecResult.failure(
			CODEC_INVALID,
			validation.error.field_path if not validation.ok else &"setup_schema_version"
		)
	var canonical := BattleCanonicalWriterV2.new().write(inputs)
	if canonical != bytes:
		return BattleCodecResult.failure(CODEC_INVALID, &"canonical_bytes")
	return BattleCodecResult.decoded(inputs)

func _read_unit(reader: BattleCanonicalReader, path: StringName) -> UnitBattleSnapshot:
	var value := UnitBattleSnapshot.new()
	reader.begin_object(path)
	reader.read_key("instance_id", true, path)
	value.instance_id = StringName(reader.read_string(StringName("%s.instance_id" % path)))
	reader.read_key("unit_id", false, path)
	value.unit_id = StringName(reader.read_string(StringName("%s.unit_id" % path)))
	reader.read_key("side", false, path)
	value.side = StringName(reader.read_string(StringName("%s.side" % path)))
	reader.read_key("logical_y", false, path)
	value.logical_y = reader.read_int(StringName("%s.logical_y" % path))
	reader.read_key("logical_x", false, path)
	value.logical_x = reader.read_int(StringName("%s.logical_x" % path))
	reader.read_key("star", false, path)
	value.star = reader.read_int(StringName("%s.star" % path))
	reader.read_key("health", false, path)
	value.health = reader.read_int(StringName("%s.health" % path))
	reader.read_key("attack", false, path)
	value.attack = reader.read_int(StringName("%s.attack" % path))
	reader.read_key("armor", false, path)
	value.armor = reader.read_int(StringName("%s.armor" % path))
	reader.read_key("magic_resist", false, path)
	value.magic_resist = reader.read_int(StringName("%s.magic_resist" % path))
	reader.read_key("attack_speed_milli", false, path)
	value.attack_speed_milli = reader.read_int(StringName("%s.attack_speed_milli" % path))
	reader.read_key("attack_range_cells", false, path)
	value.attack_range_cells = reader.read_int(StringName("%s.attack_range_cells" % path))
	reader.read_key("start_mana", false, path)
	value.start_mana = reader.read_int(StringName("%s.start_mana" % path))
	reader.read_key("max_mana", false, path)
	value.max_mana = reader.read_int(StringName("%s.max_mana" % path))
	reader.read_key("move_speed_milli", false, path)
	value.move_speed_milli = reader.read_int(StringName("%s.move_speed_milli" % path))
	reader.read_key("basic_attack_profile", false, path)
	value.basic_attack_profile = StringName(reader.read_string(
		StringName("%s.basic_attack_profile" % path)
	))
	reader.read_key("ability_id", false, path)
	if reader.next_is_null():
		reader.read_null(StringName("%s.ability_id" % path))
	else:
		value.ability_id = OptionalStringNameValue.of(StringName(reader.read_string(StringName("%s.ability_id" % path))))
	reader.read_key("effect_ids", false, path)
	value.effect_ids = _read_ids(reader, StringName("%s.effect_ids" % path))
	reader.read_key("effect_assignments", false, path)
	value.effect_assignments = _read_effects(reader, StringName("%s.effect_assignments" % path))
	reader.end_object(path)
	return value

func _read_traits(reader: BattleCanonicalReader, path: StringName) -> Array[TraitBattleSnapshot]:
	var values: Array[TraitBattleSnapshot] = []
	reader.begin_array(path)
	var first := true
	while reader.array_next(first, path):
		first = false
		var value := TraitBattleSnapshot.new()
		var item_path := StringName("%s.%d" % [path, values.size()])
		reader.begin_object(item_path)
		reader.read_key("trait_id", true, item_path)
		value.trait_id = StringName(reader.read_string(StringName("%s.trait_id" % item_path)))
		reader.read_key("tier", false, item_path)
		value.tier = reader.read_int(StringName("%s.tier" % item_path))
		reader.read_key("member_instance_ids", false, item_path)
		value.member_instance_ids = _read_ids(reader, StringName("%s.member_instance_ids" % item_path))
		reader.read_key("effect_assignments", false, item_path)
		value.effect_assignments = _read_effects(reader, StringName("%s.effect_assignments" % item_path))
		reader.end_object(item_path)
		values.append(value)
	return values

func _read_effect(reader: BattleCanonicalReader, path: StringName) -> BattleEffectSnapshot:
	var value := BattleEffectSourceAssignmentSnapshot.new()
	reader.begin_object(path)
	reader.read_key("priority", true, path)
	value.priority = reader.read_int(StringName("%s.priority" % path))
	reader.read_key("source_category", false, path)
	value.source_category = StringName(reader.read_string(StringName("%s.source_category" % path)))
	reader.read_key("source_side", false, path)
	value.source_side = StringName(reader.read_string(StringName("%s.source_side" % path)))
	reader.read_key("source_stable_id", false, path)
	value.source_stable_id = StringName(reader.read_string(StringName("%s.source_stable_id" % path)))
	reader.read_key("source_instance_id", false, path)
	if reader.next_is_null():
		reader.read_null(StringName("%s.source_instance_id" % path))
	else:
		value.source_instance_id = OptionalStringNameValue.of(StringName(reader.read_string(StringName("%s.source_instance_id" % path))))
	reader.read_key("source_slot", false, path)
	value.source_slot = reader.read_int(StringName("%s.source_slot" % path))
	reader.read_key("effect_index", false, path)
	value.effect_index = reader.read_int(StringName("%s.effect_index" % path))
	reader.read_key("effect_id", false, path)
	value.effect_id = StringName(reader.read_string(StringName("%s.effect_id" % path)))
	reader.read_key("target_ids", false, path)
	value.target_ids = _read_ids(reader, StringName("%s.target_ids" % path))
	reader.read_key("integer_params", false, path)
	value.integer_params = _read_int_params(reader, StringName("%s.integer_params" % path))
	reader.read_key("id_params", false, path)
	value.id_params = _read_id_params(reader, StringName("%s.id_params" % path))
	reader.end_object(path)
	return value

func _read_phases(reader: BattleCanonicalReader, path: StringName) -> Array[BossPhaseSnapshot]:
	var values: Array[BossPhaseSnapshot] = []
	reader.begin_array(path)
	var first := true
	while reader.array_next(first, path):
		first = false
		var item_path := StringName("%s.%d" % [path, values.size()])
		var value := BossPhaseSnapshot.new()
		reader.begin_object(item_path)
		reader.read_key("phase_index", true, item_path)
		value.phase_index = reader.read_int(item_path)
		reader.read_key("hp_threshold_bps", false, item_path)
		value.hp_threshold_bps = reader.read_int(item_path)
		reader.read_key("source_instance_id", false, item_path)
		value.source_instance_id = StringName(reader.read_string(item_path))
		reader.read_key("effect_ids", false, item_path)
		value.effect_ids = _read_ids(reader, item_path)
		reader.end_object(item_path)
		values.append(value)
	return values

func _read_rules(reader: BattleCanonicalReader) -> BattleRulesSnapshot:
	var value := BattleRulesSnapshot.new()
	reader.begin_object(&"battle_rules")
	reader.read_key("simulation_version", true, &"battle_rules.simulation_version")
	value.simulation_version = reader.read_int(&"battle_rules.simulation_version")
	reader.read_key("event_codec_version", false, &"battle_rules.event_codec_version")
	value.event_codec_version = reader.read_int(&"battle_rules.event_codec_version")
	reader.read_key("result_codec_version", false, &"battle_rules.result_codec_version")
	value.result_codec_version = reader.read_int(&"battle_rules.result_codec_version")
	reader.read_key("combat_config_id", false, &"battle_rules.combat_config_id")
	value.combat_config_id = StringName(reader.read_string(&"battle_rules.combat_config_id"))
	value.tick_rate = _read_rule_int(reader, "tick_rate")
	value.board_width = _read_rule_int(reader, "board_width")
	value.board_height = _read_rule_int(reader, "board_height")
	value.soft_limit_ticks = _read_rule_int(reader, "soft_limit_ticks")
	value.hard_limit_ticks = _read_rule_int(reader, "hard_limit_ticks")
	value.progress_scale = _read_rule_int(reader, "progress_scale")
	value.resistance_base = _read_rule_int(reader, "resistance_base")
	value.basis_points = _read_rule_int(reader, "basis_points")
	value.overtime_interval_ticks = _read_rule_int(reader, "overtime_interval_ticks")
	value.main_actions_per_tick = _read_rule_int(reader, "main_actions_per_tick")
	value.attack_mana_gain = _read_rule_int(reader, "attack_mana_gain")
	value.damage_mana_factor = _read_rule_int(reader, "damage_mana_factor")
	value.damage_mana_min = _read_rule_int(reader, "damage_mana_min")
	value.damage_mana_max = _read_rule_int(reader, "damage_mana_max")
	value.overtime_step_bps = _read_rule_int(reader, "overtime_step_bps")
	value.overtime_cap_bps = _read_rule_int(reader, "overtime_cap_bps")
	value.act1_base_damage = _read_rule_int(reader, "act1_base_damage")
	value.act2_base_damage = _read_rule_int(reader, "act2_base_damage")
	value.act3_base_damage = _read_rule_int(reader, "act3_base_damage")
	value.survivor_damage = _read_rule_int(reader, "survivor_damage")
	value.boss_damage = _read_rule_int(reader, "boss_damage")
	value.effect_resolution_budget = _read_rule_int(reader, "effect_resolution_budget")
	value.operation_budget = _read_rule_int(reader, "operation_budget")
	value.event_budget = _read_rule_int(reader, "event_budget")
	value.entity_budget = _read_rule_int(reader, "entity_budget")
	value.act1_enemy_stat_bps = _read_rule_int(reader, "act1_enemy_stat_bps")
	value.act2_enemy_stat_bps = _read_rule_int(reader, "act2_enemy_stat_bps")
	value.act3_enemy_stat_bps = _read_rule_int(reader, "act3_enemy_stat_bps")
	value.act_index = _read_rule_int(reader, "act_index")
	reader.read_key("encounter_kind", false, &"battle_rules.encounter_kind")
	value.encounter_kind = StringName(reader.read_string(&"battle_rules.encounter_kind"))
	reader.read_key("ability_rules", false, &"battle_rules.ability_rules")
	value.ability_rules = _read_ability_rules(reader)
	reader.read_key("effect_rules", false, &"battle_rules.effect_rules")
	value.effect_rules = _read_effect_rules(reader)
	reader.read_key("summoned_unit_templates", false, &"battle_rules.summoned_unit_templates")
	value.summoned_unit_templates = _read_summoned_templates(reader)
	reader.end_object(&"battle_rules")
	return value

func _read_rule_int(reader: BattleCanonicalReader, key: String) -> int:
	var path := StringName("battle_rules.%s" % key)
	reader.read_key(key, false, path)
	return reader.read_int(path)

func _read_ability_rules(reader: BattleCanonicalReader) -> Array[BattleAbilityRuleSnapshot]:
	var values: Array[BattleAbilityRuleSnapshot] = []
	reader.begin_array(&"battle_rules.ability_rules")
	var first := true
	while reader.array_next(first, &"battle_rules.ability_rules"):
		first = false
		var path := StringName("battle_rules.ability_rules.%d" % values.size())
		var value := BattleAbilityRuleSnapshot.new()
		reader.begin_object(path)
		reader.read_key("ability_id", true, path)
		value.ability_id = StringName(reader.read_string(path))
		reader.read_key("target_rule", false, path)
		value.target_rule = StringName(reader.read_string(path))
		reader.read_key("cast_ticks", false, path)
		value.cast_ticks = reader.read_int(path)
		reader.read_key("effect_ids", false, path)
		value.effect_ids = _read_ids(reader, path)
		reader.end_object(path)
		values.append(value)
	return values

func _read_effect_rules(reader: BattleCanonicalReader) -> Array[BattleEffectRuleSnapshot]:
	var values: Array[BattleEffectRuleSnapshot] = []
	reader.begin_array(&"battle_rules.effect_rules")
	var first := true
	while reader.array_next(first, &"battle_rules.effect_rules"):
		first = false
		var path := StringName("battle_rules.effect_rules.%d" % values.size())
		var value := BattleEffectRuleSnapshot.new()
		reader.begin_object(path)
		reader.read_key("effect_id", true, path)
		value.effect_id = StringName(reader.read_string(path))
		reader.read_key("trigger", false, path)
		value.trigger = StringName(reader.read_string(path))
		reader.read_key("periodic_interval_ticks", false, path)
		value.periodic_interval_ticks = reader.read_int(path)
		reader.read_key("conditions", false, path)
		value.conditions = _read_conditions(reader, path)
		reader.read_key("battle_operations", false, path)
		value.battle_operations = _read_battle_operations(reader, path)
		reader.read_key("run_operations", false, path)
		value.run_operations = _read_run_operations(reader, path)
		reader.read_key("stacking", false, path)
		value.stacking = StringName(reader.read_string(path))
		reader.read_key("max_stacks", false, path)
		value.max_stacks = reader.read_int(path)
		reader.read_key("duration_ticks", false, path)
		value.duration_ticks = reader.read_int(path)
		reader.end_object(path)
		values.append(value)
	return values

func _read_conditions(reader: BattleCanonicalReader, parent_path: StringName) -> Array[BattleConditionRule]:
	var values: Array[BattleConditionRule] = []
	var path := StringName("%s.conditions" % parent_path)
	reader.begin_array(path)
	var first := true
	while reader.array_next(first, path):
		first = false
		var value := BattleConditionRule.new()
		reader.begin_object(path)
		reader.read_key("kind", true, path)
		value.kind = StringName(reader.read_string(path))
		reader.read_key("subject", false, path)
		value.subject = StringName(reader.read_string(path))
		reader.read_key("comparator", false, path)
		value.comparator = StringName(reader.read_string(path))
		reader.read_key("int_value", false, path)
		if reader.next_is_null(): reader.read_null(path)
		else: value.int_value = OptionalIntValue.new(reader.read_int(path))
		reader.read_key("stable_id_value", false, path)
		if reader.next_is_null(): reader.read_null(path)
		else: value.stable_id_value = OptionalStringNameValue.of(StringName(reader.read_string(path)))
		reader.read_key("max_uses_per_battle", false, path)
		if reader.next_is_null(): reader.read_null(path)
		else: value.max_uses_per_battle = OptionalIntValue.new(reader.read_int(path))
		reader.end_object(path)
		values.append(value)
	return values

func _read_battle_operations(reader: BattleCanonicalReader, parent_path: StringName) -> Array[BattleOperationRule]:
	var values: Array[BattleOperationRule] = []
	var path := StringName("%s.battle_operations" % parent_path)
	reader.begin_array(path)
	var first := true
	while reader.array_next(first, path):
		first = false
		var value := BattleOperationRule.new()
		reader.begin_object(path)
		reader.read_key("operation_index", true, path)
		value.operation_index = reader.read_int(path)
		reader.read_key("kind", false, path)
		value.kind = StringName(reader.read_string(path))
		match value.kind:
			&"damage":
				value.base_amount = _read_operation_int(reader, "base", path)
				value.scaling = _read_operation_name(reader, "scaling", path)
				value.damage_type = _read_operation_name(reader, "damage_type", path)
				value.target = _read_operation_name(reader, "target", path)
			&"heal":
				value.base_amount = _read_operation_int(reader, "base", path)
				value.scaling = _read_operation_name(reader, "scaling", path)
				value.target = _read_operation_name(reader, "target", path)
			&"shield":
				value.amount = _read_operation_int(reader, "amount", path)
				value.duration_ticks = _read_operation_int(reader, "duration_ticks", path)
				value.target = _read_operation_name(reader, "target", path)
			&"modify_stat":
				value.stat = _read_operation_name(reader, "stat", path)
				value.mode = _read_operation_name(reader, "mode", path)
				value.amount = _read_operation_int(reader, "amount", path)
				value.duration_ticks = _read_operation_int(reader, "duration_ticks", path)
				value.target = _read_operation_name(reader, "target", path)
			&"apply_status":
				value.status_id = OptionalStringNameValue.of(_read_operation_name(reader, "status_id", path))
				value.stacks = _read_operation_int(reader, "stacks", path)
				value.duration_ticks = _read_operation_int(reader, "duration_ticks", path)
				value.target = _read_operation_name(reader, "target", path)
			&"remove_status":
				value.status_id = OptionalStringNameValue.of(_read_operation_name(reader, "status_id", path))
				value.target = _read_operation_name(reader, "target", path)
			&"move":
				value.direction = _read_operation_name(reader, "direction", path)
				value.cells = _read_operation_int(reader, "cells", path)
			&"summon":
				value.unit_id = OptionalStringNameValue.of(_read_operation_name(reader, "unit_id", path))
				value.count = _read_operation_int(reader, "count", path)
				value.max_active_per_source = _read_operation_int(reader, "max_active_per_source", path)
				value.placement_rule = _read_operation_name(reader, "placement_rule", path)
			&"grant_mana":
				value.amount = _read_operation_int(reader, "amount", path)
				value.target = _read_operation_name(reader, "target", path)
		reader.end_object(path)
		values.append(value)
	return values

func _read_run_operations(reader: BattleCanonicalReader, parent_path: StringName) -> Array[BattleRunOperationRule]:
	var values: Array[BattleRunOperationRule] = []
	var path := StringName("%s.run_operations" % parent_path)
	reader.begin_array(path)
	var first := true
	while reader.array_next(first, path):
		first = false
		var value := BattleRunOperationRule.new()
		reader.begin_object(path)
		reader.read_key("operation_index", true, path)
		value.operation_index = reader.read_int(path)
		reader.read_key("kind", false, path)
		value.kind = StringName(reader.read_string(path))
		value.amount = _read_operation_int(reader, "amount", path)
		value.claim_scope = _read_operation_name(reader, "claim_scope", path)
		reader.end_object(path)
		values.append(value)
	return values

func _read_summoned_templates(reader: BattleCanonicalReader) -> Array[SummonedUnitRuleSnapshot]:
	var values: Array[SummonedUnitRuleSnapshot] = []
	var path := &"battle_rules.summoned_unit_templates"
	reader.begin_array(path)
	var first := true
	while reader.array_next(first, path):
		first = false
		var value := SummonedUnitRuleSnapshot.new()
		reader.begin_object(path)
		reader.read_key("unit_id", true, path)
		value.unit_id = StringName(reader.read_string(path))
		reader.read_key("star", false, path)
		value.star = reader.read_int(path)
		reader.read_key("trait_ids", false, path)
		value.trait_ids = _read_ids(reader, path)
		value.health = _read_operation_int(reader, "health", path)
		value.attack = _read_operation_int(reader, "attack", path)
		value.armor = _read_operation_int(reader, "armor", path)
		value.magic_resist = _read_operation_int(reader, "magic_resist", path)
		value.attack_speed_milli = _read_operation_int(reader, "attack_speed_milli", path)
		value.attack_range_cells = _read_operation_int(reader, "attack_range_cells", path)
		value.start_mana = _read_operation_int(reader, "start_mana", path)
		value.max_mana = _read_operation_int(reader, "max_mana", path)
		value.move_speed_milli = _read_operation_int(reader, "move_speed_milli", path)
		reader.read_key("ability_id", false, path)
		if reader.next_is_null(): reader.read_null(path)
		else: value.ability_id = OptionalStringNameValue.of(StringName(reader.read_string(path)))
		value.ai_profile = _read_operation_name(reader, "ai_profile", path)
		value.basic_attack_profile = _read_operation_name(reader, "basic_attack_profile", path)
		reader.read_key("unit_effect_assignments", false, path)
		value.unit_effect_assignments = _read_assignments(reader, path)
		reader.end_object(path)
		values.append(value)
	return values

func _read_assignments(reader: BattleCanonicalReader, parent_path: StringName) -> Array[UnitEffectAssignmentSnapshot]:
	var values: Array[UnitEffectAssignmentSnapshot] = []
	reader.begin_array(parent_path)
	var first := true
	while reader.array_next(first, parent_path):
		first = false
		var value := UnitEffectAssignmentSnapshot.new()
		reader.begin_object(parent_path)
		reader.read_key("priority", true, parent_path)
		value.priority = reader.read_int(parent_path)
		reader.read_key("source_stable_id", false, parent_path)
		value.source_stable_id = StringName(reader.read_string(parent_path))
		reader.read_key("effect_index", false, parent_path)
		value.effect_index = reader.read_int(parent_path)
		reader.read_key("effect_id", false, parent_path)
		value.effect_id = StringName(reader.read_string(parent_path))
		reader.end_object(parent_path)
		values.append(value)
	return values

func _read_operation_int(reader: BattleCanonicalReader, key: String, path: StringName) -> int:
	reader.read_key(key, false, path)
	return reader.read_int(path)

func _read_operation_name(reader: BattleCanonicalReader, key: String, path: StringName) -> StringName:
	reader.read_key(key, false, path)
	return StringName(reader.read_string(path))
