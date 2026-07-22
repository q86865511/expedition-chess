class_name BattleRuleCatalogBuilder
extends RefCounted

var _error: BattleRuleCatalogError

func build(
	registry: ContentRegistryService,
	manifest_digest: String,
	required_ids: Array[StringName]
) -> BattleRuleCatalogBuildResult:
	_error = null
	if registry == null or not ContentRef.new(manifest_digest, &"config.combat_default").is_valid():
		return BattleRuleCatalogBuildResult.failure(
			BattleRuleCatalogError.INPUT_INVALID,
			&"manifest_digest"
		)
	var pending: Array[StringName] = required_ids.duplicate()
	if not pending.has(&"config.combat_default"):
		pending.append(&"config.combat_default")
	var seen: Dictionary = {}
	var units: Array[BattleUnitRule] = []
	var traits: Array[BattleTraitRule] = []
	var abilities: Array[BattleAbilityRule] = []
	var effects: Array[BattleEffectRule] = []
	var encounters: Array[BattleEncounterRule] = []
	var equipment: Array[BattleEquipmentRule] = []
	var configs: Array[BattleCombatConfigRule] = []
	var relics: Array[BattleRelicRule] = []
	while not pending.is_empty():
		pending.sort_custom(_name_less)
		var content_id: StringName = pending.pop_front()
		if seen.has(content_id):
			continue
		if not StableIdValidator.new().is_valid(content_id):
			return BattleRuleCatalogBuildResult.failure(
				BattleRuleCatalogError.INPUT_INVALID,
				&"required_ids",
				content_id
			)
		seen[content_id] = true
		var resolved := registry.resolve(ContentRef.new(manifest_digest, content_id))
		if not resolved.ok:
			return BattleRuleCatalogBuildResult.failure(
				BattleRuleCatalogError.RESOLVE_FAILED,
				resolved.error.field_path,
				content_id
			)
		var view: ContentDefinitionView = resolved.value
		match view.category:
			&"unit":
				var unit := _decode_unit(view)
				if unit == null: return _current_failure(content_id)
				units.append(unit)
				_append_names(pending, unit.trait_ids)
				if unit.ability_id != null: pending.append(unit.ability_id.value)
				_append_names(pending, unit.effect_ids)
			&"trait":
				var trait_rule := _decode_trait(view)
				if trait_rule == null: return _current_failure(content_id)
				traits.append(trait_rule)
				for threshold: BattleTraitThresholdRule in trait_rule.thresholds:
					_append_names(pending, threshold.effect_ids)
			&"ability":
				var ability := _decode_ability(view)
				if ability == null: return _current_failure(content_id)
				abilities.append(ability)
				_append_names(pending, ability.effect_ids)
			&"effect":
				var effect := _decode_effect(view)
				if effect == null: return _current_failure(content_id)
				effects.append(effect)
				_append_effect_references(pending, effect)
			&"encounter":
				var encounter := _decode_encounter(view)
				if encounter == null: return _current_failure(content_id)
				encounters.append(encounter)
				for spawn: BattleEnemySpawnRule in encounter.enemy_spawns:
					pending.append(spawn.unit_id)
					_append_names(pending, spawn.effect_ids)
				_append_names(pending, encounter.affix_ids)
				for phase: BattleBossPhaseRule in encounter.boss_phases:
					_append_names(pending, phase.effect_ids)
			&"equipment":
				var item := _decode_equipment(view)
				if item == null: return _current_failure(content_id)
				equipment.append(item)
				_append_names(pending, item.effect_ids)
			&"combat_config":
				var config := _decode_config(view)
				if config == null: return _current_failure(content_id)
				configs.append(config)
			&"relic":
				var relic_rule := _decode_relic(view)
				if relic_rule == null: return _current_failure(content_id)
				relics.append(relic_rule)
				_append_names(pending, relic_rule.battle_effect_ids)
			_:
				return BattleRuleCatalogBuildResult.failure(
					BattleRuleCatalogError.CATEGORY_MISMATCH,
					&"category",
					content_id
				)
	if configs.size() != 1 or configs[0].config_id != &"config.combat_default":
		return BattleRuleCatalogBuildResult.failure(
			BattleRuleCatalogError.CONFIG_MISSING,
			&"config.combat_default"
		)
	units.sort_custom(_unit_less)
	traits.sort_custom(_trait_less)
	abilities.sort_custom(_ability_less)
	effects.sort_custom(_effect_less)
	encounters.sort_custom(_encounter_less)
	equipment.sort_custom(_equipment_less)
	relics.sort_custom(_relic_less)
	return BattleRuleCatalogBuildResult.success(BattleRuleCatalog.new(
		manifest_digest, units, traits, abilities, effects, encounters, equipment, configs, relics
	))

func _decode_unit(view: ContentDefinitionView) -> BattleUnitRule:
	if not _payload_is(view, ContentCategory.UNIT, 13): return null
	var children: Array[ContentValue] = view.payload.children
	var result := BattleUnitRule.new()
	result.unit_id = view.content_id
	result.cost_tier = children[3].int_value
	result.trait_ids = _names(children[4])
	result.base_stats = _decode_stats(children[5])
	if result.base_stats == null: return null
	for value: ContentValue in children[6].children:
		var scaling := _decode_star_scaling(value)
		if scaling == null: return null
		result.star_scalings.append(scaling)
	var optional: ContentValue = children[7]
	if optional.optional_present:
		result.ability_id = OptionalStringNameValue.of(StringName(optional.children[0].string_value))
	result.ai_profile = StringName(children[8].string_value)
	result.basic_attack_profile = StringName(children[9].string_value)
	result.availability = StringName(children[10].string_value)
	result.shop_condition = StringName(children[11].string_value)
	result.effect_ids = _names(children[12])
	return result

func _decode_trait(view: ContentDefinitionView) -> BattleTraitRule:
	if not _payload_is(view, ContentCategory.TRAIT, 7): return null
	var result := BattleTraitRule.new()
	result.trait_id = view.content_id
	result.trait_kind = StringName(view.payload.children[3].string_value)
	result.member_rule = StringName(view.payload.children[4].string_value)
	for value: ContentValue in view.payload.children[5].children:
		if value.record_type != 0x2001 or value.children.size() != 2:
			return _payload_failure(&"trait.thresholds")
		var threshold := BattleTraitThresholdRule.new()
		threshold.required_count = value.children[0].int_value
		threshold.effect_ids = _names(value.children[1])
		result.thresholds.append(threshold)
	return result

func _decode_ability(view: ContentDefinitionView) -> BattleAbilityRule:
	if not _payload_is(view, ContentCategory.ABILITY, 9): return null
	var children: Array[ContentValue] = view.payload.children
	var result := BattleAbilityRule.new()
	result.ability_id = view.content_id
	result.start_mana = children[3].int_value
	result.max_mana = children[4].int_value
	result.target_rule = StringName(children[5].string_value)
	result.cast_ticks = children[6].int_value
	result.effect_ids = _names(children[7])
	return result

func _decode_effect(view: ContentDefinitionView) -> BattleEffectRule:
	if not _payload_is(view, ContentCategory.EFFECT, 12): return null
	var children: Array[ContentValue] = view.payload.children
	var result := BattleEffectRule.new()
	result.effect_id = view.content_id
	result.content_role = StringName(children[3].string_value)
	result.trigger = StringName(children[4].string_value)
	result.periodic_interval_ticks = children[5].int_value
	for value: ContentValue in children[6].children:
		var condition := _decode_condition(value)
		if condition == null: return null
		result.conditions.append(condition)
	for value: ContentValue in children[7].children:
		var operation := _decode_battle_operation(value)
		if operation == null: return null
		result.battle_operations.append(operation)
	for value: ContentValue in children[8].children:
		var run_operation := _decode_run_operation(value)
		if run_operation == null: return null
		result.run_operations.append(run_operation)
	result.stacking = StringName(children[9].string_value)
	result.max_stacks = children[10].int_value
	result.duration_ticks = children[11].int_value
	return result

func _decode_encounter(view: ContentDefinitionView) -> BattleEncounterRule:
	if not _payload_is(view, ContentCategory.ENCOUNTER, 8): return null
	var children: Array[ContentValue] = view.payload.children
	var result := BattleEncounterRule.new()
	result.encounter_id = view.content_id
	result.encounter_kind = StringName(children[3].string_value)
	result.preview_schema_version = children[4].int_value
	for value: ContentValue in children[5].children:
		if value.record_type != 0x2006 or value.children.size() != 7:
			return _payload_failure(&"encounter.enemy_spawns")
		var spawn := BattleEnemySpawnRule.new()
		spawn.side = StringName(value.children[0].string_value)
		spawn.logical_y = value.children[1].int_value
		spawn.logical_x = value.children[2].int_value
		spawn.spawn_key = value.children[3].string_value
		spawn.unit_id = StringName(value.children[4].string_value)
		spawn.star = value.children[5].int_value
		spawn.effect_ids = _names(value.children[6])
		result.enemy_spawns.append(spawn)
	result.affix_ids = _names(children[6])
	for value: ContentValue in children[7].children:
		if value.record_type != 0x2007 or value.children.size() != 4:
			return _payload_failure(&"encounter.boss_phases")
		var phase := BattleBossPhaseRule.new()
		phase.phase_index = value.children[0].int_value
		phase.hp_threshold_bps = value.children[1].int_value
		phase.source_spawn_key = value.children[2].string_value
		phase.effect_ids = _names(value.children[3])
		result.boss_phases.append(phase)
	return result

func _decode_equipment(view: ContentDefinitionView) -> BattleEquipmentRule:
	if not _payload_is(view, ContentCategory.EQUIPMENT, 7): return null
	var children: Array[ContentValue] = view.payload.children
	var result := BattleEquipmentRule.new()
	result.equipment_id = view.content_id
	for value: ContentValue in children[4].children:
		if value.record_type != 0x2003 or value.children.size() != 3:
			return _payload_failure(&"equipment.stat_modifiers")
		var modifier := BattleStatModifierRule.new()
		modifier.stat = StringName(value.children[0].string_value)
		modifier.mode = StringName(value.children[1].string_value)
		modifier.amount = value.children[2].int_value
		result.stat_modifiers.append(modifier)
	result.effect_ids = _names(children[5])
	if children[6].optional_present:
		result.unique_group = OptionalStringNameValue.of(StringName(children[6].children[0].string_value))
	return result

func _decode_relic(view: ContentDefinitionView) -> BattleRelicRule:
	if not _payload_is(view, ContentCategory.RELIC, 7): return null
	var children: Array[ContentValue] = view.payload.children
	var category := StringName(children[3].string_value)
	if category != &"battle":
		_error = BattleRuleCatalogError.new(
			BattleRuleCatalogError.CATEGORY_MISMATCH,
			&"relic.category",
			view.content_id
		)
		return null
	var result := BattleRelicRule.new()
	result.relic_id = view.content_id
	result.battle_effect_ids = _names(children[4])
	return result

func _decode_config(view: ContentDefinitionView) -> BattleCombatConfigRule:
	if not _payload_is(view, ContentCategory.COMBAT_CONFIG, 29): return null
	var result := BattleCombatConfigRule.new()
	result.config_id = view.content_id
	var properties := BattleCombatConfigRule._integer_properties()
	for index: int in range(properties.size()):
		result.set(properties[index], view.payload.children[index + 3].int_value)
	return result

func _decode_stats(value: ContentValue) -> BattleUnitStatsRule:
	if value == null or value.record_type != 0x2000 or value.children.size() != 9:
		return _payload_failure(&"unit.base_stats")
	var result := BattleUnitStatsRule.new()
	result.health = value.children[0].int_value
	result.attack = value.children[1].int_value
	result.armor = value.children[2].int_value
	result.magic_resist = value.children[3].int_value
	result.attack_speed_milli = value.children[4].int_value
	result.attack_range_cells = value.children[5].int_value
	result.start_mana = value.children[6].int_value
	result.max_mana = value.children[7].int_value
	result.move_speed_milli = value.children[8].int_value
	return result

func _decode_star_scaling(value: ContentValue) -> BattleStarScalingRule:
	if value == null or value.record_type != 0x200f or value.children.size() != 10:
		return _payload_failure(&"unit.star_scalings")
	var result := BattleStarScalingRule.new()
	result.star = value.children[0].int_value
	result.health_bps = value.children[1].int_value
	result.attack_bps = value.children[2].int_value
	result.armor_bps = value.children[3].int_value
	result.magic_resist_bps = value.children[4].int_value
	result.attack_speed_bps = value.children[5].int_value
	result.attack_range_bps = value.children[6].int_value
	result.start_mana_bps = value.children[7].int_value
	result.max_mana_bps = value.children[8].int_value
	result.move_speed_bps = value.children[9].int_value
	return result

func _decode_condition(value: ContentValue) -> BattleConditionRule:
	if value == null or value.record_type != 0x2002 or value.children.size() != 6:
		return _payload_failure(&"effect.conditions")
	var result := BattleConditionRule.new()
	result.kind = StringName(value.children[0].string_value)
	result.subject = StringName(value.children[1].string_value)
	result.comparator = StringName(value.children[2].string_value)
	if value.children[3].optional_present:
		result.int_value = OptionalIntValue.new(value.children[3].children[0].int_value)
	if value.children[4].optional_present:
		result.stable_id_value = OptionalStringNameValue.of(StringName(value.children[4].children[0].string_value))
	if value.children[5].optional_present:
		result.max_uses_per_battle = OptionalIntValue.new(value.children[5].children[0].int_value)
	return result

func _decode_battle_operation(value: ContentValue) -> BattleOperationRule:
	if value == null or value.children.is_empty():
		return _payload_failure(&"effect.battle_operations")
	var result := BattleOperationRule.new()
	result.operation_index = value.children[0].int_value
	match value.record_type:
		0x3001:
			if value.children.size() != 5: return _payload_failure(&"effect.damage")
			result.kind = &"damage"
			result.base_amount = value.children[1].int_value
			result.scaling = StringName(value.children[2].string_value)
			result.damage_type = StringName(value.children[3].string_value)
			result.target = StringName(value.children[4].string_value)
		0x3002:
			if value.children.size() != 4: return _payload_failure(&"effect.heal")
			result.kind = &"heal"
			result.base_amount = value.children[1].int_value
			result.scaling = StringName(value.children[2].string_value)
			result.target = StringName(value.children[3].string_value)
		0x3003:
			if value.children.size() != 4: return _payload_failure(&"effect.shield")
			result.kind = &"shield"
			result.amount = value.children[1].int_value
			result.duration_ticks = value.children[2].int_value
			result.target = StringName(value.children[3].string_value)
		0x3004:
			if value.children.size() != 6: return _payload_failure(&"effect.modify_stat")
			result.kind = &"modify_stat"
			result.stat = StringName(value.children[1].string_value)
			result.mode = StringName(value.children[2].string_value)
			result.amount = value.children[3].int_value
			result.duration_ticks = value.children[4].int_value
			result.target = StringName(value.children[5].string_value)
		0x3005:
			if value.children.size() != 5: return _payload_failure(&"effect.apply_status")
			result.kind = &"apply_status"
			result.status_id = OptionalStringNameValue.of(StringName(value.children[1].string_value))
			result.stacks = value.children[2].int_value
			result.duration_ticks = value.children[3].int_value
			result.target = StringName(value.children[4].string_value)
		0x3006:
			if value.children.size() != 3: return _payload_failure(&"effect.remove_status")
			result.kind = &"remove_status"
			result.status_id = OptionalStringNameValue.of(StringName(value.children[1].string_value))
			result.target = StringName(value.children[2].string_value)
		0x3007:
			if value.children.size() != 3: return _payload_failure(&"effect.move")
			result.kind = &"move"
			result.direction = StringName(value.children[1].string_value)
			result.cells = value.children[2].int_value
		0x3008:
			if value.children.size() != 5: return _payload_failure(&"effect.summon")
			result.kind = &"summon"
			result.unit_id = OptionalStringNameValue.of(StringName(value.children[1].string_value))
			result.count = value.children[2].int_value
			result.max_active_per_source = value.children[3].int_value
			result.placement_rule = StringName(value.children[4].string_value)
		0x3009:
			if value.children.size() != 3: return _payload_failure(&"effect.grant_mana")
			result.kind = &"grant_mana"
			result.amount = value.children[1].int_value
			result.target = StringName(value.children[2].string_value)
		_:
			return _payload_failure(&"effect.battle_operations.type")
	return result

func _decode_run_operation(value: ContentValue) -> BattleRunOperationRule:
	if value == null or value.children.size() != 3:
		return _payload_failure(&"effect.run_operations")
	var result := BattleRunOperationRule.new()
	result.operation_index = value.children[0].int_value
	result.amount = value.children[1].int_value
	result.claim_scope = StringName(value.children[2].string_value)
	match value.record_type:
		0x3101: result.kind = &"add_gold"
		0x3102: result.kind = &"add_xp"
		0x3103: result.kind = &"heal_expedition_hp"
		_: return _payload_failure(&"effect.run_operations.type")
	return result

func _payload_is(view: ContentDefinitionView, type_id: int, child_count: int) -> bool:
	if view == null or view.payload == null \
		or view.payload.record_type != type_id \
		or view.payload.children.size() != child_count:
		_error = BattleRuleCatalogError.new(
			BattleRuleCatalogError.PAYLOAD_INVALID,
			&"payload",
			view.content_id if view != null else &""
		)
		return false
	return true

func _payload_failure(path: StringName) -> Variant:
	_error = BattleRuleCatalogError.new(BattleRuleCatalogError.PAYLOAD_INVALID, path)
	return null

func _current_failure(content_id: StringName) -> BattleRuleCatalogBuildResult:
	if _error == null:
		return BattleRuleCatalogBuildResult.failure(
			BattleRuleCatalogError.PAYLOAD_INVALID,
			&"payload",
			content_id
		)
	return BattleRuleCatalogBuildResult.failure(
		_error.code,
		_error.field_path,
		content_id
	)

func _append_effect_references(pending: Array[StringName], effect: BattleEffectRule) -> void:
	for condition: BattleConditionRule in effect.conditions:
		if condition.stable_id_value != null:
			pending.append(condition.stable_id_value.value)
	for operation: BattleOperationRule in effect.battle_operations:
		if operation.unit_id != null: pending.append(operation.unit_id.value)
		if operation.status_id != null: pending.append(operation.status_id.value)

func _append_names(target: Array[StringName], values: Array[StringName]) -> void:
	for value: StringName in values: target.append(value)

func _names(value: ContentValue) -> Array[StringName]:
	var result: Array[StringName] = []
	if value == null: return result
	for child: ContentValue in value.children:
		result.append(StringName(child.string_value))
	return result

func _name_less(left: StringName, right: StringName) -> bool:
	return String(left) < String(right)

func _unit_less(left: BattleUnitRule, right: BattleUnitRule) -> bool:
	return String(left.unit_id) < String(right.unit_id)

func _trait_less(left: BattleTraitRule, right: BattleTraitRule) -> bool:
	return String(left.trait_id) < String(right.trait_id)

func _ability_less(left: BattleAbilityRule, right: BattleAbilityRule) -> bool:
	return String(left.ability_id) < String(right.ability_id)

func _effect_less(left: BattleEffectRule, right: BattleEffectRule) -> bool:
	return String(left.effect_id) < String(right.effect_id)

func _encounter_less(left: BattleEncounterRule, right: BattleEncounterRule) -> bool:
	return String(left.encounter_id) < String(right.encounter_id)

func _equipment_less(left: BattleEquipmentRule, right: BattleEquipmentRule) -> bool:
	return String(left.equipment_id) < String(right.equipment_id)

func _relic_less(left: BattleRelicRule, right: BattleRelicRule) -> bool:
	return String(left.relic_id) < String(right.relic_id)
