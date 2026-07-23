class_name ContentDefinitionCompiler
extends RefCounted

var _codec: ContentCanonicalCodecV1
var _content_codec_version: int
var _compile_error_path: StringName

func _init(
	p_codec: ContentCanonicalCodecV1 = null,
	p_content_codec_version: int = 1
) -> void:
	_codec = p_codec if p_codec != null else ContentCanonicalCodecV1.new()
	_content_codec_version = p_content_codec_version

func compile(definition: ContentDefinition) -> ContentEntryCompileResult:
	_compile_error_path = &""
	if definition == null or definition.schema_version != 1:
		return ContentEntryCompileResult.failure(&"schema_version")
	var category := definition.category_name()
	var type_id := ContentCategory.code_for_name(category)
	if type_id == 0:
		return ContentEntryCompileResult.failure(&"category", definition.id)
	var common: Array[ContentValue] = [
		ContentValue.text(String(definition.display_name_key)),
		_stable_set(definition.unlock_refs),
		_path_set(definition.asset_refs)
	]
	var specifics := _compile_specifics(definition)
	if not _compile_error_path.is_empty():
		return ContentEntryCompileResult.failure(_compile_error_path, definition.id)
	if specifics.is_empty() and not (definition is ItemComponentDef):
		return ContentEntryCompileResult.failure(&"payload", definition.id)
	var all_values: Array[ContentValue] = []
	all_values.append_array(common)
	all_values.append_array(specifics)
	var field_ids := PackedInt32Array([1, 2, 3])
	for index in specifics.size():
		field_ids.append(0x0100 + index)
	var entry := ContentEntryValue.new(category, definition.id, definition.schema_version, ContentValue.record(type_id, field_ids, all_values))
	var encoded := _codec.encode_entry(entry)
	if not encoded.ok:
		return ContentEntryCompileResult.failure(&"payload.codec", definition.id)
	return ContentEntryCompileResult.success(entry)

func collect_references(definition: ContentDefinition) -> Array[StringName]:
	var result: Array[StringName] = definition.unlock_refs.duplicate()
	if definition is UnitDef:
		result.append_array(definition.trait_refs)
		if definition.has_ability_ref: result.append(definition.ability_ref)
		if _content_codec_version == 2: result.append_array(definition.effect_refs)
	elif definition is TraitDef:
		for threshold in definition.thresholds: result.append_array(threshold.effect_refs)
	elif definition is AbilityDef:
		result.append_array(definition.effect_refs)
	elif definition is EffectDef:
		for condition in definition.conditions:
			if condition.has_stable_id_value:
				result.append(condition.stable_id_value)
		for operation in definition.battle_operations:
			if operation is SummonOperationDef: result.append(operation.unit_ref)
			elif operation is ApplyStatusOperationDef: result.append(operation.status_id)
			elif operation is RemoveStatusOperationDef: result.append(operation.status_id)
		for operation in definition.run_operations:
			if operation is ModifyUnitPoolOperationDef: result.append(operation.unit_ref)
			elif operation is GrantItemOperationDef: result.append(operation.content_ref)
			elif operation is GrantRelicOperationDef: result.append(operation.relic_ref)
	elif definition is EquipmentDef:
		result.append_array(definition.component_pair)
		result.append_array(definition.effect_refs)
	elif definition is ConsumableDef:
		_append_run_operation_refs(result, definition.run_operations)
	elif definition is RelicDef:
		result.append_array(definition.effect_refs)
	elif definition is CommanderDef:
		for item in definition.starting_pack: result.append(item.content_id)
		result.append_array(definition.passive_effect_refs)
	elif definition is EncounterDef:
		for spawn in definition.enemy_spawns:
			result.append(spawn.unit_ref)
			result.append_array(spawn.effect_refs)
		result.append_array(definition.affix_refs)
		for phase in definition.boss_phases: result.append_array(phase.effect_refs)
	elif definition is RewardTableDef:
		for candidate in definition.reward_candidates:
			if candidate.has_content_ref: result.append(candidate.content_ref)
	elif definition is MapNodeDef:
		result.append(definition.generator_ref)
		_append_run_operation_refs(result, definition.enter_operations)
		_append_run_operation_refs(result, definition.exit_operations)
	elif definition is UnlockDef:
		result.append_array(definition.prerequisite_refs)
		result.append_array(definition.unlocked_content_refs)
		result.append_array(definition.modifier_refs)
	result.sort_custom(_string_name_less)
	var unique: Array[StringName] = []
	for value in result:
		if unique.is_empty() or unique[-1] != value: unique.append(value)
	return unique

func _append_run_operation_refs(result: Array[StringName], operations: Array[RunOperationDef]) -> void:
	for operation in operations:
		if operation is ModifyUnitPoolOperationDef: result.append(operation.unit_ref)
		elif operation is GrantItemOperationDef: result.append(operation.content_ref)
		elif operation is GrantRelicOperationDef: result.append(operation.relic_ref)

func _compile_specifics(definition: ContentDefinition) -> Array[ContentValue]:
	if definition is UnitDef: return _compile_unit(definition)
	if definition is TraitDef: return [ContentValue.enum_value(definition.trait_kind), ContentValue.enum_value(definition.member_rule), _trait_threshold_set(definition.thresholds), ContentValue.text(String(definition.description_key))]
	if definition is AbilityDef: return [ContentValue.i32(definition.start_mana), ContentValue.i32(definition.max_mana), ContentValue.enum_value(definition.target_rule), ContentValue.u32(definition.cast_ticks), _stable_list(definition.effect_refs), ContentValue.text(String(definition.description_key))]
	if definition is EffectDef: return _compile_effect(definition)
	if definition is ItemComponentDef: return [ContentValue.text(definition.recipe_key), ContentValue.u32(definition.sort_order)]
	if definition is EquipmentDef: return [
		_stable_set(definition.component_pair), _stat_modifier_set(definition.stat_modifiers), _stable_list(definition.effect_refs),
		ContentValue.optional(ContentValue.stable_id(definition.unique_group) if definition.has_unique_group else null)]
	if definition is ConsumableDef: return [ContentValue.enum_value(definition.use_timing), _run_operation_list(definition.run_operations, &"run_operations"), ContentValue.u32(definition.stack_limit)]
	if definition is RelicDef: return [ContentValue.enum_value(definition.category), _stable_list(definition.effect_refs), ContentValue.u32(definition.activation_limit), ContentValue.i32(definition.population_bonus)]
	if definition is CommanderDef: return [_content_amount_set(definition.starting_pack), _stable_list(definition.passive_effect_refs), _weighted_enum_set(definition.route_preferences), ContentValue.i32(definition.population_bonus)]
	if definition is EncounterDef: return [ContentValue.enum_value(definition.encounter_kind), ContentValue.u32(definition.preview_schema_version), _enemy_spawn_set(definition.enemy_spawns), _stable_set(definition.affix_refs), _boss_phase_list(definition.boss_phases)]
	if definition is RewardTableDef: return [_reward_candidate_set(definition.reward_candidates), ContentValue.u32(definition.draw_count)]
	if definition is MapNodeDef: return [ContentValue.enum_value(definition.node_type), ContentValue.stable_id(definition.generator_ref), _run_operation_list(definition.enter_operations, &"enter_operations"), _run_operation_list(definition.exit_operations, &"exit_operations")]
	if definition is UnlockDef: return [ContentValue.enum_value(definition.unlock_kind), ContentValue.u32(definition.challenge_level), _stable_set(definition.prerequisite_refs), ContentValue.u32(definition.currency_cost), _stable_set(definition.unlocked_content_refs), _stable_set(definition.modifier_refs)]
	if definition is EconomyConfigDef: return _compile_economy(definition)
	if definition is MetaRewardTableDef: return [_enum_int_set(definition.node_scores), ContentValue.i32(definition.completion_reward), ContentValue.i32(definition.failure_reward), _challenge_multiplier_set(definition.challenge_multiplier_bps)]
	if definition is CombatConfigDef and _content_codec_version == 2:
		return _compile_combat_config(definition)
	return []

func _compile_unit(value: UnitDef) -> Array[ContentValue]:
	var stats: ContentValue = null
	if value.base_stats != null: stats = _unit_stats(value.base_stats)
	if stats == null: return []
	var result: Array[ContentValue] = [
		ContentValue.u32(value.cost_tier), _stable_set(value.trait_refs), stats,
		_star_scaling_set(value.star_scalings),
		ContentValue.optional(ContentValue.stable_id(value.ability_ref) if value.has_ability_ref else null),
		ContentValue.enum_value(value.ai_profile), ContentValue.enum_value(value.basic_attack_profile),
		ContentValue.enum_value(value.availability), ContentValue.enum_value(value.shop_condition)
	]
	if _content_codec_version == 2:
		result.append(_stable_list(value.effect_refs))
	return result

func _compile_effect(value: EffectDef) -> Array[ContentValue]:
	if _content_codec_version == 2:
		return [
			ContentValue.enum_value(value.content_role),
			ContentValue.enum_value(value.trigger),
			ContentValue.u32(value.periodic_interval_ticks),
			_condition_set(value.conditions),
			_battle_operation_list(value.battle_operations, &"battle_operations"),
			_run_operation_list(value.run_operations, &"run_operations"),
			ContentValue.enum_value(value.stacking),
			ContentValue.u32(value.max_stacks),
			ContentValue.u32(value.duration_ticks),
		]
	return [ContentValue.enum_value(value.content_role), ContentValue.enum_value(value.trigger), _condition_set(value.conditions),
		_battle_operation_list(value.battle_operations, &"battle_operations"), _run_operation_list(value.run_operations, &"run_operations"),
		ContentValue.enum_value(value.stacking), ContentValue.u32(value.max_stacks), ContentValue.u32(value.duration_ticks)]

func _compile_economy(value: EconomyConfigDef) -> Array[ContentValue]:
	return [_u32_pair_set(value.layer_income), ContentValue.u32(value.interest_step_gold), ContentValue.u32(value.interest_per_step),
		ContentValue.u32(value.max_interest), ContentValue.u32(value.gold_cap), ContentValue.u32(value.reroll_cost),
		ContentValue.u32(value.xp_buy_cost), ContentValue.u32(value.xp_buy_amount), _u32_pair_set(value.streak_rewards),
		_u32_pair_set(value.loss_subsidy), _shop_odds_set(value.shop_odds_by_level), _u32_pair_set(value.pool_copies_by_tier),
		_u32_pair_set(value.unit_costs_by_tier), _u32_pair_set(value.xp_thresholds)]

func _compile_combat_config(value: CombatConfigDef) -> Array[ContentValue]:
	return [
		ContentValue.u32(value.simulation_version),
		ContentValue.u32(value.tick_rate),
		ContentValue.u32(value.board_width),
		ContentValue.u32(value.board_height),
		ContentValue.u32(value.soft_limit_ticks),
		ContentValue.u32(value.hard_limit_ticks),
		ContentValue.u32(value.progress_scale),
		ContentValue.u32(value.resistance_base),
		ContentValue.u32(value.basis_points),
		ContentValue.u32(value.overtime_interval_ticks),
		ContentValue.u32(value.main_actions_per_tick),
		ContentValue.u32(value.attack_mana_gain),
		ContentValue.u32(value.damage_mana_factor),
		ContentValue.u32(value.damage_mana_min),
		ContentValue.u32(value.damage_mana_max),
		ContentValue.u32(value.overtime_step_bps),
		ContentValue.u32(value.overtime_cap_bps),
		ContentValue.u32(value.act1_base_damage),
		ContentValue.u32(value.act2_base_damage),
		ContentValue.u32(value.act3_base_damage),
		ContentValue.u32(value.survivor_damage),
		ContentValue.u32(value.boss_damage),
		ContentValue.u32(value.effect_resolution_budget),
		ContentValue.u32(value.operation_budget),
		ContentValue.u32(value.event_budget),
		ContentValue.u32(value.entity_budget),
	]

func _unit_stats(value: UnitStatsDef) -> ContentValue:
	return _record(0x2000, [ContentValue.i32(value.health), ContentValue.i32(value.attack), ContentValue.i32(value.armor),
		ContentValue.i32(value.magic_resist), ContentValue.i32(value.attack_speed_milli), ContentValue.i32(value.attack_range_cells),
		ContentValue.i32(value.start_mana), ContentValue.i32(value.max_mana), ContentValue.i32(value.move_speed_milli)])

func _star_scaling(value: StarScalingDef) -> ContentValue:
	return _record(0x200f, [ContentValue.u32(value.star), ContentValue.u32(value.health_bps), ContentValue.u32(value.attack_bps),
		ContentValue.u32(value.armor_bps), ContentValue.u32(value.magic_resist_bps), ContentValue.u32(value.attack_speed_bps),
		ContentValue.u32(value.attack_range_bps), ContentValue.u32(value.start_mana_bps), ContentValue.u32(value.max_mana_bps), ContentValue.u32(value.move_speed_bps)])

func _condition(value: ConditionDef) -> ContentValue:
	return _record(0x2002, [ContentValue.enum_value(value.kind), ContentValue.enum_value(value.subject), ContentValue.enum_value(value.comparator),
		ContentValue.optional(ContentValue.i32(value.int_value) if value.has_int_value else null),
		ContentValue.optional(ContentValue.stable_id(value.stable_id_value) if value.has_stable_id_value else null),
		ContentValue.optional(ContentValue.u32(value.max_uses_per_battle) if value.has_max_uses_per_battle else null)])

func _battle_operation(value: BattleOperationDef) -> ContentValue:
	var fields: Array[ContentValue] = [ContentValue.u32(value.operation_index)]
	if value is DamageOperationDef: fields.append_array([ContentValue.i32(value.base), ContentValue.enum_value(value.scaling), ContentValue.enum_value(value.damage_type), ContentValue.enum_value(value.target)])
	elif value is HealOperationDef: fields.append_array([ContentValue.i32(value.base), ContentValue.enum_value(value.scaling), ContentValue.enum_value(value.target)])
	elif value is ShieldOperationDef: fields.append_array([ContentValue.i32(value.amount), ContentValue.u32(value.duration_ticks), ContentValue.enum_value(value.target)])
	elif value is ModifyStatOperationDef: fields.append_array([ContentValue.enum_value(value.stat), ContentValue.enum_value(value.mode), ContentValue.i32(value.amount), ContentValue.u32(value.duration_ticks), ContentValue.enum_value(value.target)])
	elif value is ApplyStatusOperationDef: fields.append_array([ContentValue.stable_id(value.status_id), ContentValue.u32(value.stacks), ContentValue.u32(value.duration_ticks), ContentValue.enum_value(value.target)])
	elif value is RemoveStatusOperationDef: fields.append_array([ContentValue.stable_id(value.status_id), ContentValue.enum_value(value.target)])
	elif value is MoveOperationDef: fields.append_array([ContentValue.enum_value(value.direction_or_target), ContentValue.u32(value.cells)])
	elif value is SummonOperationDef: fields.append_array([ContentValue.stable_id(value.unit_ref), ContentValue.u32(value.count), ContentValue.u32(value.max_active_per_source), ContentValue.enum_value(value.placement_rule)])
	elif value is GrantManaOperationDef: fields.append_array([ContentValue.i32(value.amount), ContentValue.enum_value(value.target)])
	else: return null
	return _operation_record(value.operation_type(), fields)

func _run_operation(value: RunOperationDef) -> ContentValue:
	var fields: Array[ContentValue] = [ContentValue.u32(value.operation_index)]
	if value is AddGoldOperationDef: fields.append_array([ContentValue.i32(value.amount), ContentValue.enum_value(value.claim_scope)])
	elif value is AddXpOperationDef: fields.append_array([ContentValue.i32(value.amount), ContentValue.enum_value(value.claim_scope)])
	elif value is HealExpeditionHpOperationDef: fields.append_array([ContentValue.i32(value.amount), ContentValue.enum_value(value.claim_scope)])
	elif value is ShopDiscountOperationDef: fields.append_array([ContentValue.i32(value.amount), ContentValue.enum_value(value.claim_scope)])
	elif value is ModifyUnitPoolOperationDef: fields.append_array([ContentValue.stable_id(value.unit_ref), ContentValue.i32(value.count)])
	elif value is GrantItemOperationDef: fields.append_array([ContentValue.stable_id(value.content_ref), ContentValue.u32(value.count)])
	elif value is GrantRelicOperationDef: fields.append(ContentValue.stable_id(value.relic_ref))
	elif value is PopulationSourceOperationDef: fields.append_array([ContentValue.stable_id(value.source_id), ContentValue.i32(value.amount)])
	else: return null
	return _operation_record(value.operation_type(), fields)

func _record(type_id: int, values: Array[ContentValue]) -> ContentValue:
	var ids := PackedInt32Array()
	for index in values.size(): ids.append(index + 1)
	return ContentValue.record(type_id, ids, values)

func _operation_record(type_id: int, values: Array[ContentValue]) -> ContentValue:
	var ids := PackedInt32Array([1])
	for index in range(1, values.size()): ids.append(0x0100 + index - 1)
	return ContentValue.record(type_id, ids, values)

func _stable_list(values: Array[StringName]) -> ContentValue:
	var result: Array[ContentValue] = []
	for value in values: result.append(ContentValue.stable_id(value))
	return ContentValue.ordered_list(result)

func _stable_set(values: Array[StringName]) -> ContentValue:
	var result: Array[ContentValue] = []
	for value in values: result.append(ContentValue.stable_id(value))
	return _canonical_set(result)

func _path_set(values: Array[String]) -> ContentValue:
	var result: Array[ContentValue] = []
	for value in values: result.append(ContentValue.path(value))
	return _canonical_set(result)

func _star_scaling_set(values: Array[StarScalingDef]) -> ContentValue:
	var result: Array[ContentValue] = []
	for value in values: result.append(_star_scaling(value))
	return _canonical_set(result)

func _trait_threshold_set(values: Array[TraitThresholdDef]) -> ContentValue:
	var result: Array[ContentValue] = []
	for value in values: result.append(_record(0x2001, [ContentValue.u32(value.required_count), _stable_list(value.effect_refs)]))
	return _canonical_set(result)

func _condition_set(values: Array[ConditionDef]) -> ContentValue:
	var result: Array[ContentValue] = []
	for value in values: result.append(_condition(value))
	return _canonical_set(result)

func _stat_modifier_set(values: Array[StatModifierDef]) -> ContentValue:
	var result: Array[ContentValue] = []
	for value in values: result.append(_record(0x2003, [ContentValue.enum_value(value.stat), ContentValue.enum_value(value.mode), ContentValue.i32(value.amount_i32)]))
	return _canonical_set(result)

func _content_amount_set(values: Array[ContentAmountDef]) -> ContentValue:
	var result: Array[ContentValue] = []
	for value in values: result.append(_record(0x2004, [ContentValue.stable_id(value.content_id), ContentValue.u32(value.count_u32)]))
	return _canonical_set(result)

func _weighted_enum_set(values: Array[WeightedEnumDef]) -> ContentValue:
	var result: Array[ContentValue] = []
	for value in values: result.append(_record(0x2005, [ContentValue.enum_value(value.enum_key), ContentValue.i32(value.weight_i32)]))
	return _canonical_set(result)

func _enemy_spawn_set(values: Array[EnemySpawnDef]) -> ContentValue:
	var result: Array[ContentValue] = []
	for value in values: result.append(_record(0x2006, [ContentValue.enum_value(value.side), ContentValue.i32(value.logical_y), ContentValue.i32(value.logical_x), ContentValue.text(value.spawn_key), ContentValue.stable_id(value.unit_ref), ContentValue.u32(value.star), _stable_list(value.effect_refs)]))
	return _canonical_set(result)

func _boss_phase_list(values: Array[BossPhaseDef]) -> ContentValue:
	var result: Array[ContentValue] = []
	for value in values:
		if _content_codec_version == 2:
			result.append(_record(0x2007, [
				ContentValue.u32(value.phase_index),
				ContentValue.u32(value.hp_threshold_bps),
				ContentValue.text(value.source_spawn_key),
				_stable_list(value.effect_refs),
			]))
		else:
			result.append(_record(0x2007, [
				ContentValue.u32(value.phase_index),
				ContentValue.u32(value.hp_threshold_bps),
				_stable_list(value.effect_refs),
			]))
	return ContentValue.ordered_list(result)

func _reward_candidate_set(values: Array[RewardCandidateDef]) -> ContentValue:
	var result: Array[ContentValue] = []
	for value in values: result.append(_record(0x2008, [ContentValue.enum_value(value.kind), ContentValue.optional(ContentValue.stable_id(value.content_ref) if value.has_content_ref else null), ContentValue.i32(value.weight_i32), _condition_set(value.conditions)]))
	return _canonical_set(result)

func _u32_pair_set(values: Array[U32PairDef]) -> ContentValue:
	var result: Array[ContentValue] = []
	for value in values: result.append(_record(0x200e, [ContentValue.u32(value.key_u32), ContentValue.u32(value.value_u32)]))
	return _canonical_set(result)

func _shop_odds_set(values: Array[ShopOddsRowDef]) -> ContentValue:
	var result: Array[ContentValue] = []
	for value in values:
		var odds: Array[ContentValue] = []
		for item in value.tier_basis_points: odds.append(ContentValue.u32(item))
		result.append(_record(0x200a, [ContentValue.u32(value.level), ContentValue.ordered_list(odds)]))
	return _canonical_set(result)

func _enum_int_set(values: Array[EnumIntPairDef]) -> ContentValue:
	var result: Array[ContentValue] = []
	for value in values: result.append(_record(0x200b, [ContentValue.enum_value(value.enum_key), ContentValue.i32(value.value_i32)]))
	return _canonical_set(result)

func _challenge_multiplier_set(values: Array[ChallengeMultiplierDef]) -> ContentValue:
	var result: Array[ContentValue] = []
	for value in values: result.append(_record(0x200c, [ContentValue.u32(value.challenge_level), ContentValue.u32(value.basis_points)]))
	return _canonical_set(result)

func _battle_operation_list(values: Array[BattleOperationDef], field_path: StringName) -> ContentValue:
	var result: Array[ContentValue] = []
	for value in values:
		if value == null:
			_set_compile_error(StringName("%s.unknown_type" % String(field_path)))
			return ContentValue.ordered_list(result)
		var compiled := _battle_operation(value)
		if compiled == null:
			_set_compile_error(StringName("%s.unknown_type" % String(field_path)))
			return ContentValue.ordered_list(result)
		result.append(compiled)
	return ContentValue.ordered_list(result)

func _run_operation_list(values: Array[RunOperationDef], field_path: StringName) -> ContentValue:
	var result: Array[ContentValue] = []
	for value in values:
		if value == null:
			_set_compile_error(StringName("%s.unknown_type" % String(field_path)))
			return ContentValue.ordered_list(result)
		var compiled := _run_operation(value)
		if compiled == null:
			_set_compile_error(StringName("%s.unknown_type" % String(field_path)))
			return ContentValue.ordered_list(result)
		result.append(compiled)
	return ContentValue.ordered_list(result)

func _set_compile_error(field_path: StringName) -> void:
	if _compile_error_path.is_empty(): _compile_error_path = field_path

func _canonical_set(values: Array[ContentValue]) -> ContentValue:
	values.sort_custom(_value_less)
	return ContentValue.canonical_set(values)

func _value_less(left: ContentValue, right: ContentValue) -> bool:
	var left_result := _codec.encode_value_for_sort(left)
	var right_result := _codec.encode_value_for_sort(right)
	if not left_result.ok or not right_result.ok: return false
	return left_result.canonical_bytes.hex_encode() < right_result.canonical_bytes.hex_encode()

func _string_name_less(left: StringName, right: StringName) -> bool:
	return String(left) < String(right)
