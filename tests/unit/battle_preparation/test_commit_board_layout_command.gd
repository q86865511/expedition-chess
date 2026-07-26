extends GutTest

func test_command_compacts_validates_and_returns_complete_draft() -> void:
	var draft := SaveRootFixture.create_valid_root().run
	draft.run_phase = RunState.RunPhase.PREPARE
	draft.economy_state.level = 2
	var empty_equipment: Array[String] = []
	var units: Array[UnitInstance] = [
		_unit("u_0000000000000001", 1, 1, empty_equipment),
		_unit("u_0000000000000002", 1, 2, empty_equipment),
	]
	draft.roster_state.unit_instances = units
	var pool_entries: Array[UnitPoolEntryState] = [
		UnitPoolEntryState.new(&"unit.fixture", 10, 8, 0, 2),
	]
	draft.unit_pool_state = UnitPoolState.new(pool_entries)
	var placements: Array[BoardPlacementState] = [
		BoardPlacementState.new(0, 0, units[0].instance_id),
	]
	var bench: Array[String] = ["", units[1].instance_id]
	var result := CommitBoardLayoutCommand.new(
		BoardState.new(placements), bench, _empty_catalog()
	).apply_to(draft)
	assert_true(result.ok)
	assert_eq(result.draft.roster_state.board.placements.size(), 1)
	assert_eq(result.draft.roster_state.bench_unit_instance_ids, [units[1].instance_id])
	assert_true(RunStateValidator.new().validate_run(result.draft).ok)

func test_command_rejects_wrong_half_without_success_draft() -> void:
	var draft := SaveRootFixture.create_valid_root().run
	draft.run_phase = RunState.RunPhase.PREPARE
	draft.economy_state.level = 1
	var empty_equipment: Array[String] = []
	var unit := _unit("u_0000000000000001", 1, 1, empty_equipment)
	var units: Array[UnitInstance] = [unit]
	draft.roster_state.unit_instances = units
	var pool_entries: Array[UnitPoolEntryState] = [
		UnitPoolEntryState.new(&"unit.fixture", 10, 9, 0, 1),
	]
	draft.unit_pool_state = UnitPoolState.new(pool_entries)
	var placements: Array[BoardPlacementState] = [
		BoardPlacementState.new(5, 0, unit.instance_id),
	]
	var bench: Array[String] = []
	var result := CommitBoardLayoutCommand.new(
		BoardState.new(placements), bench, _empty_catalog()
	).apply_to(draft)
	assert_false(result.ok)
	assert_null(result.draft)
	assert_eq(result.error.code, CommandApplyError.APPLY_REJECTED)
	assert_eq(result.error.diagnostic_values[0].string_value.value, String(BoardValidationIssue.WRONG_HALF))

func test_command_rejects_pool_held_copy_mismatch() -> void:
	var draft := SaveRootFixture.create_valid_root().run
	draft.run_phase = RunState.RunPhase.PREPARE
	draft.economy_state.level = 1
	var empty_equipment: Array[String] = []
	var unit := _unit("u_0000000000000001", 1, 1, empty_equipment)
	var units: Array[UnitInstance] = [unit]
	draft.roster_state.unit_instances = units
	var pool_entries: Array[UnitPoolEntryState] = [
		UnitPoolEntryState.new(&"unit.fixture", 10, 10, 0, 0),
	]
	draft.unit_pool_state = UnitPoolState.new(pool_entries)
	var placements: Array[BoardPlacementState] = [
		BoardPlacementState.new(0, 0, unit.instance_id),
	]
	var bench: Array[String] = []
	var result := CommitBoardLayoutCommand.new(
		BoardState.new(placements), bench, _empty_catalog()
	).apply_to(draft)
	assert_false(result.ok)
	assert_eq(
		result.error.diagnostic_values[0].string_value.value,
		"UNIT_POOL_HELD_COPY_MISMATCH"
	)

func test_command_rejects_catalog_from_a_different_pinned_generation() -> void:
	var draft := SaveRootFixture.create_valid_root().run
	draft.run_phase = RunState.RunPhase.PREPARE
	var no_placements: Array[BoardPlacementState] = []
	var no_bench: Array[String] = []
	var result := CommitBoardLayoutCommand.new(
		BoardState.new(no_placements),
		no_bench,
		_catalog_with_digest(
			"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
		)
	).apply_to(draft)
	assert_false(result.ok)
	assert_eq(result.error.field_path, &"run.content_snapshot.manifest_digest")
	assert_eq(
		result.error.diagnostic_values[0].string_value.value,
		"BOARD_LAYOUT_CATALOG_GENERATION_MISMATCH"
	)

func test_command_uses_level_only_until_authoritative_population_builder_exists() -> void:
	var draft := SaveRootFixture.create_valid_root().run
	draft.run_phase = RunState.RunPhase.PREPARE
	draft.economy_state.level = 1
	var no_equipment: Array[String] = []
	var units: Array[UnitInstance] = [
		_unit("u_0000000000000001", 1, 1, no_equipment),
		_unit("u_0000000000000002", 1, 2, no_equipment),
	]
	draft.roster_state.unit_instances = units
	var pool_entries: Array[UnitPoolEntryState] = [
		UnitPoolEntryState.new(&"unit.fixture", 2, 0, 0, 2),
	]
	draft.unit_pool_state = UnitPoolState.new(pool_entries)
	var placements: Array[BoardPlacementState] = [
		BoardPlacementState.new(0, 0, units[0].instance_id),
		BoardPlacementState.new(0, 1, units[1].instance_id),
	]
	var no_bench: Array[String] = []
	var result := CommitBoardLayoutCommand.new(
		BoardState.new(placements), no_bench, _empty_catalog()
	).apply_to(draft)
	assert_false(result.ok)
	assert_eq(
		result.error.diagnostic_values[0].string_value.value,
		String(BoardValidationIssue.OVER_CAPACITY)
	)

func test_command_applies_an_injected_try_commander_population_source() -> void:
	# S5 / design.md SS4.2 (W3-F3): the commander's population_bonus raises capacity
	# as an EXTRA population source on top of economy_state.level -- it must never be
	# folded into the level itself, which is also the shop tier-odds key and the XP
	# ladder. Same layout as the test above, which is OVER_CAPACITY without a source.
	var draft := SaveRootFixture.create_valid_root().run
	draft.run_phase = RunState.RunPhase.PREPARE
	draft.economy_state.level = 1
	var no_equipment: Array[String] = []
	var units: Array[UnitInstance] = [
		_unit("u_0000000000000001", 1, 1, no_equipment),
		_unit("u_0000000000000002", 1, 2, no_equipment),
	]
	draft.roster_state.unit_instances = units
	var pool_entries: Array[UnitPoolEntryState] = [
		UnitPoolEntryState.new(&"unit.fixture", 2, 0, 0, 2),
	]
	draft.unit_pool_state = UnitPoolState.new(pool_entries)
	var placements: Array[BoardPlacementState] = [
		BoardPlacementState.new(0, 0, units[0].instance_id),
		BoardPlacementState.new(0, 1, units[1].instance_id),
	]
	var no_bench: Array[String] = []
	var sources: Array[PopulationSourceSnapshot] = [
		RunBootstrapService.try_commander_population_source(draft.commander_id, 1),
	]

	var result := CommitBoardLayoutCommand.new(
		BoardState.new(placements), no_bench, _empty_catalog(), sources
	).apply_to(draft)

	assert_true(result.ok, "level 1 + a commander bonus of 1 must seat two units")
	if not result.ok:
		return
	assert_eq(result.draft.roster_state.board.placements.size(), 2)


func _unit(
	instance_id: String,
	star: int,
	serial: int,
	equipment: Array[String]
) -> UnitInstance:
	return UnitInstance.new(
		instance_id,
		&"unit.fixture",
		star,
		equipment,
		U64Bits.from_hex("%016x" % serial).value
	)

func _empty_catalog() -> BattleRuleCatalog:
	return _catalog_with_digest(SaveRootFixture.MANIFEST_DIGEST)

func _catalog_with_digest(digest: String) -> BattleRuleCatalog:
	var units: Array[BattleUnitRule] = []
	var traits: Array[BattleTraitRule] = []
	var abilities: Array[BattleAbilityRule] = []
	var effects: Array[BattleEffectRule] = []
	var encounters: Array[BattleEncounterRule] = []
	var equipment: Array[BattleEquipmentRule] = []
	var configs: Array[BattleCombatConfigRule] = []
	return BattleRuleCatalog.new(
		digest,
		units, traits, abilities, effects, encounters, equipment, configs
	)
