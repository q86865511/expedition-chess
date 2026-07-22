class_name ContentValidator
extends RefCounted

const PLAYER_COST_DISTRIBUTION := [10, 8, 6, 5, 3]
const NODE_TYPES: Array[StringName] = [&"normal", &"elite", &"merchant", &"event", &"rest", &"treasure", &"boss"]
const EFFECT_TRIGGERS: Array[StringName] = [&"battle_start", &"attack", &"hit", &"damaged", &"cast", &"kill", &"death", &"periodic", &"battle_end"]
const EFFECT_CONDITIONS: Array[StringName] = [&"source_tag", &"target_tag", &"health_below_bps", &"health_above_bps", &"distance_at_most", &"distance_at_least", &"has_status", &"lacks_status", &"has_equipment", &"max_uses_per_battle"]
const STACKING_RULES: Array[StringName] = [&"replace", &"refresh_duration", &"add_stacks", &"independent"]
const BASIC_ATTACK_PROFILES: Array[StringName] = [&"melee", &"ranged", &"magic_projectile"]
const SHOP_CONDITIONS: Array[StringName] = [&"always", &"unlocked", &"event_only", &"never"]

var _issues: Array[ContentValidationIssue] = []
var _by_id: Dictionary = {}
var _compiler := ContentDefinitionCompilerV2.new()
var _stable_id_validator := StableIdValidator.new()

func validate(input: ContentValidationInput) -> ContentValidationReport:
	_issues.clear()
	_by_id.clear()
	var report := ContentValidationReport.new()
	if input == null:
		return ContentValidationReport.failure(&"CONTENT_VALIDATION_FAILED", &"input")
	_index_and_validate_ids(input)
	_validate_dependencies(input)
	_validate_units_and_traits(input.definitions)
	_validate_recipes(input.definitions)
	_validate_minimum_counts_and_nodes(input.definitions)
	_validate_challenge_chain(input.definitions)
	_validate_economy(input.definitions)
	_validate_rewards(input.definitions)
	_validate_unlock_graph(input.definitions)
	_validate_operations(input.definitions)
	_validate_encounter_sources(input.definitions)
	_calculate_population_and_entities(input, report)
	_validate_combat_config(input.definitions, report.entity_stress_minimum)
	_issues.sort_custom(_issue_less)
	report.valid = _issues.is_empty()
	for issue in _issues: report.issues.append(issue.deep_clone())
	return report

func _index_and_validate_ids(input: ContentValidationInput) -> void:
	var names: Dictionary = {}
	for definition in input.definitions:
		if definition == null:
			_issue(&"CONTENT_STABLE_ID", &"", &"definition", "null")
			continue
		if not _stable_id_validator.is_valid(definition.id):
			_issue(&"CONTENT_STABLE_ID", definition.id, &"id")
		if names.has(definition.id):
			_issue(&"CONTENT_STABLE_ID", definition.id, &"id", "duplicate")
		else:
			names[definition.id] = &"active"
			_by_id[definition.id] = definition
	for alias in input.aliases:
		if not _stable_id_validator.is_valid(alias.source_id) or not _stable_id_validator.is_valid(alias.target_id) or names.has(alias.source_id):
			_issue(&"CONTENT_STABLE_ID", alias.source_id, &"alias")
		else:
			names[alias.source_id] = &"alias"
	for tombstone in input.tombstones:
		if not _stable_id_validator.is_valid(tombstone.original_id) or names.has(tombstone.original_id):
			_issue(&"CONTENT_STABLE_ID", tombstone.original_id, &"tombstone")
		else:
			names[tombstone.original_id] = &"tombstone"
	var alias_targets: Dictionary = {}
	for alias in input.aliases: alias_targets[alias.source_id] = alias.target_id
	for alias in input.aliases:
		var visited: Dictionary = {}
		var cursor: StringName = alias.source_id
		while alias_targets.has(cursor):
			if visited.has(cursor):
				_issue(&"CONTENT_STABLE_ID", alias.source_id, &"alias", "cycle")
				break
			visited[cursor] = true
			cursor = alias_targets[cursor] as StringName
		if not names.has(cursor): _issue(&"CONTENT_STABLE_ID", alias.source_id, &"alias.target", "missing")

func _validate_dependencies(input: ContentValidationInput) -> void:
	for definition in input.definitions:
		if definition == null: continue
		for reference in _compiler.collect_references(definition):
			if not _by_id.has(reference): _issue(&"CONTENT_REFERENCE_MISSING", definition.id, &"references", String(reference))
		if definition.display_name_key.is_empty() or input.dependency_port == null or not input.dependency_port.localization_key_exists(definition.display_name_key):
			_issue(&"CONTENT_LOCALIZATION_MISSING", definition.id, &"display_name_key", String(definition.display_name_key))
		for asset_path in definition.asset_refs:
			if input.dependency_port == null or not input.dependency_port.asset_exists(asset_path):
				_issue(&"CONTENT_ASSET_MISSING", definition.id, &"asset_refs", asset_path)
		if definition is TraitDef:
			_validate_localization(input, definition.id, definition.description_key, &"description_key")
		elif definition is AbilityDef:
			_validate_localization(input, definition.id, definition.description_key, &"description_key")

func _validate_localization(input: ContentValidationInput, source_id: StringName, key: StringName, path: StringName) -> void:
	if key.is_empty() or input.dependency_port == null or not input.dependency_port.localization_key_exists(key):
		_issue(&"CONTENT_LOCALIZATION_MISSING", source_id, path, String(key))

func _validate_units_and_traits(definitions: Array[ContentDefinition]) -> void:
	var players: Array[UnitDef] = []
	var faction_count := 0
	var role_count := 0
	var three_tag_count := 0
	var cost_counts := PackedInt32Array([0, 0, 0, 0, 0])
	var trait_members: Dictionary = {}
	for definition in definitions:
		if definition is TraitDef:
			var trait_definition := definition as TraitDef
			if trait_definition.trait_kind == &"faction": faction_count += 1
			elif trait_definition.trait_kind == &"role": role_count += 1
		if definition is UnitDef:
			var unit := definition as UnitDef
			_validate_unit_schema(unit)
			if unit.availability not in [&"player", &"shared"]: continue
			players.append(unit)
			if unit.cost_tier >= 1 and unit.cost_tier <= 5: cost_counts[unit.cost_tier - 1] += 1
			if unit.trait_refs.size() == 3: three_tag_count += 1
			for trait_id in unit.trait_refs:
				trait_members[trait_id] = int(trait_members.get(trait_id, 0)) + 1
	if players.size() != 32: _issue(&"CONTENT_UNIT_COUNT", &"catalog.units", &"players", str(players.size()))
	var distribution_matches := cost_counts.size() == PLAYER_COST_DISTRIBUTION.size()
	for index in cost_counts.size():
		if cost_counts[index] != PLAYER_COST_DISTRIBUTION[index]: distribution_matches = false
	if not distribution_matches: _issue(&"CONTENT_COST_DISTRIBUTION", &"catalog.units", &"cost_tier", str(cost_counts))
	if faction_count != 6 or role_count != 6: _issue(&"CONTENT_TRAIT_KIND_COUNT", &"catalog.traits", &"trait_kind", "%d/%d" % [faction_count, role_count])
	if three_tag_count != 4: _issue(&"CONTENT_THREE_TAG_COUNT", &"catalog.units", &"trait_refs", str(three_tag_count))
	for definition in definitions:
		if definition is TraitDef:
			var available := int(trait_members.get(definition.id, 0))
			var previous := 0
			for threshold in definition.thresholds:
				if threshold == null or threshold.required_count <= previous or threshold.required_count > available:
					_issue(&"CONTENT_TRAIT_THRESHOLD_UNREACHABLE", definition.id, &"thresholds", str(available))
					break
				previous = threshold.required_count

func _validate_unit_schema(unit: UnitDef) -> void:
	if unit.base_stats == null:
		_issue(&"CONTENT_OPERATION_INVALID", unit.id, &"base_stats", "missing")
	else:
		var stats := unit.base_stats
		if stats.health <= 0 or stats.attack <= 0 or stats.attack_speed_milli <= 0 or stats.attack_range_cells <= 0 or stats.max_mana <= 0 or stats.move_speed_milli <= 0:
			_issue(&"CONTENT_OPERATION_INVALID", unit.id, &"base_stats", "range")
	if not BASIC_ATTACK_PROFILES.has(unit.basic_attack_profile): _issue(&"CONTENT_OPERATION_INVALID", unit.id, &"basic_attack_profile")
	if not SHOP_CONDITIONS.has(unit.shop_condition): _issue(&"CONTENT_OPERATION_INVALID", unit.id, &"shop_condition")
	var stars := PackedInt32Array()
	for scaling in unit.star_scalings:
		if scaling == null: continue
		stars.append(scaling.star)
		var values := PackedInt32Array([scaling.health_bps, scaling.attack_bps, scaling.armor_bps, scaling.magic_resist_bps,
			scaling.attack_speed_bps, scaling.attack_range_bps, scaling.start_mana_bps, scaling.max_mana_bps, scaling.move_speed_bps])
		for value in values:
			if value < 1 or value > 100000: _issue(&"CONTENT_OPERATION_INVALID", unit.id, &"star_scalings", "range")
	stars.sort()
	if stars != PackedInt32Array([1, 2, 3]): _issue(&"CONTENT_OPERATION_INVALID", unit.id, &"star_scalings", "stars")

func _validate_recipes(definitions: Array[ContentDefinition]) -> void:
	var components: Array[StringName] = []
	var recipes: Dictionary = {}
	for definition in definitions:
		if definition is ItemComponentDef: components.append(definition.id)
	if components.size() != 6: _issue(&"CONTENT_COMPONENT_COUNT", &"catalog.components", &"count", str(components.size()))
	components.sort_custom(_string_name_less)
	for definition in definitions:
		if not definition is EquipmentDef: continue
		if definition.component_pair.size() < 1 or definition.component_pair.size() > 2:
			_issue(&"CONTENT_RECIPE_COVERAGE", definition.id, &"component_pair", "count")
			continue
		var pair: Array[StringName] = definition.component_pair.duplicate()
		pair.sort_custom(_string_name_less)
		var key := String(pair[0]) + "+" + String(pair[0] if pair.size() == 1 else pair[1])
		if not components.has(pair[0]) or (pair.size() == 2 and not components.has(pair[1])) or recipes.has(key):
			_issue(&"CONTENT_RECIPE_COVERAGE", definition.id, &"component_pair", key)
		else: recipes[key] = definition.id
	var expected := 0
	for left in components.size():
		for right in range(left, components.size()):
			expected += 1
			var key := String(components[left]) + "+" + String(components[right])
			if not recipes.has(key): _issue(&"CONTENT_RECIPE_COVERAGE", &"catalog.equipment", &"component_pair", key)
	if expected != 21 or recipes.size() != 21: _issue(&"CONTENT_RECIPE_COVERAGE", &"catalog.equipment", &"count", str(recipes.size()))

func _validate_minimum_counts_and_nodes(definitions: Array[ContentDefinition]) -> void:
	var relics := 0
	var commanders := 0
	var monsters := 0
	var affixes := 0
	var bosses := 0
	var event_generators: Dictionary = {}
	var node_types: Array[StringName] = []
	for definition in definitions:
		if definition is RelicDef: relics += 1
		elif definition is CommanderDef: commanders += 1
		elif definition is UnitDef and definition.availability == &"monster": monsters += 1
		elif definition is EffectDef and definition.content_role == &"elite_affix": affixes += 1
		elif definition is EncounterDef and definition.encounter_kind == &"boss": bosses += 1
		elif definition is MapNodeDef:
			if not node_types.has(definition.node_type): node_types.append(definition.node_type)
			if definition.node_type == &"event": event_generators[definition.generator_ref] = true
			if definition.node_type in [&"normal", &"elite", &"boss"]:
				var generator: ContentDefinition = _by_id.get(
					definition.generator_ref, null
				)
				if not generator is EncounterDef \
					or generator.encounter_kind != definition.node_type:
					_issue(
						&"CONTENT_NODE_GENERATOR", definition.id,
						&"generator_ref", String(definition.generator_ref)
					)
	if relics < 15 or commanders != 3 or monsters < 12 or affixes < 6 or bosses != 3 or event_generators.size() < 12:
		_issue(&"CONTENT_MINIMUM_COUNTS", &"catalog.minimums", &"counts", "%d/%d/%d/%d/%d/%d" % [relics, commanders, monsters, affixes, bosses, event_generators.size()])
	node_types.sort_custom(_string_name_less)
	var expected := NODE_TYPES.duplicate()
	expected.sort_custom(_string_name_less)
	if node_types != expected: _issue(&"CONTENT_NODE_KIND_COVERAGE", &"catalog.nodes", &"node_type", str(node_types))

func _validate_challenge_chain(definitions: Array[ContentDefinition]) -> void:
	var levels: Dictionary = {}
	for definition in definitions:
		if definition is UnlockDef and definition.unlock_kind == &"challenge":
			if levels.has(definition.challenge_level): _issue(&"CONTENT_CHALLENGE_CHAIN", definition.id, &"challenge_level", "duplicate")
			levels[definition.challenge_level] = definition
	for level in range(0, 6):
		if not levels.has(level):
			_issue(&"CONTENT_CHALLENGE_CHAIN", &"catalog.challenge", &"challenge_level", str(level))
			continue
		var unlock: UnlockDef = levels[level]
		if level == 0 and not unlock.prerequisite_refs.is_empty(): _issue(&"CONTENT_CHALLENGE_CHAIN", unlock.id, &"prerequisite_refs", "level0")
		if level > 0:
			if not levels.has(level - 1): continue
			var previous: UnlockDef = levels[level - 1]
			if unlock.prerequisite_refs.size() != 1 or unlock.prerequisite_refs[0] != previous.id:
				_issue(&"CONTENT_CHALLENGE_CHAIN", unlock.id, &"prerequisite_refs", "gap")
			if unlock.modifier_refs.is_empty(): _issue(&"CONTENT_CHALLENGE_CHAIN", unlock.id, &"modifier_refs", "missing")

func _validate_economy(definitions: Array[ContentDefinition]) -> void:
	for definition in definitions:
		if not definition is EconomyConfigDef: continue
		for row in definition.shop_odds_by_level:
			var total := 0
			for odds in row.tier_basis_points: total += odds
			if row.tier_basis_points.size() != 5 or total != 10000: _issue(&"CONTENT_SHOP_PROBABILITY", definition.id, &"shop_odds_by_level", str(row.level))
		var tiers: Dictionary = {}
		for pair in definition.pool_copies_by_tier:
			tiers[pair.key_u32] = pair.value_u32
		for tier in range(1, 6):
			if int(tiers.get(tier, 0)) < 9: _issue(&"CONTENT_POOL_COPIES", definition.id, &"pool_copies_by_tier", str(tier))

func _validate_rewards(definitions: Array[ContentDefinition]) -> void:
	var has_standard := false
	var has_relic := false
	var has_event := false
	for definition in definitions:
		if not definition is RewardTableDef: continue
		var usable := 0
		var relic_candidates := 0
		var non_relic_candidates := 0
		var non_unit_candidates := 0
		var unconditional_relic := 0
		var unconditional_non_unit := 0
		var unconditional_non_relic := 0
		for candidate in definition.reward_candidates:
			for condition: ConditionDef in candidate.conditions:
				_validate_reward_condition(definition.id, condition)
			if candidate.weight_i32 < 0:
				_issue(&"CONTENT_REWARD_WEIGHT", definition.id, &"reward_candidates", "negative")
			elif candidate.weight_i32 > 0:
				usable += 1
				if candidate.kind == &"relic":
					relic_candidates += 1
					if candidate.conditions.is_empty():
						unconditional_relic += 1
				else:
					non_relic_candidates += 1
					if candidate.conditions.is_empty():
						unconditional_non_relic += 1
					if candidate.kind != &"unit":
						non_unit_candidates += 1
						if candidate.conditions.is_empty():
							unconditional_non_unit += 1
		if usable == 0 or definition.draw_count != 3: _issue(&"CONTENT_REWARD_WEIGHT", definition.id, &"reward_candidates", "draw_count")
		if relic_candidates > 0 and non_relic_candidates > 0:
			_issue(&"CONTENT_REWARD_STAGE", definition.id, &"reward_candidates", "mixed")
		elif relic_candidates > 0:
			has_relic = unconditional_relic > 0
			if not has_relic:
				_issue(&"CONTENT_REWARD_FALLBACK", definition.id, &"reward_candidates", "relic")
		elif non_relic_candidates > 0 and non_unit_candidates > 0:
			has_standard = unconditional_non_unit > 0
			has_event = has_event or unconditional_non_relic > 0
			if not has_standard:
				_issue(&"CONTENT_REWARD_FALLBACK", definition.id, &"reward_candidates", "standard")
		elif non_relic_candidates > 0:
			has_event = has_event or unconditional_non_relic > 0
			if unconditional_non_relic == 0:
				_issue(&"CONTENT_REWARD_FALLBACK", definition.id, &"reward_candidates", "event")
	if not has_standard or not has_relic or not has_event:
		_issue(
			&"CONTENT_REWARD_STAGE_COVERAGE", &"catalog.reward_tables",
			&"reward_candidates", "%s/%s/%s" % [has_standard, has_relic, has_event]
		)

func _validate_reward_condition(source_id: StringName, condition: ConditionDef) -> void:
	if condition == null or not condition.has_int_value \
		or condition.has_max_uses_per_battle:
		_issue(&"CONTENT_REWARD_CONDITION", source_id, &"reward_candidates.conditions", "shape")
		return
	var valid := false
	match condition.kind:
		&"roster_space_at_least":
			valid = condition.subject == &"roster" and condition.comparator == &"gte" \
				and condition.int_value >= 0 and condition.int_value <= 9 \
				and not condition.has_stable_id_value
		&"inventory_space_at_least":
			valid = condition.subject == &"inventory" and condition.comparator == &"gte" \
				and condition.int_value >= 0 and condition.int_value <= 16 \
				and not condition.has_stable_id_value
		&"expedition_hp_below":
			valid = condition.subject == &"expedition_hp" and condition.comparator == &"lt" \
				and condition.int_value >= 1 and condition.int_value <= 101 \
				and not condition.has_stable_id_value
		&"pool_copies_at_least":
			var referenced: ContentDefinition = _by_id.get(condition.stable_id_value)
			valid = condition.subject == &"pool" and condition.comparator == &"gte" \
				and condition.int_value >= 1 and condition.int_value <= 999 \
				and condition.has_stable_id_value and referenced is UnitDef
	if not valid:
		_issue(&"CONTENT_REWARD_CONDITION", source_id, &"reward_candidates.conditions", String(condition.kind))

func _validate_unlock_graph(definitions: Array[ContentDefinition]) -> void:
	var unlocks: Dictionary = {}
	var base_profiles: Array[UnlockDef] = []
	for definition in definitions:
		if definition is UnlockDef:
			unlocks[definition.id] = definition
			if definition.unlock_kind == &"base_profile": base_profiles.append(definition)
	for unlock_id in unlocks.keys():
		if _unlock_cycle_from(unlock_id as StringName, unlocks, {}, {}): _issue(&"CONTENT_UNLOCK_CYCLE", unlock_id as StringName, &"prerequisite_refs")
	if base_profiles.size() != 1:
		_issue(&"CONTENT_BASE_BUILD_MISSING", &"catalog.base_profile", &"count", str(base_profiles.size()))
		return
	var unit_ids: Array[StringName] = []
	for content_id in base_profiles[0].unlocked_content_refs:
		if _by_id.has(content_id) and _by_id[content_id] is UnitDef and (_by_id[content_id] as UnitDef).availability in [&"player", &"shared"]:
			unit_ids.append(content_id)
	if unit_ids.size() < 3: _issue(&"CONTENT_BASE_BUILD_MISSING", base_profiles[0].id, &"unlocked_content_refs", str(unit_ids.size()))
	var reachable_trait := false
	for definition in definitions:
		if not definition is TraitDef or definition.thresholds.is_empty(): continue
		var members := 0
		for unit_id in unit_ids:
			if (_by_id[unit_id] as UnitDef).trait_refs.has(definition.id): members += 1
		if members >= definition.thresholds[0].required_count: reachable_trait = true
	if not reachable_trait: _issue(&"CONTENT_BASE_BUILD_MISSING", base_profiles[0].id, &"trait_threshold")

func _unlock_cycle_from(current: StringName, unlocks: Dictionary, visiting: Dictionary, done: Dictionary) -> bool:
	if done.has(current): return false
	if visiting.has(current): return true
	visiting[current] = true
	var unlock: UnlockDef = unlocks[current]
	for prerequisite in unlock.prerequisite_refs:
		if unlocks.has(prerequisite) and _unlock_cycle_from(prerequisite, unlocks, visiting, done): return true
	visiting.erase(current)
	done[current] = true
	return false

func _validate_operations(definitions: Array[ContentDefinition]) -> void:
	for definition in definitions:
		if definition is EffectDef:
			var effect_definition := definition as EffectDef
			if not EFFECT_TRIGGERS.has(effect_definition.trigger):
				_issue(&"CONTENT_EFFECT_TRIGGER", effect_definition.id, &"trigger")
			if (effect_definition.trigger == &"periodic" \
				and (effect_definition.periodic_interval_ticks < 1 \
					or effect_definition.periodic_interval_ticks > 1800)) \
				or (effect_definition.trigger != &"periodic" \
					and effect_definition.periodic_interval_ticks != 0):
				_issue(&"CONTENT_EFFECT_TRIGGER", effect_definition.id, &"periodic_interval_ticks")
			if not STACKING_RULES.has(effect_definition.stacking) \
				or effect_definition.max_stacks < 1 \
				or effect_definition.max_stacks > 99 \
				or effect_definition.duration_ticks < 1 \
				or effect_definition.duration_ticks > 1800:
				_issue(&"CONTENT_OPERATION_INVALID", effect_definition.id, &"stacking")
			_validate_conditions(effect_definition)
			_validate_battle_operations(effect_definition.id, effect_definition.battle_operations, &"battle_operations")
			_validate_run_operations(effect_definition.id, effect_definition.run_operations, &"run_operations", &"battle_effect", true, false)
		elif definition is ConsumableDef:
			var consumable_definition := definition as ConsumableDef
			_validate_run_operations(consumable_definition.id, consumable_definition.run_operations, &"run_operations", &"consumable", false, false)
		elif definition is MapNodeDef:
			var map_definition := definition as MapNodeDef
			var allow_capacity := map_definition.node_type == &"event"
			_validate_run_operations(map_definition.id, map_definition.enter_operations, &"enter_operations", &"map_node", false, allow_capacity)
			_validate_run_operations(map_definition.id, map_definition.exit_operations, &"exit_operations", &"map_node", false, allow_capacity)
	_validate_effect_trigger_cycles(definitions)

func _validate_effect_trigger_cycles(
	definitions: Array[ContentDefinition]
) -> void:
	var reactive_damage_effects: Array[EffectDef] = []
	for definition: ContentDefinition in definitions:
		if not definition is EffectDef:
			continue
		var effect := definition as EffectDef
		if effect.trigger not in [&"hit", &"damaged", &"kill", &"death"]:
			continue
		var produces_damage := false
		for operation: BattleOperationDef in effect.battle_operations:
			if operation is DamageOperationDef:
				produces_damage = true
				break
		if produces_damage:
			reactive_damage_effects.append(effect)
	reactive_damage_effects.sort_custom(func(left: EffectDef, right: EffectDef) -> bool:
		return String(left.id) < String(right.id))
	for effect: EffectDef in reactive_damage_effects:
		if not _has_finite_use_bound(effect.conditions):
			_issue(
				&"CONTENT_EFFECT_TRIGGER_CYCLE",
				effect.id,
				&"conditions.max_uses_per_battle"
			)

func _has_finite_use_bound(conditions: Array[ConditionDef]) -> bool:
	for condition: ConditionDef in conditions:
		if condition != null and condition.kind == &"max_uses_per_battle" \
			and condition.has_max_uses_per_battle \
			and condition.max_uses_per_battle >= 1 \
			and condition.max_uses_per_battle <= 99:
			return true
	return false

func _validate_encounter_sources(definitions: Array[ContentDefinition]) -> void:
	for definition: ContentDefinition in definitions:
		if not definition is EncounterDef:
			continue
		var encounter := definition as EncounterDef
		var spawn_keys: Dictionary = {}
		for spawn_index: int in range(encounter.enemy_spawns.size()):
			var spawn: EnemySpawnDef = encounter.enemy_spawns[spawn_index]
			if spawn == null or not _strict_ascii_token(spawn.spawn_key):
				_issue(&"CONTENT_ENCOUNTER_SPAWN_KEY", encounter.id, &"enemy_spawns", str(spawn_index))
				continue
			if spawn_keys.has(spawn.spawn_key):
				_issue(&"CONTENT_ENCOUNTER_SPAWN_KEY", encounter.id, &"enemy_spawns", spawn.spawn_key)
			else:
				spawn_keys[spawn.spawn_key] = true
		var previous_phase := -1
		for phase_index: int in range(encounter.boss_phases.size()):
			var phase: BossPhaseDef = encounter.boss_phases[phase_index]
			if phase == null \
				or phase.phase_index <= previous_phase \
				or phase.hp_threshold_bps < 0 \
				or phase.hp_threshold_bps > 10000:
				_issue(&"CONTENT_BOSS_PHASE_INVALID", encounter.id, &"boss_phases", str(phase_index))
				continue
			previous_phase = phase.phase_index
			if not _strict_ascii_token(phase.source_spawn_key) \
				or not spawn_keys.has(phase.source_spawn_key):
				_issue(&"CONTENT_BOSS_PHASE_SOURCE", encounter.id, &"boss_phases.source_spawn_key", phase.source_spawn_key)

func _validate_combat_config(
	definitions: Array[ContentDefinition],
	entity_stress_minimum: int
) -> void:
	var configs: Array[CombatConfigDef] = []
	for definition: ContentDefinition in definitions:
		if definition is CombatConfigDef:
			configs.append(definition as CombatConfigDef)
	if configs.size() != 1:
		_issue(&"CONTENT_COMBAT_CONFIG_COUNT", &"config.combat_default", &"count", str(configs.size()))
		return
	var config: CombatConfigDef = configs[0]
	if config.id != &"config.combat_default":
		_issue(&"CONTENT_COMBAT_CONFIG_ID", config.id, &"id")
	var fixed_values := PackedInt32Array([
		config.simulation_version,
		config.tick_rate,
		config.board_width,
		config.board_height,
		config.soft_limit_ticks,
		config.hard_limit_ticks,
		config.progress_scale,
		config.resistance_base,
		config.basis_points,
		config.overtime_interval_ticks,
		config.main_actions_per_tick,
	])
	if fixed_values != PackedInt32Array([1, 20, 8, 8, 1200, 1800, 1000, 100, 10000, 20, 1]):
		_issue(&"CONTENT_COMBAT_CONFIG_FIXED", config.id, &"fixed_rules")
	if config.attack_mana_gain < 0 or config.attack_mana_gain > 100:
		_issue(&"CONTENT_COMBAT_CONFIG_TUNE", config.id, &"attack_mana_gain")
	if config.damage_mana_factor < 1 or config.damage_mana_factor > 100:
		_issue(&"CONTENT_COMBAT_CONFIG_TUNE", config.id, &"damage_mana_factor")
	if config.damage_mana_min < 0 or config.damage_mana_max > 100 \
		or config.damage_mana_min > config.damage_mana_max:
		_issue(&"CONTENT_COMBAT_CONFIG_TUNE", config.id, &"damage_mana")
	if config.overtime_step_bps < 1 or config.overtime_step_bps > 1000 \
		or config.overtime_cap_bps < config.overtime_step_bps \
		or config.overtime_cap_bps > 10000:
		_issue(&"CONTENT_COMBAT_CONFIG_TUNE", config.id, &"overtime")
	for value: int in [config.act1_base_damage, config.act2_base_damage, config.act3_base_damage]:
		if value < 1 or value > 100:
			_issue(&"CONTENT_COMBAT_CONFIG_TUNE", config.id, &"act_base_damage")
			break
	if config.survivor_damage < 0 or config.survivor_damage > 100 \
		or config.boss_damage < 0 or config.boss_damage > 100:
		_issue(&"CONTENT_COMBAT_CONFIG_TUNE", config.id, &"expedition_damage")
	if config.effect_resolution_budget < 64 or config.effect_resolution_budget > 65535:
		_issue(&"CONTENT_COMBAT_CONFIG_BUDGET", config.id, &"effect_resolution_budget")
	if config.operation_budget < config.effect_resolution_budget \
		or config.operation_budget > 65535:
		_issue(&"CONTENT_COMBAT_CONFIG_BUDGET", config.id, &"operation_budget")
	if config.event_budget < 64 or config.event_budget > 65535:
		_issue(&"CONTENT_COMBAT_CONFIG_BUDGET", config.id, &"event_budget")
	if config.entity_budget < 64 or config.entity_budget > 1024 \
		or config.entity_budget < entity_stress_minimum:
		_issue(&"CONTENT_COMBAT_CONFIG_BUDGET", config.id, &"entity_budget", str(entity_stress_minimum))

func _validate_conditions(effect: EffectDef) -> void:
	for condition in effect.conditions:
		if condition == null or not EFFECT_CONDITIONS.has(condition.kind):
			_issue(&"CONTENT_EFFECT_CONDITION", effect.id, &"conditions", "kind")
			continue
		if condition.kind in [&"health_below_bps", &"health_above_bps"] and (not condition.has_int_value or condition.int_value < 0 or condition.int_value > 10000):
			_issue(&"CONTENT_EFFECT_CONDITION", effect.id, &"conditions", "bps")
		if condition.kind in [&"distance_at_most", &"distance_at_least"] and (not condition.has_int_value or condition.int_value < 0 or condition.int_value > 7):
			_issue(&"CONTENT_EFFECT_CONDITION", effect.id, &"conditions", "distance")
		if condition.kind in [&"source_tag", &"target_tag", &"has_status", &"lacks_status", &"has_equipment"]:
			if not condition.has_stable_id_value or not _by_id.has(condition.stable_id_value): _issue(&"CONTENT_EFFECT_CONDITION", effect.id, &"conditions", "reference")
		if condition.has_max_uses_per_battle and (condition.max_uses_per_battle < 1 or condition.max_uses_per_battle > 99):
			_issue(&"CONTENT_EFFECT_CONDITION", effect.id, &"conditions", "uses")

func _validate_battle_operations(source_id: StringName, operations: Array[BattleOperationDef], field_path: StringName) -> void:
	for index in operations.size():
		var operation := operations[index]
		if operation == null or operation.operation_index != index or not _is_known_battle_operation(operation):
			_issue(&"CONTENT_OPERATION_INVALID", source_id, field_path, "index/type")
			continue
		if operation is DamageOperationDef:
			if operation.base < 0 or operation.scaling.is_empty() or operation.damage_type.is_empty() or operation.target.is_empty():
				_issue(&"CONTENT_OPERATION_INVALID", source_id, field_path, "damage")
		elif operation is HealOperationDef:
			if operation.base < 0 or operation.scaling.is_empty() or operation.target.is_empty():
				_issue(&"CONTENT_OPERATION_INVALID", source_id, field_path, "heal")
		elif operation is ShieldOperationDef:
			if operation.amount < 0 or operation.duration_ticks < 1 or operation.duration_ticks > 1800 or operation.target.is_empty():
				_issue(&"CONTENT_OPERATION_INVALID", source_id, field_path, "shield")
		elif operation is ModifyStatOperationDef:
			if operation.stat.is_empty() or operation.mode.is_empty() or operation.duration_ticks < 1 or operation.duration_ticks > 1800 or operation.target.is_empty():
				_issue(&"CONTENT_OPERATION_INVALID", source_id, field_path, "modify_stat")
		elif operation is ApplyStatusOperationDef:
			if operation.stacks < 1 or operation.stacks > 99 or operation.duration_ticks < 1 or operation.duration_ticks > 1800 or operation.target.is_empty():
				_issue(&"CONTENT_OPERATION_INVALID", source_id, field_path, "status")
		elif operation is RemoveStatusOperationDef:
			if operation.target.is_empty(): _issue(&"CONTENT_OPERATION_INVALID", source_id, field_path, "remove_status")
		elif operation is MoveOperationDef:
			if operation.cells < 0 or operation.cells > 7 or operation.direction_or_target.is_empty():
				_issue(&"CONTENT_OPERATION_INVALID", source_id, field_path, "move")
		elif operation is SummonOperationDef:
			if operation.count < 1 or operation.count > 64 or operation.max_active_per_source < 1 or operation.max_active_per_source > 64:
				_issue(&"CONTENT_ENTITY_BOUND", source_id, field_path, "summon_bound")
			if operation.placement_rule.is_empty(): _issue(&"CONTENT_OPERATION_INVALID", source_id, field_path, "summon")
		elif operation is GrantManaOperationDef:
			if operation.amount < 0 or operation.target.is_empty(): _issue(&"CONTENT_OPERATION_INVALID", source_id, field_path, "grant_mana")

func _is_known_battle_operation(operation: BattleOperationDef) -> bool:
	return operation is DamageOperationDef \
		or operation is HealOperationDef \
		or operation is ShieldOperationDef \
		or operation is ModifyStatOperationDef \
		or operation is ApplyStatusOperationDef \
		or operation is RemoveStatusOperationDef \
		or operation is MoveOperationDef \
		or operation is SummonOperationDef \
		or operation is GrantManaOperationDef

func _validate_run_operations(
	source_id: StringName,
	operations: Array[RunOperationDef],
	field_path: StringName,
	source_context: StringName,
	battle_source: bool,
	allow_capacity: bool
) -> void:
	for index in operations.size():
		var operation := operations[index]
		if operation == null or operation.operation_index != index or not _is_known_run_operation(operation):
			_issue(&"CONTENT_OPERATION_INVALID", source_id, field_path, "%s:index/type" % String(source_context))
			continue
		if operation is AddGoldOperationDef or operation is AddXpOperationDef or operation is HealExpeditionHpOperationDef:
			if _scalar_run_amount(operation) < 0 or _scalar_run_claim_scope(operation) not in [&"once_per_node", &"on_first_clear"]:
				var scalar_code := &"CONTENT_RUN_INTENT_FORBIDDEN" if battle_source else &"CONTENT_OPERATION_INVALID"
				_issue(scalar_code, source_id, field_path, "%s:amount/scope" % String(source_context))
			continue
		if not allow_capacity:
			_issue(&"CONTENT_RUN_INTENT_FORBIDDEN", source_id, field_path, "%s:capacity" % String(source_context))
		if operation is ModifyUnitPoolOperationDef:
			if not _stable_id_validator.is_valid(operation.unit_ref) \
				or not _by_id.has(operation.unit_ref) \
				or not _by_id[operation.unit_ref] is UnitDef \
				or operation.count == 0:
				_issue(&"CONTENT_OPERATION_INVALID", source_id, field_path, "modify_pool")
		elif operation is GrantItemOperationDef:
			if not _stable_id_validator.is_valid(operation.content_ref) \
				or not _is_item_content_ref(operation.content_ref) \
				or operation.count < 1:
				_issue(&"CONTENT_OPERATION_INVALID", source_id, field_path, "grant_item")
		elif operation is GrantRelicOperationDef:
			if not _stable_id_validator.is_valid(operation.relic_ref) or not _by_id.has(operation.relic_ref) or not _by_id[operation.relic_ref] is RelicDef:
				_issue(&"CONTENT_OPERATION_INVALID", source_id, field_path, "grant_relic")
		elif operation is PopulationSourceOperationDef:
			if not _stable_id_validator.is_valid(operation.source_id) or operation.amount < 1:
				_issue(&"CONTENT_OPERATION_INVALID", source_id, field_path, "population_source")

func _is_known_run_operation(operation: RunOperationDef) -> bool:
	return operation is AddGoldOperationDef \
		or operation is AddXpOperationDef \
		or operation is HealExpeditionHpOperationDef \
		or operation is ModifyUnitPoolOperationDef \
		or operation is GrantItemOperationDef \
		or operation is GrantRelicOperationDef \
		or operation is PopulationSourceOperationDef

func _scalar_run_amount(operation: RunOperationDef) -> int:
	if operation is AddGoldOperationDef: return (operation as AddGoldOperationDef).amount
	if operation is AddXpOperationDef: return (operation as AddXpOperationDef).amount
	if operation is HealExpeditionHpOperationDef: return (operation as HealExpeditionHpOperationDef).amount
	return 0

func _scalar_run_claim_scope(operation: RunOperationDef) -> StringName:
	if operation is AddGoldOperationDef: return (operation as AddGoldOperationDef).claim_scope
	if operation is AddXpOperationDef: return (operation as AddXpOperationDef).claim_scope
	if operation is HealExpeditionHpOperationDef: return (operation as HealExpeditionHpOperationDef).claim_scope
	return &""

func _is_item_content_ref(content_id: StringName) -> bool:
	if not _by_id.has(content_id): return false
	var definition: ContentDefinition = _by_id[content_id]
	return definition is ItemComponentDef or definition is EquipmentDef or definition is ConsumableDef

func _calculate_population_and_entities(input: ContentValidationInput, report: ContentValidationReport) -> void:
	var relic_bonuses: Array[int] = []
	var commander_bonus := 0
	var source_bonuses: Dictionary = {}
	for definition in input.definitions:
		if definition is RelicDef and definition.population_bonus > 0: relic_bonuses.append(definition.population_bonus)
		elif definition is CommanderDef: commander_bonus = maxi(commander_bonus, definition.population_bonus)
		elif definition is MapNodeDef:
			var map_definition := definition as MapNodeDef
			if map_definition.node_type == &"event":
				_collect_population_bonuses(map_definition.enter_operations, source_bonuses)
				_collect_population_bonuses(map_definition.exit_operations, source_bonuses)
	relic_bonuses.sort()
	var relic_total := 0
	for index in mini(5, relic_bonuses.size()): relic_total += relic_bonuses[relic_bonuses.size() - 1 - index]
	var extra := relic_total + commander_bonus
	for value in source_bonuses.values(): extra += int(value)
	report.version_maximum_population = input.base_population_cap + extra
	report.per_side_stress_minimum = maxi(16, report.version_maximum_population + 4)
	if report.version_maximum_population < input.base_population_cap: _issue(&"CONTENT_POPULATION_BOUND", &"catalog.population", &"maximum")
	var summon_bounds: Dictionary = {}
	for definition in input.definitions:
		if definition is UnitDef: summon_bounds[definition.id] = _unit_summon_bound(definition)
	for definition in input.definitions:
		if not definition is UnitDef: continue
		var targets := _unit_summon_targets(definition)
		for target in targets:
			if int(summon_bounds.get(target, 0)) > 0: _issue(&"CONTENT_ENTITY_BOUND", definition.id, &"summon", "chain")
			if _has_summon_cycle(definition.id, definition.id, {}): _issue(&"CONTENT_ENTITY_BOUND", definition.id, &"summon", "cycle")
	var player_best := 0
	for definition in input.definitions:
		if definition is UnitDef and definition.availability in [&"player", &"shared"]: player_best = maxi(player_best, int(summon_bounds.get(definition.id, 0)))
	var player_entities := report.version_maximum_population * (1 + player_best)
	var enemy_entities := 0
	for definition in input.definitions:
		if not definition is EncounterDef: continue
		var encounter := definition as EncounterDef
		var current: int = encounter.enemy_spawns.size()
		for spawn in encounter.enemy_spawns: current += int(summon_bounds.get(spawn.unit_ref, 0))
		enemy_entities = maxi(enemy_entities, current)
	report.maximum_simultaneous_entities = player_entities + enemy_entities
	report.entity_stress_minimum = maxi(64, report.maximum_simultaneous_entities)

func _collect_population_bonuses(operations: Array[RunOperationDef], source_bonuses: Dictionary) -> void:
	for operation in operations:
		if operation is PopulationSourceOperationDef and operation.amount > 0:
			source_bonuses[operation.source_id] = maxi(int(source_bonuses.get(operation.source_id, 0)), operation.amount)

func _unit_summon_bound(unit: UnitDef) -> int:
	if not unit.has_ability_ref or not _by_id.has(unit.ability_ref) or not _by_id[unit.ability_ref] is AbilityDef: return 0
	var ability: AbilityDef = _by_id[unit.ability_ref]
	var total := 0
	for effect_id in ability.effect_refs:
		if not _by_id.has(effect_id) or not _by_id[effect_id] is EffectDef: continue
		for operation in (_by_id[effect_id] as EffectDef).battle_operations:
			if operation is SummonOperationDef: total += operation.max_active_per_source
	return total

func _unit_summon_targets(unit: UnitDef) -> Array[StringName]:
	var result: Array[StringName] = []
	if not unit.has_ability_ref or not _by_id.has(unit.ability_ref) or not _by_id[unit.ability_ref] is AbilityDef: return result
	for effect_id in (_by_id[unit.ability_ref] as AbilityDef).effect_refs:
		if not _by_id.has(effect_id) or not _by_id[effect_id] is EffectDef: continue
		for operation in (_by_id[effect_id] as EffectDef).battle_operations:
			if operation is SummonOperationDef: result.append(operation.unit_ref)
	return result

func _has_summon_cycle(origin: StringName, current: StringName, visited: Dictionary) -> bool:
	if visited.has(current): return current == origin
	visited[current] = true
	if _by_id.has(current) and _by_id[current] is UnitDef:
		for target in _unit_summon_targets(_by_id[current]):
			if target == origin or _has_summon_cycle(origin, target, visited.duplicate()): return true
	return false

func _issue(code: StringName, source_id: StringName, path: StringName, detail: String = "") -> void:
	_issues.append(ContentValidationIssue.new(code, source_id, path, detail))

func _issue_less(left: ContentValidationIssue, right: ContentValidationIssue) -> bool:
	if left.code != right.code: return String(left.code) < String(right.code)
	if left.source_id != right.source_id: return String(left.source_id) < String(right.source_id)
	return String(left.field_path) < String(right.field_path)

func _string_name_less(left: StringName, right: StringName) -> bool:
	return String(left) < String(right)

func _strict_ascii_token(value: String) -> bool:
	if value.is_empty():
		return false
	for byte: int in value.to_utf8_buffer():
		if byte < 33 or byte > 126:
			return false
	return true
