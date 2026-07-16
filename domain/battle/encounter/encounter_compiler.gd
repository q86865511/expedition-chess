class_name EncounterCompiler
extends RefCounted

const INPUT_INVALID: StringName = &"ENCOUNTER_COMPILE_INPUT_INVALID"
const GENERATION_MISMATCH: StringName = &"ENCOUNTER_GENERATION_MISMATCH"
const RULE_MISSING: StringName = &"ENCOUNTER_RULE_MISSING"
const RULE_INVALID: StringName = &"ENCOUNTER_RULE_INVALID"
const SPAWN_KEY_DUPLICATE: StringName = &"ENCOUNTER_SPAWN_KEY_DUPLICATE"
const ENTITY_ID_COLLISION: StringName = &"BATTLE_ENTITY_ID_COLLISION"
const BOSS_SOURCE_MISSING: StringName = &"ENCOUNTER_BOSS_SOURCE_MISSING"
const MAX_U32: int = 0xffffffff
const I32_MIN: int = -2147483648
const I32_MAX: int = 2147483647
const BASIS_POINTS: int = 10000

var _entity_ids := BattleEntityIdCodecV1.new()
var _stable_ids := StableIdValidator.new()

func compile(
	request: EncounterCompileRequest,
	catalog: BattleRuleCatalog
) -> EncounterCompileResult:
	var input_error := _validate_request(request, catalog)
	if input_error != null:
		return EncounterCompileResult.failure(
			input_error.code,
			input_error.field_path,
			input_error.source_id
		)
	var encounter := catalog.try_encounter_rule(request.encounter_id)
	if encounter == null:
		return EncounterCompileResult.failure(
			RULE_MISSING, &"encounter_id", request.encounter_id
		)
	if encounter.encounter_id != request.encounter_id \
		or encounter.preview_schema_version != 1:
		return EncounterCompileResult.failure(
			RULE_INVALID, &"encounter", request.encounter_id
		)
	var preview := EncounterPreviewSnapshot.new()
	preview.preview_schema_version = encounter.preview_schema_version
	preview.encounter_id = request.encounter_id
	preview.manifest_digest = StringName(request.manifest_digest)
	var spawn_keys: Array[String] = []
	var spawn_instance_ids: Array[StringName] = []
	var occupied_cells: Dictionary = {}
	var seen_entity_ids: Dictionary = {}
	for index: int in range(encounter.enemy_spawns.size()):
		var spawn := encounter.enemy_spawns[index]
		var path := StringName("encounter.enemy_spawns.%d" % index)
		if spawn == null or spawn.side != &"enemy" \
			or spawn.logical_y < 4 or spawn.logical_y > 7 \
			or spawn.logical_x < 0 or spawn.logical_x > 7 \
			or spawn.star < 1 or spawn.star > 3:
			return EncounterCompileResult.failure(
				RULE_INVALID, path, request.encounter_id
			)
		if spawn_keys.has(spawn.spawn_key):
			return EncounterCompileResult.failure(
				SPAWN_KEY_DUPLICATE,
				StringName("%s.spawn_key" % path),
				request.encounter_id
			)
		var cell_key := spawn.logical_y * 8 + spawn.logical_x
		if occupied_cells.has(cell_key):
			return EncounterCompileResult.failure(
				RULE_INVALID, StringName("%s.cell" % path), request.encounter_id
			)
		var encoded_id := _entity_ids.encode_enemy(request.node_id, spawn.spawn_key)
		if not encoded_id.ok:
			return EncounterCompileResult.failure(
				encoded_id.error.code,
				StringName("%s.%s" % [path, encoded_id.error.field_path]),
				request.encounter_id
			)
		if seen_entity_ids.has(encoded_id.entity_id):
			return EncounterCompileResult.failure(
				ENTITY_ID_COLLISION,
				StringName("%s.instance_id" % path),
				encoded_id.entity_id
			)
		var unit_rule := catalog.try_unit_rule(spawn.unit_id)
		if unit_rule == null:
			return EncounterCompileResult.failure(
				RULE_MISSING, StringName("%s.unit_id" % path), spawn.unit_id
			)
		var scaling := _find_scaling(unit_rule.star_scalings, spawn.star)
		if not _unit_rule_valid(unit_rule, scaling):
			return EncounterCompileResult.failure(
				RULE_INVALID, StringName("%s.unit_id" % path), spawn.unit_id
			)
		var reference_error := _validate_unit_references(
			unit_rule, spawn, catalog, path
		)
		if reference_error != null:
			return EncounterCompileResult.failure(
				reference_error.code,
				reference_error.field_path,
				reference_error.source_id
			)
		var unit := _build_unit_snapshot(
			encoded_id.entity_id, spawn, unit_rule, scaling
		)
		preview.enemy_units.append(unit)
		spawn_keys.append(spawn.spawn_key)
		spawn_instance_ids.append(encoded_id.entity_id)
		seen_entity_ids[encoded_id.entity_id] = true
		occupied_cells[cell_key] = true
	preview.enemy_units.sort_custom(_unit_before)
	var traits_result := _compile_traits(preview.enemy_units, catalog)
	if not traits_result.ok:
		return traits_result
	preview.active_traits = traits_result.preview.active_traits
	var affix_result := _compile_affixes(encounter.affix_ids, catalog)
	if not affix_result.ok:
		return affix_result
	preview.affix_effects = affix_result.preview.affix_effects
	var phase_result := _compile_phases(
		encounter.boss_phases,
		spawn_keys,
		spawn_instance_ids,
		catalog
	)
	if not phase_result.ok:
		return phase_result
	preview.boss_phases = phase_result.preview.boss_phases
	var validation := EncounterPreviewValidator.new().validate(preview)
	if not validation.ok:
		return EncounterCompileResult.failure(
			validation.error.code,
			validation.error.field_path,
			validation.error.source_id
		)
	return EncounterCompileResult.success(preview)

func _validate_request(
	request: EncounterCompileRequest,
	catalog: BattleRuleCatalog
) -> EncounterCompileError:
	if request == null:
		return EncounterCompileError.create(INPUT_INVALID, &"request")
	if catalog == null:
		return EncounterCompileError.create(INPUT_INVALID, &"catalog")
	if not _is_digest(request.manifest_digest):
		return EncounterCompileError.create(INPUT_INVALID, &"manifest_digest")
	if request.manifest_digest != catalog.manifest_digest_value():
		return EncounterCompileError.create(
			GENERATION_MISMATCH, &"manifest_digest", request.encounter_id
		)
	if not _stable_ids.is_valid(request.encounter_id):
		return EncounterCompileError.create(
			INPUT_INVALID, &"encounter_id", request.encounter_id
		)
	if not _is_u32(request.act_index):
		return EncounterCompileError.create(INPUT_INVALID, &"act_index")
	if not _is_u32(request.depth):
		return EncounterCompileError.create(INPUT_INVALID, &"depth")
	if not _is_u32(request.challenge_level):
		return EncounterCompileError.create(INPUT_INVALID, &"challenge_level")
	var node_probe := _entity_ids.encode_enemy(request.node_id, "probe")
	if not node_probe.ok:
		return EncounterCompileError.create(INPUT_INVALID, &"node_id")
	return null

func _validate_unit_references(
	unit_rule: BattleUnitRule,
	spawn: BattleEnemySpawnRule,
	catalog: BattleRuleCatalog,
	path: StringName
) -> EncounterCompileError:
	if unit_rule.ability_id != null \
		and catalog.try_ability_rule(unit_rule.ability_id.value) == null:
		return EncounterCompileError.create(
			RULE_MISSING,
			StringName("%s.ability_id" % path),
			unit_rule.ability_id.value
		)
	for trait_id: StringName in unit_rule.trait_ids:
		if catalog.try_trait_rule(trait_id) == null:
			return EncounterCompileError.create(
				RULE_MISSING, StringName("%s.trait_ids" % path), trait_id
			)
	var effect_ids: Array[StringName] = unit_rule.effect_ids.duplicate()
	effect_ids.append_array(spawn.effect_ids)
	effect_ids.sort_custom(_string_name_before)
	for index: int in range(effect_ids.size()):
		var effect_id: StringName = effect_ids[index]
		if index > 0 and effect_ids[index - 1] == effect_id:
			return EncounterCompileError.create(
				RULE_INVALID, StringName("%s.effect_ids" % path), effect_id
			)
		if catalog.try_effect_rule(effect_id) == null:
			return EncounterCompileError.create(
				RULE_MISSING, StringName("%s.effect_ids" % path), effect_id
			)
	return null

func _build_unit_snapshot(
	instance_id: StringName,
	spawn: BattleEnemySpawnRule,
	unit_rule: BattleUnitRule,
	scaling: BattleStarScalingRule
) -> UnitBattleSnapshot:
	var unit := UnitBattleSnapshot.new()
	unit.instance_id = instance_id
	unit.unit_id = unit_rule.unit_id
	unit.side = &"enemy"
	unit.logical_y = spawn.logical_y
	unit.logical_x = spawn.logical_x
	unit.star = spawn.star
	unit.health = _scaled(unit_rule.base_stats.health, scaling.health_bps)
	unit.attack = _scaled(unit_rule.base_stats.attack, scaling.attack_bps)
	unit.armor = _scaled(unit_rule.base_stats.armor, scaling.armor_bps)
	unit.magic_resist = _scaled(
		unit_rule.base_stats.magic_resist, scaling.magic_resist_bps
	)
	unit.attack_speed_milli = _scaled(
		unit_rule.base_stats.attack_speed_milli, scaling.attack_speed_bps
	)
	unit.attack_range_cells = _scaled(
		unit_rule.base_stats.attack_range_cells, scaling.attack_range_bps
	)
	unit.start_mana = _scaled(
		unit_rule.base_stats.start_mana, scaling.start_mana_bps
	)
	unit.max_mana = _scaled(
		unit_rule.base_stats.max_mana, scaling.max_mana_bps
	)
	unit.move_speed_milli = _scaled(
		unit_rule.base_stats.move_speed_milli, scaling.move_speed_bps
	)
	unit.basic_attack_profile = unit_rule.basic_attack_profile
	unit.ability_id = unit_rule.ability_id.deep_clone() \
		if unit_rule.ability_id != null else null
	unit.effect_ids = unit_rule.effect_ids.duplicate()
	unit.effect_ids.append_array(spawn.effect_ids)
	unit.effect_ids.sort_custom(_string_name_before)
	for effect_index: int in range(unit.effect_ids.size()):
		var assignment := BattleEffectSourceAssignmentSnapshot.new()
		assignment.priority = 0
		assignment.source_category = &"unit"
		assignment.source_side = &"enemy"
		assignment.source_stable_id = unit.unit_id
		assignment.source_instance_id = OptionalStringNameValue.of(unit.instance_id)
		assignment.source_slot = 0
		assignment.effect_index = effect_index
		assignment.effect_id = unit.effect_ids[effect_index]
		unit.effect_assignments.append(assignment)
	return unit

func _compile_traits(
	units: Array[UnitBattleSnapshot],
	catalog: BattleRuleCatalog
) -> EncounterCompileResult:
	var trait_ids: Array[StringName] = []
	for unit: UnitBattleSnapshot in units:
		var unit_rule := catalog.try_unit_rule(unit.unit_id)
		if unit_rule == null:
			return EncounterCompileResult.failure(
				RULE_MISSING, &"enemy_units.unit_id", unit.unit_id
			)
		for trait_id: StringName in unit_rule.trait_ids:
			if not trait_ids.has(trait_id):
				trait_ids.append(trait_id)
	trait_ids.sort_custom(_string_name_before)
	var partial := EncounterPreviewSnapshot.new()
	for trait_id: StringName in trait_ids:
		var trait_rule := catalog.try_trait_rule(trait_id)
		if trait_rule == null:
			return EncounterCompileResult.failure(
				RULE_MISSING, &"active_traits.trait_id", trait_id
			)
		var members: Array[StringName] = []
		for unit: UnitBattleSnapshot in units:
			var unit_rule := catalog.try_unit_rule(unit.unit_id)
			if unit_rule != null and unit_rule.trait_ids.has(trait_id):
				members.append(unit.instance_id)
		members.sort_custom(_string_name_before)
		var active_tier := 0
		var previous_required := 0
		for threshold_index: int in range(trait_rule.thresholds.size()):
			var threshold := trait_rule.thresholds[threshold_index]
			if threshold == null or threshold.required_count <= previous_required:
				return EncounterCompileResult.failure(
					RULE_INVALID, &"active_traits.thresholds", trait_id
				)
			for effect_id: StringName in threshold.effect_ids:
				if catalog.try_effect_rule(effect_id) == null:
					return EncounterCompileResult.failure(
						RULE_MISSING, &"active_traits.effect_ids", effect_id
					)
			if members.size() >= threshold.required_count:
				active_tier = threshold_index + 1
			previous_required = threshold.required_count
		if active_tier == 0:
			continue
		var trait_snapshot := TraitBattleSnapshot.new()
		trait_snapshot.trait_id = trait_id
		trait_snapshot.tier = active_tier
		trait_snapshot.member_instance_ids = members
		var active_effect_ids: Array[StringName] = \
			trait_rule.thresholds[active_tier - 1].effect_ids.duplicate()
		active_effect_ids.sort_custom(_string_name_before)
		for effect_index: int in range(active_effect_ids.size()):
			var assignment := BattleEffectSourceAssignmentSnapshot.new()
			assignment.priority = 0
			assignment.source_category = &"trait"
			assignment.source_side = &"enemy"
			assignment.source_stable_id = trait_id
			assignment.source_slot = 0
			assignment.effect_index = effect_index
			assignment.effect_id = active_effect_ids[effect_index]
			trait_snapshot.effect_assignments.append(assignment)
		partial.active_traits.append(trait_snapshot)
	return EncounterCompileResult.success(partial)

func _compile_affixes(
	affix_ids: Array[StringName],
	catalog: BattleRuleCatalog
) -> EncounterCompileResult:
	var sorted_ids: Array[StringName] = affix_ids.duplicate()
	sorted_ids.sort_custom(_string_name_before)
	var partial := EncounterPreviewSnapshot.new()
	for index: int in range(sorted_ids.size()):
		var effect_id: StringName = sorted_ids[index]
		if index > 0 and sorted_ids[index - 1] == effect_id:
			return EncounterCompileResult.failure(
				RULE_INVALID, &"encounter.affix_ids", effect_id
			)
		if catalog.try_effect_rule(effect_id) == null:
			return EncounterCompileResult.failure(
				RULE_MISSING, &"encounter.affix_ids", effect_id
			)
		var effect := BattleEffectSourceAssignmentSnapshot.new()
		effect.priority = 0
		effect.source_category = &"encounter_affix"
		effect.source_side = &"enemy"
		effect.source_stable_id = effect_id
		effect.source_slot = 0
		effect.effect_index = 0
		effect.effect_id = effect_id
		partial.affix_effects.append(effect)
	return EncounterCompileResult.success(partial)

func _compile_phases(
	phase_rules: Array[BattleBossPhaseRule],
	spawn_keys: Array[String],
	spawn_instance_ids: Array[StringName],
	catalog: BattleRuleCatalog
) -> EncounterCompileResult:
	var sorted_phases: Array[BattleBossPhaseRule] = []
	for rule: BattleBossPhaseRule in phase_rules:
		if rule == null:
			return EncounterCompileResult.failure(
				RULE_INVALID, &"encounter.boss_phases"
			)
		sorted_phases.append(rule.deep_clone())
	sorted_phases.sort_custom(_phase_before)
	var partial := EncounterPreviewSnapshot.new()
	var previous_phase := -1
	for index: int in range(sorted_phases.size()):
		var rule := sorted_phases[index]
		var path := StringName("encounter.boss_phases.%d" % index)
		if not _is_u32(rule.phase_index) \
			or rule.phase_index <= previous_phase \
			or rule.hp_threshold_bps < 0 \
			or rule.hp_threshold_bps > BASIS_POINTS:
			return EncounterCompileResult.failure(RULE_INVALID, path)
		var source_index := spawn_keys.find(rule.source_spawn_key)
		if source_index < 0:
			return EncounterCompileResult.failure(
				BOSS_SOURCE_MISSING,
				StringName("%s.source_spawn_key" % path),
				StringName(rule.source_spawn_key)
			)
		var effect_ids: Array[StringName] = rule.effect_ids.duplicate()
		effect_ids.sort_custom(_string_name_before)
		for effect_index: int in range(effect_ids.size()):
			var effect_id: StringName = effect_ids[effect_index]
			var is_duplicate: bool = effect_index > 0 \
				and effect_ids[effect_index - 1] == effect_id
			if is_duplicate or catalog.try_effect_rule(effect_id) == null:
				var error_code: StringName = RULE_INVALID \
					if is_duplicate else RULE_MISSING
				return EncounterCompileResult.failure(
					error_code,
					StringName("%s.effect_ids" % path),
					effect_id
				)
		var phase := BossPhaseSnapshot.new()
		phase.phase_index = rule.phase_index
		phase.hp_threshold_bps = rule.hp_threshold_bps
		phase.source_instance_id = spawn_instance_ids[source_index]
		phase.effect_ids = effect_ids
		partial.boss_phases.append(phase)
		previous_phase = rule.phase_index
	return EncounterCompileResult.success(partial)

func _find_scaling(
	values: Array[BattleStarScalingRule],
	star: int
) -> BattleStarScalingRule:
	for value: BattleStarScalingRule in values:
		if value != null and value.star == star:
			return value.deep_clone()
	return null

func _unit_rule_valid(
	unit_rule: BattleUnitRule,
	scaling: BattleStarScalingRule
) -> bool:
	if unit_rule == null or unit_rule.base_stats == null or scaling == null:
		return false
	var base_values := PackedInt64Array([
		unit_rule.base_stats.health,
		unit_rule.base_stats.attack,
		unit_rule.base_stats.armor,
		unit_rule.base_stats.magic_resist,
		unit_rule.base_stats.attack_speed_milli,
		unit_rule.base_stats.attack_range_cells,
		unit_rule.base_stats.start_mana,
		unit_rule.base_stats.max_mana,
		unit_rule.base_stats.move_speed_milli,
	])
	var multipliers := PackedInt64Array([
		scaling.health_bps,
		scaling.attack_bps,
		scaling.armor_bps,
		scaling.magic_resist_bps,
		scaling.attack_speed_bps,
		scaling.attack_range_bps,
		scaling.start_mana_bps,
		scaling.max_mana_bps,
		scaling.move_speed_bps,
	])
	var scaled: Array[int] = []
	for index: int in range(base_values.size()):
		if not _is_i32(base_values[index]) \
			or multipliers[index] < 1 \
			or multipliers[index] > 100000:
			return false
		var value := _scaled(base_values[index], multipliers[index])
		if not _is_i32(value):
			return false
		scaled.append(value)
	return scaled[0] > 0 \
		and scaled[1] >= 0 \
		and scaled[4] > 0 \
		and scaled[5] >= 0 and scaled[5] <= 7 \
		and scaled[6] >= 0 \
		and scaled[7] >= scaled[6] \
		and scaled[8] > 0

func _scaled(base_value: int, multiplier_bps: int) -> int:
	@warning_ignore("integer_division")
	var result: int = (base_value * multiplier_bps) / BASIS_POINTS
	return result

func _unit_before(left: UnitBattleSnapshot, right: UnitBattleSnapshot) -> bool:
	if left.logical_y != right.logical_y:
		return left.logical_y < right.logical_y
	if left.logical_x != right.logical_x:
		return left.logical_x < right.logical_x
	return String(left.instance_id) < String(right.instance_id)

func _phase_before(left: BattleBossPhaseRule, right: BattleBossPhaseRule) -> bool:
	return left.phase_index < right.phase_index

func _string_name_before(left: StringName, right: StringName) -> bool:
	return String(left) < String(right)

func _is_digest(value: String) -> bool:
	if value.length() != 64:
		return false
	for index: int in range(value.length()):
		var code := value.unicode_at(index)
		if not (code >= 48 and code <= 57) \
			and not (code >= 97 and code <= 102):
			return false
	return true

func _is_u32(value: int) -> bool:
	return value >= 0 and value <= MAX_U32

func _is_i32(value: int) -> bool:
	return value >= I32_MIN and value <= I32_MAX
