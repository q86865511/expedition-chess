extends GutTest

func test_bench_is_ordered_player_data_but_need_not_be_sorted_by_instance_id() -> void:
	var run := _run_with_units(2)
	run.roster_state.board = BoardState.new(_no_placements())
	run.roster_state.bench_unit_instance_ids = [
		"u_0000000000000002",
		"u_0000000000000001",
	]
	assert_true(RunStateValidator.new().validate_run(run).ok)

func test_pool_held_copies_must_equal_weighted_roster_copies() -> void:
	var run := _run_with_units(1)
	run.unit_pool_state.entries[0].held_copies = 0
	run.unit_pool_state.entries[0].remaining_copies = 1
	var result := RunStateValidator.new().validate_run(run)
	assert_false(result.ok)
	assert_eq(result.error.field_path, &"run.unit_pool_state.entries.held_copies")

func test_bound_item_must_be_listed_on_exactly_its_owner_unit() -> void:
	var run := _run_with_units(1)
	var item := ItemInstanceState.new(
		"it_0000000000000001",
		&"equipment.fixture",
		OptionalStringValue.new("u_0000000000000001"),
		U64Bits.one()
	)
	run.roster_state.item_instances = [item]
	var result := RunStateValidator.new().validate_run(run)
	assert_false(result.ok)
	assert_eq(
		result.error.field_path,
		&"run.roster_state.item_instances.bound_unit_instance_id"
	)

func test_unbound_item_must_be_in_inventory_or_overflow_exactly_once() -> void:
	var run := _run_with_units(1)
	var item := ItemInstanceState.new(
		"it_0000000000000001",
		&"equipment.fixture",
		null,
		U64Bits.one()
	)
	run.roster_state.item_instances = [item]
	var missing := RunStateValidator.new().validate_run(run)
	assert_false(missing.ok)
	assert_eq(missing.error.field_path, &"run.roster_state.item_instances.location")
	run.roster_state.inventory_item_instance_ids = [item.instance_id]
	run.roster_state.pending_item_overflow = [item.instance_id]
	var duplicated := RunStateValidator.new().validate_run(run)
	assert_false(duplicated.ok)
	assert_eq(duplicated.error.field_path, &"run.roster_state.inventory")

func test_every_roster_unit_must_have_one_board_or_bench_location() -> void:
	var run := _run_with_units(1)
	run.roster_state.board = BoardState.new(_no_placements())
	var no_bench: Array[String] = []
	run.roster_state.bench_unit_instance_ids = no_bench
	var result := RunStateValidator.new().validate_run(run)
	assert_false(result.ok)
	assert_eq(result.error.field_path, &"run.roster_state.unit_instances.location")

func _run_with_units(count: int) -> RunState:
	var run := SaveRootFixture.create_valid_root().run
	var units: Array[UnitInstance] = []
	var placements: Array[BoardPlacementState] = []
	var no_equipment: Array[String] = []
	for index: int in range(count):
		var instance_id := "u_%016x" % (index + 1)
		units.append(
			UnitInstance.new(
				instance_id,
				&"unit.fixture",
				1,
				no_equipment,
				U64Bits.from_hex("%016x" % (index + 1)).value
			)
		)
		placements.append(BoardPlacementState.new(0, index, instance_id))
	run.roster_state.unit_instances = units
	run.roster_state.board = BoardState.new(placements)
	var no_bench: Array[String] = []
	run.roster_state.bench_unit_instance_ids = no_bench
	var entries: Array[UnitPoolEntryState] = [
		UnitPoolEntryState.new(&"unit.fixture", count, 0, 0, count),
	]
	run.unit_pool_state = UnitPoolState.new(entries)
	return run

func _no_placements() -> Array[BoardPlacementState]:
	var placements: Array[BoardPlacementState] = []
	return placements
