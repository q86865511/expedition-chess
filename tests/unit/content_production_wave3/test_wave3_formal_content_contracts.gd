extends GutTest

const PACK_ROOT := "res://content/packs/vertical_slice"
const EXPECTED_UNIT_COUNT := 44
const EXPECTED_EVENT_SET_COUNT := 12
const REQUIRED_RUNTIME_SCRIPTS: Array[String] = [
	"res://application/run/commands/commit_node_choice_command.gd",
	"res://application/run/commands/cancel_node_choice_command.gd",
	"res://application/run/commit_node_choice_service.gd",
]


func test_every_unit_has_one_formal_ability_primary_effect_and_presentation() -> void:
	var units := _load_resources("%s/units" % PACK_ROOT)
	var abilities := _load_resources("%s/abilities" % PACK_ROOT)
	var primary_effects := _load_resources("%s/unit_effects" % PACK_ROOT)
	var presentations := _load_resources("%s/unit_presentations" % PACK_ROOT)
	assert_eq(units.size(), EXPECTED_UNIT_COUNT)
	assert_eq(abilities.size(), EXPECTED_UNIT_COUNT)
	assert_eq(primary_effects.size(), EXPECTED_UNIT_COUNT)
	assert_eq(presentations.size(), EXPECTED_UNIT_COUNT)
	if (
		units.size() != EXPECTED_UNIT_COUNT
		or abilities.size() != EXPECTED_UNIT_COUNT
		or primary_effects.size() != EXPECTED_UNIT_COUNT
		or presentations.size() != EXPECTED_UNIT_COUNT
	):
		return

	var ability_by_id := _index_by_id(abilities)
	var effect_by_id := _index_by_id(primary_effects)
	var presentation_by_id := _index_by_id(presentations)
	var dedicated_effect_ids: Dictionary = {}
	for unit: Resource in units:
		assert_eq(unit.schema_version, 2, "unit must use V3 resource schema")
		assert_true(unit.has_ability_ref, "%s lacks an ability" % unit.id)
		assert_true(ability_by_id.has(unit.ability_ref), "%s ability missing" % unit.id)
		assert_true(
			presentation_by_id.has(unit.presentation_ref),
			"%s presentation missing" % unit.id
		)
		if not ability_by_id.has(unit.ability_ref):
			continue
		var ability: Resource = ability_by_id[unit.ability_ref]
		assert_eq(ability.effect_refs.size(), 1, "%s needs one primary effect" % ability.id)
		if ability.effect_refs.size() != 1:
			continue
		var effect_id: StringName = ability.effect_refs[0]
		assert_true(effect_by_id.has(effect_id), "%s primary effect missing" % ability.id)
		assert_false(
			dedicated_effect_ids.has(effect_id),
			"%s is reused by multiple formal abilities" % effect_id
		)
		dedicated_effect_ids[effect_id] = true
		assert_false(
			unit.effect_refs.has(effect_id),
			"ability primary effects must not masquerade as innate unit effects"
		)
		if effect_by_id.has(effect_id):
			var effect: Resource = effect_by_id[effect_id]
			assert_eq(effect.schema_version, 2)
			assert_ne(effect.description_key, &"")


func test_formal_roster_preserves_player_monster_split_and_base_economy() -> void:
	var units := _load_resources("%s/units" % PACK_ROOT)
	var player_count := 0
	var monster_count := 0
	var player_cost_counts := {1: 0, 2: 0, 3: 0, 4: 0, 5: 0}
	for unit: Resource in units:
		if unit.availability == &"player":
			player_count += 1
			player_cost_counts[unit.cost_tier] += 1
		elif unit.availability == &"monster":
			monster_count += 1
	assert_eq(player_count, 32)
	assert_eq(monster_count, 12)
	assert_eq(player_cost_counts, {1: 10, 2: 8, 3: 6, 4: 5, 5: 3})


func test_event_rest_and_treasure_choice_sets_are_substantive() -> void:
	var choice_sets := _load_resources("%s/node_choices" % PACK_ROOT)
	var event_count := 0
	var rest_found := false
	var treasure_found := false
	for choice_set: Resource in choice_sets:
		var operation_signatures: Dictionary = {}
		for choice: Resource in choice_set.choices:
			assert_ne(choice.choice_id, &"")
			assert_ne(choice.title_key, &"")
			assert_ne(choice.description_key, &"")
			assert_ne(choice.preview_key, &"")
			assert_ne(choice.result_key, &"")
			assert_true(
				not choice.operations.is_empty()
				or choice.has_reward_table_ref
				or choice.outcome_kind != NodeChoiceDef.OutcomeKind.APPLY_AND_COMPLETE,
				"%s must produce a typed, observable outcome" % choice.choice_id
			)
			operation_signatures[
				"%s|%s|%s" % [
					choice.outcome_kind,
					choice.reward_table_ref,
					choice.operations.size(),
				]
			] = true
		assert_eq(
			operation_signatures.size(),
			choice_set.choices.size(),
			"%s choices must have materially different costs/outcomes" % choice_set.id
		)
		match choice_set.node_kind:
			&"event":
				event_count += 1
				assert_gte(choice_set.choices.size(), 2)
			&"rest":
				rest_found = true
				assert_eq(choice_set.choices.size(), 2)
				assert_eq(choice_set.choices[0].choice_id, &"choice.rest.heal_20")
				assert_eq(
					choice_set.choices[1].outcome_kind,
					NodeChoiceDef.OutcomeKind.OPEN_DISMANTLE_SERVICE
				)
			&"treasure":
				treasure_found = true
				assert_gte(choice_set.choices.size(), 3)
	assert_eq(event_count, EXPECTED_EVENT_SET_COUNT)
	assert_true(rest_found)
	assert_true(treasure_found)


func test_at_least_one_boss_has_multiple_ordered_phases() -> void:
	var encounters := _load_resources("%s/encounters" % PACK_ROOT)
	var found_multiphase := false
	for encounter: Resource in encounters:
		if encounter.encounter_kind != &"boss" or encounter.boss_phases.size() < 2:
			continue
		found_multiphase = true
		var previous_threshold := 10001
		for phase: Resource in encounter.boss_phases:
			assert_lt(phase.hp_threshold_bps, previous_threshold)
			assert_ne(phase.source_spawn_key, "")
			assert_false(phase.effect_refs.is_empty())
			previous_threshold = phase.hp_threshold_bps
	assert_true(found_multiphase, "at least one boss must own multiple ordered phases")


func test_node_choice_commit_runtime_exists_as_named_api() -> void:
	for path: String in REQUIRED_RUNTIME_SCRIPTS:
		assert_true(FileAccess.file_exists(path), "missing node-choice runtime: %s" % path)


func _load_resources(path: String) -> Array[Resource]:
	var result: Array[Resource] = []
	var directory := DirAccess.open(path)
	if directory == null:
		fail_test("missing content directory: %s" % path)
		return result
	var file_names: Array[String] = []
	directory.list_dir_begin()
	var file_name := directory.get_next()
	while not file_name.is_empty():
		if not directory.current_is_dir() and file_name.ends_with(".tres"):
			file_names.append(file_name)
		file_name = directory.get_next()
	directory.list_dir_end()
	file_names.sort()
	for resource_name: String in file_names:
		var resource := load("%s/%s" % [path, resource_name]) as Resource
		assert_not_null(resource, "could not load %s/%s" % [path, resource_name])
		if resource != null:
			result.append(resource)
	return result


func _index_by_id(resources: Array[Resource]) -> Dictionary:
	var result: Dictionary = {}
	for resource: Resource in resources:
		assert_false(result.has(resource.id), "duplicate content id: %s" % resource.id)
		result[resource.id] = resource
	return result
