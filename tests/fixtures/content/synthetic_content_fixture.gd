class_name SyntheticContentFixture
extends RefCounted

static func build_valid(add_fourth_population_source: bool = false) -> ContentValidationInput:
	var definitions: Array[ContentDefinition] = []
	definitions.append(_effect(&"effect.general", &"general"))
	for index in 6: definitions.append(_effect(StringName("effect.affix_%d" % index), &"elite_affix"))
	for index in 12: definitions.append(_effect(StringName("effect.event_%d" % index), &"general"))
	definitions.append(_summon_effect())
	definitions.append(_operation_matrix_effect())
	definitions.append(_summon_ability())
	for index in 6: definitions.append(_trait(StringName("trait.faction_%d" % index), &"faction"))
	for index in 6: definitions.append(_trait(StringName("trait.role_%d" % index), &"role"))
	for index in 32: definitions.append(_player_unit(index))
	for index in 12: definitions.append(_monster_unit(index))
	for index in 6: definitions.append(_component(index))
	for left in 6:
		for right in range(left, 6): definitions.append(_equipment(left, right))
	var consumable := ConsumableDef.new()
	_common(consumable, &"consumable.test")
	consumable.use_timing = &"event"
	var consumable_gold := AddGoldOperationDef.new()
	consumable_gold.operation_index = 0
	consumable_gold.amount = 1
	consumable_gold.claim_scope = &"once_per_node"
	consumable.run_operations = [consumable_gold]
	consumable.stack_limit = 1
	definitions.append(consumable)
	for index in 15: definitions.append(_relic(index))
	for index in 3: definitions.append(_commander(index))
	definitions.append(_battle_encounter(&"normal"))
	definitions.append(_battle_encounter(&"elite"))
	for index in 3: definitions.append(_boss_encounter(index))
	definitions.append(_reward_table())
	definitions.append(_relic_reward_table())
	definitions.append_array(_map_nodes(add_fourth_population_source))
	definitions.append_array(_unlocks())
	definitions.append(_economy())
	definitions.append(_combat_config())
	definitions.append(_meta_reward())
	return ContentValidationInput.new(definitions, [], [], FakeContentDependencyPort.new(), 9)

static func mutate(case_name: StringName) -> ContentValidationInput:
	var input := build_valid()
	match case_name:
		&"stable_id":
			input.definitions[0].id = &"Invalid"
		&"reference":
			var unit := _find(input, &"unit.player_00") as UnitDef
			unit.has_ability_ref = true
			unit.ability_ref = &"ability.missing"
		&"asset":
			input.definitions[0].asset_refs = ["res://missing.png"]
			(input.dependency_port as FakeContentDependencyPort).missing_assets.append("res://missing.png")
		&"localization":
			input.definitions[0].display_name_key = &"loc.missing"
			(input.dependency_port as FakeContentDependencyPort).missing_localization_keys.append(&"loc.missing")
		&"unit_count":
			_remove(input, &"unit.player_31")
		&"cost_distribution":
			(_find(input, &"unit.player_00") as UnitDef).cost_tier = 2
		&"trait_kind_count":
			(_find(input, &"trait.faction_0") as TraitDef).trait_kind = &"role"
		&"three_tag_count":
			(_find(input, &"unit.player_00") as UnitDef).trait_refs.resize(2)
		&"trait_threshold":
			((_find(input, &"trait.faction_0") as TraitDef).thresholds[0]).required_count = 99
		&"component_count":
			_remove(input, &"item_component.c5")
		&"recipe_coverage":
			(_find(input, &"equipment.c0_c1") as EquipmentDef).component_pair = [&"item_component.c0", &"item_component.c0"]
		&"minimum_counts":
			_remove(input, &"relic.r14")
		&"node_coverage":
			(_find(input, &"map_node.normal") as MapNodeDef).node_type = &"unknown"
		&"challenge_chain":
			_remove(input, &"unlock.challenge_3")
		&"shop_probability":
			((_find(input, &"economy.default") as EconomyConfigDef).shop_odds_by_level[0]).tier_basis_points[0] = 9999
		&"pool_copies":
			((_find(input, &"economy.default") as EconomyConfigDef).pool_copies_by_tier[4]).value_u32 = 8
		&"reward_weight":
			((_find(input, &"reward_table.default") as RewardTableDef).reward_candidates[0]).weight_i32 = -1
		&"unlock_cycle":
			(_find(input, &"unlock.challenge_0") as UnlockDef).prerequisite_refs = [&"unlock.challenge_5"]
		&"base_build":
			(_find(input, &"unlock.base_profile") as UnlockDef).unlocked_content_refs = [&"unit.player_00"]
		&"effect_trigger":
			(_find(input, &"effect.general") as EffectDef).trigger = &"invalid"
		&"effect_condition":
			var condition := ConditionDef.new()
			condition.kind = &"distance_at_most"
			condition.subject = &"target"
			condition.comparator = &"lte"
			condition.has_int_value = true
			condition.int_value = 8
			(_find(input, &"effect.general") as EffectDef).conditions = [condition]
		&"operation":
			var move := MoveOperationDef.new()
			move.operation_index = 0
			move.direction_or_target = &"forward"
			move.cells = 8
			(_find(input, &"effect.general") as EffectDef).battle_operations = [move]
		&"consumable_operation":
			var unknown_consumable_operation := RunOperationDef.new()
			unknown_consumable_operation.operation_index = 0
			(_find(input, &"consumable.test") as ConsumableDef).run_operations = [unknown_consumable_operation]
		&"map_enter_operation":
			var unknown_enter_operation := RunOperationDef.new()
			unknown_enter_operation.operation_index = 0
			(_find(input, &"map_node.normal") as MapNodeDef).enter_operations = [unknown_enter_operation]
		&"map_exit_operation":
			var unknown_exit_operation := RunOperationDef.new()
			unknown_exit_operation.operation_index = 0
			(_find(input, &"map_node.event_0") as MapNodeDef).exit_operations = [unknown_exit_operation]
		&"run_intent":
			var effect := _find(input, &"effect.general") as EffectDef
			effect.content_role = &"battle_intent"
			var grant := GrantItemOperationDef.new()
			grant.operation_index = 0
			grant.content_ref = &"consumable.test"
			grant.count = 1
			effect.run_operations = [grant]
		&"summon_bound":
			((_find(input, &"effect.summon") as EffectDef).battle_operations[0] as SummonOperationDef).max_active_per_source = 0
		&"summon_chain":
			(_find(input, &"unit.monster_01") as UnitDef).has_ability_ref = true
			(_find(input, &"unit.monster_01") as UnitDef).ability_ref = &"ability.summon"
		&"summon_cycle":
			((_find(input, &"effect.summon") as EffectDef).battle_operations[0] as SummonOperationDef).unit_ref = &"unit.monster_00"
	return input

static func _common(definition: ContentDefinition, content_id: StringName) -> void:
	definition.id = content_id
	definition.schema_version = 1
	definition.display_name_key = StringName("loc.%s" % String(content_id))

static func _effect(content_id: StringName, role: StringName) -> EffectDef:
	var value := EffectDef.new()
	_common(value, content_id)
	value.content_role = role
	value.trigger = &"battle_start"
	value.stacking = &"replace"
	value.max_stacks = 1
	value.duration_ticks = 1
	return value

static func _summon_effect() -> EffectDef:
	var value := _effect(&"effect.summon", &"general")
	value.trigger = &"cast"
	var operation := SummonOperationDef.new()
	operation.operation_index = 0
	operation.unit_ref = &"unit.monster_01"
	operation.count = 1
	operation.max_active_per_source = 2
	operation.placement_rule = &"adjacent"
	value.battle_operations = [operation]
	return value

static func _summon_ability() -> AbilityDef:
	var value := AbilityDef.new()
	_common(value, &"ability.summon")
	value.start_mana = 0
	value.max_mana = 50
	value.target_rule = &"self"
	value.cast_ticks = 1
	value.effect_refs = [&"effect.summon"]
	value.description_key = &"loc.ability.summon.description"
	return value

static func _operation_matrix_effect() -> EffectDef:
	var value := _effect(&"effect.operation_matrix", &"general")
	var damage := DamageOperationDef.new()
	damage.operation_index = 0
	damage.base = 10
	damage.scaling = &"attack"
	damage.damage_type = &"physical"
	damage.target = &"target"
	var heal := HealOperationDef.new()
	heal.operation_index = 1
	heal.base = 5
	heal.scaling = &"attack"
	heal.target = &"self"
	var shield := ShieldOperationDef.new()
	shield.operation_index = 2
	shield.amount = 5
	shield.duration_ticks = 20
	shield.target = &"self"
	var modify := ModifyStatOperationDef.new()
	modify.operation_index = 3
	modify.stat = &"armor"
	modify.mode = &"flat"
	modify.amount = 1
	modify.duration_ticks = 20
	modify.target = &"self"
	var apply_status := ApplyStatusOperationDef.new()
	apply_status.operation_index = 4
	apply_status.status_id = &"effect.general"
	apply_status.stacks = 1
	apply_status.duration_ticks = 20
	apply_status.target = &"target"
	var remove_status := RemoveStatusOperationDef.new()
	remove_status.operation_index = 5
	remove_status.status_id = &"effect.general"
	remove_status.target = &"self"
	var move := MoveOperationDef.new()
	move.operation_index = 6
	move.direction_or_target = &"forward"
	move.cells = 1
	var summon := SummonOperationDef.new()
	summon.operation_index = 7
	summon.unit_ref = &"unit.monster_01"
	summon.count = 1
	summon.max_active_per_source = 1
	summon.placement_rule = &"adjacent"
	var mana := GrantManaOperationDef.new()
	mana.operation_index = 8
	mana.amount = 5
	mana.target = &"self"
	value.battle_operations = [damage, heal, shield, modify, apply_status, remove_status, move, summon, mana]
	# W4-F1（2026-07-24）：effect.operation_matrix 被 economy/route/rule 遺物引用，其 run intent
	# 的 claim_scope 必須為 &"always"（見 content_validator._validate_relic_effect_scope 與
	# RunRelicTableBuilder）。map_node／consumable 的 run intent 不受此規則約束，維持 once_per_node。
	var add_gold := AddGoldOperationDef.new()
	add_gold.operation_index = 0
	add_gold.amount = 1
	add_gold.claim_scope = &"always"
	var add_xp := AddXpOperationDef.new()
	add_xp.operation_index = 1
	add_xp.amount = 1
	add_xp.claim_scope = &"always"
	var heal_hp := HealExpeditionHpOperationDef.new()
	heal_hp.operation_index = 2
	heal_hp.amount = 1
	heal_hp.claim_scope = &"always"
	value.run_operations = [add_gold, add_xp, heal_hp]
	var condition := ConditionDef.new()
	condition.kind = &"source_tag"
	condition.subject = &"source"
	condition.comparator = &"has"
	condition.has_stable_id_value = true
	condition.stable_id_value = &"trait.faction_0"
	condition.has_max_uses_per_battle = true
	condition.max_uses_per_battle = 1
	value.conditions = [condition]
	return value

static func _trait(content_id: StringName, kind: StringName) -> TraitDef:
	var value := TraitDef.new()
	_common(value, content_id)
	value.trait_kind = kind
	value.member_rule = &"distinct_unit_id"
	value.description_key = StringName("loc.%s.description" % String(content_id))
	var threshold := TraitThresholdDef.new()
	threshold.required_count = 1
	threshold.effect_refs = [&"effect.general"]
	value.thresholds = [threshold]
	return value

static func _player_unit(index: int) -> UnitDef:
	var value := _unit(StringName("unit.player_%02d" % index), &"player")
	value.cost_tier = 1 if index < 10 else (2 if index < 18 else (3 if index < 24 else (4 if index < 29 else 5)))
	value.trait_refs = [StringName("trait.faction_%d" % (index % 6)), StringName("trait.role_%d" % (index % 6))]
	if index < 4: value.trait_refs.append(StringName("trait.faction_%d" % ((index + 1) % 6)))
	return value

static func _monster_unit(index: int) -> UnitDef:
	var value := _unit(StringName("unit.monster_%02d" % index), &"monster")
	value.shop_condition = &"never"
	if index == 0:
		value.has_ability_ref = true
		value.ability_ref = &"ability.summon"
	return value

static func _unit(content_id: StringName, availability: StringName) -> UnitDef:
	var value := UnitDef.new()
	_common(value, content_id)
	value.cost_tier = 1
	value.base_stats = UnitStatsDef.new()
	value.base_stats.health = 100
	value.base_stats.attack = 10
	value.base_stats.attack_speed_milli = 1000
	value.base_stats.attack_range_cells = 1
	value.base_stats.max_mana = 50
	value.base_stats.move_speed_milli = 1000
	value.star_scalings = [_scaling(1, 10000), _scaling(2, 18000), _scaling(3, 32000)]
	value.ai_profile = &"frontline"
	value.basic_attack_profile = &"melee"
	value.availability = availability
	value.shop_condition = &"always"
	return value

static func _scaling(star: int, bps: int) -> StarScalingDef:
	var value := StarScalingDef.new()
	value.star = star
	value.health_bps = bps
	value.attack_bps = bps
	value.armor_bps = bps
	value.magic_resist_bps = bps
	value.attack_speed_bps = bps
	value.attack_range_bps = bps
	value.start_mana_bps = bps
	value.max_mana_bps = bps
	value.move_speed_bps = bps
	return value

static func _component(index: int) -> ItemComponentDef:
	var value := ItemComponentDef.new()
	_common(value, StringName("item_component.c%d" % index))
	value.recipe_key = "c%d" % index
	value.sort_order = index
	return value

static func _equipment(left: int, right: int) -> EquipmentDef:
	var value := EquipmentDef.new()
	_common(value, StringName("equipment.c%d_c%d" % [left, right]))
	value.component_pair = [StringName("item_component.c%d" % left)]
	if right != left: value.component_pair.append(StringName("item_component.c%d" % right))
	value.effect_refs = [&"effect.general"]
	if left == 0 and right == 0:
		var modifier := StatModifierDef.new()
		modifier.stat = &"attack"
		modifier.mode = &"flat"
		modifier.amount_i32 = 1
		value.stat_modifiers = [modifier]
	return value

static func _relic(index: int) -> RelicDef:
	var value := RelicDef.new()
	_common(value, StringName("relic.r%d" % index))
	value.category = _relic_category_for_index(index)
	value.effect_refs = [&"effect.operation_matrix"]
	value.activation_limit = 1
	value.population_bonus = 1 if index == 0 else 0
	return value

# 15 件遺物涵蓋四類各 >=1（0-3 battle、4-7 economy、8-10 route、11-14 rule）。
# effect_refs 統一指向 effect.operation_matrix——其 battle_operations 與 run_operations 皆非空，
# battle／非 battle 類遺物的 effect scope 規則都能滿足；run_operations 的 claim_scope 全為
# &"always"（W4-F1：非 battle 遺物引用的 run intent 必須 always）。
static func _relic_category_for_index(index: int) -> StringName:
	if index < 4: return &"battle"
	if index < 8: return &"economy"
	if index < 11: return &"route"
	return &"rule"

static func _commander(index: int) -> CommanderDef:
	var value := CommanderDef.new()
	_common(value, StringName("commander.c%d" % index))
	var amount := ContentAmountDef.new()
	amount.content_id = StringName("unit.player_%02d" % index)
	amount.count_u32 = 1
	value.starting_pack = [amount]
	value.passive_effect_refs = [&"effect.general"]
	var preference := WeightedEnumDef.new()
	preference.enum_key = &"normal"
	preference.weight_i32 = 1
	value.route_preferences = [preference]
	value.population_bonus = 1 if index == 0 else 0
	return value

static func _boss_encounter(index: int) -> EncounterDef:
	var value := EncounterDef.new()
	_common(value, StringName("encounter.boss_%d" % index))
	value.encounter_kind = &"boss"
	var spawn := EnemySpawnDef.new()
	spawn.side = &"enemy"
	spawn.logical_y = 6
	spawn.logical_x = index
	spawn.spawn_key = "boss_%d" % index
	spawn.unit_ref = &"unit.monster_00"
	spawn.star = 1
	value.enemy_spawns = [spawn]
	value.affix_refs = [&"effect.affix_0"]
	var phase := BossPhaseDef.new()
	phase.phase_index = 0
	phase.hp_threshold_bps = 10000
	phase.source_spawn_key = spawn.spawn_key
	phase.effect_refs = [&"effect.general"]
	value.boss_phases = [phase]
	return value

static func _battle_encounter(kind: StringName) -> EncounterDef:
	var value := EncounterDef.new()
	_common(value, StringName("encounter.%s" % String(kind)))
	value.encounter_kind = kind
	var spawn := EnemySpawnDef.new()
	spawn.side = &"enemy"
	spawn.logical_y = 6
	spawn.logical_x = 3
	spawn.spawn_key = "enemy_0"
	spawn.unit_ref = &"unit.monster_00"
	spawn.star = 1
	value.enemy_spawns = [spawn]
	return value

static func _reward_table() -> RewardTableDef:
	var value := RewardTableDef.new()
	_common(value, &"reward_table.default")
	var candidate := RewardCandidateDef.new()
	candidate.kind = &"gold"
	candidate.weight_i32 = 1
	var condition := ConditionDef.new()
	condition.kind = &"expedition_hp_below"
	condition.subject = &"expedition_hp"
	condition.comparator = &"lt"
	condition.has_int_value = true
	condition.int_value = 101
	candidate.conditions = [condition]
	var fallback := RewardCandidateDef.new()
	fallback.kind = &"heal"
	fallback.weight_i32 = 1
	value.reward_candidates = [candidate, fallback]
	value.draw_count = 3
	return value

static func _relic_reward_table() -> RewardTableDef:
	var value := RewardTableDef.new()
	_common(value, &"reward_table.relic")
	var candidate := RewardCandidateDef.new()
	candidate.kind = &"relic"
	candidate.has_content_ref = true
	candidate.content_ref = &"relic.r0"
	candidate.weight_i32 = 1
	value.reward_candidates = [candidate]
	value.draw_count = 3
	return value

static func _map_nodes(add_fourth_population_source: bool) -> Array[ContentDefinition]:
	var result: Array[ContentDefinition] = []
	for kind in [&"normal", &"elite", &"merchant", &"rest", &"treasure", &"boss"]:
		var value := MapNodeDef.new()
		_common(value, StringName("map_node.%s" % String(kind)))
		value.node_type = kind
		match kind:
			&"normal", &"elite":
				value.generator_ref = StringName("encounter.%s" % String(kind))
			&"boss":
				value.generator_ref = &"encounter.boss_0"
			_:
				value.generator_ref = &"effect.general"
		if kind == &"normal":
			var enter_xp := AddXpOperationDef.new()
			enter_xp.operation_index = 0
			enter_xp.amount = 1
			enter_xp.claim_scope = &"once_per_node"
			value.enter_operations = [enter_xp]
		result.append(value)
	for index in 12:
		var event := MapNodeDef.new()
		_common(event, StringName("map_node.event_%d" % index))
		event.node_type = &"event"
		event.generator_ref = StringName("effect.event_%d" % index)
		if index == 0:
			var modify_pool := ModifyUnitPoolOperationDef.new()
			modify_pool.operation_index = 0
			modify_pool.unit_ref = &"unit.player_00"
			modify_pool.count = 1
			var grant_item := GrantItemOperationDef.new()
			grant_item.operation_index = 1
			grant_item.content_ref = &"consumable.test"
			grant_item.count = 1
			var grant_relic := GrantRelicOperationDef.new()
			grant_relic.operation_index = 2
			grant_relic.relic_ref = &"relic.r0"
			var population := PopulationSourceOperationDef.new()
			population.operation_index = 3
			population.source_id = &"source.event_bonus"
			population.amount = 1
			event.enter_operations = [modify_pool, grant_item, grant_relic, population]
			var exit_heal := HealExpeditionHpOperationDef.new()
			exit_heal.operation_index = 0
			exit_heal.amount = 1
			exit_heal.claim_scope = &"once_per_node"
			event.exit_operations = [exit_heal]
		elif index == 1 and add_fourth_population_source:
			var extra_population := PopulationSourceOperationDef.new()
			extra_population.operation_index = 0
			extra_population.source_id = &"source.extra_bonus"
			extra_population.amount = 1
			event.enter_operations = [extra_population]
		result.append(event)
	return result

static func _unlocks() -> Array[ContentDefinition]:
	var result: Array[ContentDefinition] = []
	var base := UnlockDef.new()
	_common(base, &"unlock.base_profile")
	base.unlock_kind = &"base_profile"
	base.unlocked_content_refs = [&"unit.player_00", &"unit.player_01", &"unit.player_02"]
	result.append(base)
	for level in 6:
		var value := UnlockDef.new()
		_common(value, StringName("unlock.challenge_%d" % level))
		value.unlock_kind = &"challenge"
		value.challenge_level = level
		if level > 0:
			value.prerequisite_refs = [StringName("unlock.challenge_%d" % (level - 1))]
			value.modifier_refs = [StringName("effect.affix_%d" % ((level - 1) % 6))]
		result.append(value)
	return result

static func _economy() -> EconomyConfigDef:
	var value := EconomyConfigDef.new()
	_common(value, &"economy.default")
	var income := U32PairDef.new()
	income.key_u32 = 0
	income.value_u32 = 5
	value.layer_income = [income]
	for level in range(1, 10):
		var odds := ShopOddsRowDef.new()
		odds.level = level
		odds.tier_basis_points = [10000, 0, 0, 0, 0]
		value.shop_odds_by_level.append(odds)
	var copies := [18, 15, 12, 10, 9]
	for tier in range(1, 6):
		var pair := U32PairDef.new()
		pair.key_u32 = tier
		pair.value_u32 = copies[tier - 1]
		value.pool_copies_by_tier.append(pair)
		var cost := U32PairDef.new()
		cost.key_u32 = tier
		cost.value_u32 = tier
		value.unit_costs_by_tier.append(cost)
	var thresholds := [4, 8, 16, 28, 44, 64]
	for level in range(3, 9):
		var threshold := U32PairDef.new()
		threshold.key_u32 = level
		threshold.value_u32 = thresholds[level - 3]
		value.xp_thresholds.append(threshold)
	return value

static func _combat_config() -> CombatConfigDef:
	var value := CombatConfigDef.new()
	_common(value, &"config.combat_default")
	return value

static func _meta_reward() -> MetaRewardTableDef:
	var value := MetaRewardTableDef.new()
	_common(value, &"meta_reward.default")
	value.completion_reward = 1
	value.failure_reward = 0
	var score := EnumIntPairDef.new()
	score.enum_key = &"normal"
	score.value_i32 = 1
	value.node_scores = [score]
	for level in range(0, 6):
		var multiplier := ChallengeMultiplierDef.new()
		multiplier.challenge_level = level
		multiplier.basis_points = 10000 + level * 1000
		value.challenge_multiplier_bps.append(multiplier)
	return value

static func _find(input: ContentValidationInput, content_id: StringName) -> ContentDefinition:
	for definition in input.definitions:
		if definition.id == content_id: return definition
	return null

static func _remove(input: ContentValidationInput, content_id: StringName) -> void:
	for index in input.definitions.size():
		if input.definitions[index].id == content_id:
			input.definitions.remove_at(index)
			return
