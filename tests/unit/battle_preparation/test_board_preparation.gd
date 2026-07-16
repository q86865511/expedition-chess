extends GutTest

func test_population_sources_are_sorted_and_added_without_abstract_cap() -> void:
	var sources: Array[PopulationSourceSnapshot] = [
		PopulationSourceSnapshot.new(
			PopulationSourceSnapshot.SourceKind.TRAIT, &"trait.capacity", "tier_2", 1
		),
		PopulationSourceSnapshot.new(
			PopulationSourceSnapshot.SourceKind.EVENT, &"event.capacity", "node_2", 1
		),
		PopulationSourceSnapshot.new(
			PopulationSourceSnapshot.SourceKind.RELIC, &"relic.capacity", "slot_0", 1
		),
	]
	var result := PopulationCalculator.new().calculate(9, sources)
	assert_true(result.ok)
	assert_eq(result.derived_capacity, 12)
	assert_eq(result.ordered_sources[0].source_kind, PopulationSourceSnapshot.SourceKind.EVENT)
	assert_eq(result.ordered_sources[1].source_kind, PopulationSourceSnapshot.SourceKind.RELIC)
	assert_eq(result.ordered_sources[2].source_kind, PopulationSourceSnapshot.SourceKind.TRAIT)

func test_population_duplicate_identity_is_rejected() -> void:
	var sources: Array[PopulationSourceSnapshot] = [
		PopulationSourceSnapshot.new(
			PopulationSourceSnapshot.SourceKind.EVENT, &"event.capacity", "node_2", 1
		),
		PopulationSourceSnapshot.new(
			PopulationSourceSnapshot.SourceKind.EVENT, &"event.capacity", "node_2", 2
		),
	]
	var result := PopulationCalculator.new().calculate(9, sources)
	assert_false(result.ok)
	assert_eq(result.error.code, PopulationCalculationError.DUPLICATE_SOURCE)

func test_population_sources_are_strictly_positive() -> void:
	for amount: int in [0, -1]:
		var sources: Array[PopulationSourceSnapshot] = [
			PopulationSourceSnapshot.new(
				PopulationSourceSnapshot.SourceKind.EVENT,
				&"event.capacity",
				"node_2",
				amount
			),
		]
		var result := PopulationCalculator.new().calculate(9, sources)
		assert_false(result.ok)
		assert_eq(result.error.code, PopulationCalculationError.INVALID_SOURCE)

func test_population_checked_addition_reaches_i32_max_without_abstract_cap() -> void:
	var sources: Array[PopulationSourceSnapshot] = [
		PopulationSourceSnapshot.new(
			PopulationSourceSnapshot.SourceKind.EVENT,
			&"event.capacity",
			"stress",
			7
		),
	]
	var maximum := PopulationCalculator.new().calculate(2147483640, sources)
	assert_true(maximum.ok)
	assert_eq(maximum.derived_capacity, 2147483647)
	sources[0].amount = 8
	var overflow := PopulationCalculator.new().calculate(2147483640, sources)
	assert_false(overflow.ok)
	assert_eq(overflow.error.code, PopulationCalculationError.OVERFLOW)

func test_twelve_deployed_units_fit_capacity_and_thirteen_do_not() -> void:
	var sources: Array[PopulationSourceSnapshot] = [
		PopulationSourceSnapshot.new(
			PopulationSourceSnapshot.SourceKind.EVENT, &"event.capacity_a", "node_a", 1
		),
		PopulationSourceSnapshot.new(
			PopulationSourceSnapshot.SourceKind.RELIC, &"relic.capacity_b", "slot_0", 1
		),
		PopulationSourceSnapshot.new(
			PopulationSourceSnapshot.SourceKind.TRAIT, &"trait.capacity_c", "tier_1", 1
		),
	]
	var twelve := BoardPreparationValidator.new().validate(
		_request_with_deployed_count(12, 9, sources)
	)
	assert_true(twelve.valid)
	assert_eq(twelve.derived_capacity, 12)
	var thirteen := BoardPreparationValidator.new().validate(
		_request_with_deployed_count(13, 9, sources)
	)
	assert_false(thirteen.valid)
	assert_eq(thirteen.derived_capacity, 12)
	var codes: Array[StringName] = []
	for issue: BoardValidationIssue in thirteen.issues:
		codes.append(issue.code)
	assert_has(codes, BoardValidationIssue.OVER_CAPACITY)

func test_all_thirty_two_player_half_cells_are_a_valid_physical_bound() -> void:
	var no_sources: Array[PopulationSourceSnapshot] = []
	var report := BoardPreparationValidator.new().validate(
		_request_with_deployed_count(32, 32, no_sources)
	)
	assert_true(report.valid)
	assert_eq(report.derived_capacity, 32)

func test_issue_order_compares_signed_coordinates_numerically() -> void:
	var placements: Array[BoardPlacementState] = [
		BoardPlacementState.new(10000, 0, "missing_d"),
		BoardPlacementState.new(-2, 0, "missing_b"),
		BoardPlacementState.new(9999, 0, "missing_c"),
		BoardPlacementState.new(-10, 0, "missing_a"),
	]
	var no_bench: Array[String] = []
	var no_units: Array[UnitInstance] = []
	var no_sources: Array[PopulationSourceSnapshot] = []
	var report := BoardPreparationValidator.new().validate(
		BoardPreparationRequest.new(
			BoardState.new(placements),
			no_bench,
			no_units,
			4,
			no_sources
		)
	)
	var out_of_bounds_y: Array[int] = []
	for issue: BoardValidationIssue in report.issues:
		if issue.code == BoardValidationIssue.OUT_OF_BOUNDS:
			out_of_bounds_y.append(issue.logical_y)
	assert_eq(out_of_bounds_y, [-10, -2, 9999, 10000])

func test_board_validator_collects_and_sorts_all_errors() -> void:
	var units: Array[UnitInstance] = []
	var placements: Array[BoardPlacementState] = []
	for index: int in range(33):
		var instance_id := "u_%016x" % (index + 1)
		units.append(_unit(instance_id, index))
		placements.append(BoardPlacementState.new(index >> 3, index % 8, instance_id))
	placements[1] = BoardPlacementState.new(0, 0, units[1].instance_id)
	placements[2] = BoardPlacementState.new(5, 2, units[2].instance_id)
	placements[3] = BoardPlacementState.new(0, 3, "u_ffffffffffffffff")
	var bench: Array[String] = []
	var sources: Array[PopulationSourceSnapshot] = [
		PopulationSourceSnapshot.new(
			PopulationSourceSnapshot.SourceKind.EVENT, &"event.capacity", "node_0", 3
		),
	]
	var report := BoardPreparationValidator.new().validate(
		BoardPreparationRequest.new(BoardState.new(placements), bench, units, 9, sources)
	)
	assert_false(report.valid)
	assert_eq(report.derived_capacity, 12)
	var codes: Array[StringName] = []
	var previous_issue: BoardValidationIssue = null
	for issue: BoardValidationIssue in report.issues:
		codes.append(issue.code)
		if previous_issue != null:
			assert_false(issue.precedes(previous_issue))
		previous_issue = issue
	assert_has(codes, BoardValidationIssue.CELL_OVERLAP)
	assert_has(codes, BoardValidationIssue.WRONG_HALF)
	assert_has(codes, BoardValidationIssue.UNIT_REFERENCE_MISSING)
	assert_has(codes, BoardValidationIssue.OVER_CAPACITY)
	assert_has(codes, BoardValidationIssue.PHYSICAL_LIMIT)

func test_bench_compaction_preserves_player_relative_order() -> void:
	var bench: Array[String] = ["u_3", "", "u_1", "missing", "u_2"]
	var valid: Array[String] = ["u_1", "u_2", "u_3"]
	var board: Array[String] = ["u_1"]
	assert_eq(
		BenchCompactor.new().compact(bench, valid, board),
		["u_3", "u_2"]
	)

func _unit(instance_id: String, serial: int) -> UnitInstance:
	var equipment: Array[String] = []
	var parsed := U64Bits.from_hex("%016x" % serial)
	return UnitInstance.new(instance_id, &"unit.fixture", 1, equipment, parsed.value)

func _request_with_deployed_count(
	count: int,
	base_level: int,
	sources: Array[PopulationSourceSnapshot]
) -> BoardPreparationRequest:
	var units: Array[UnitInstance] = []
	var placements: Array[BoardPlacementState] = []
	for index: int in range(count):
		var instance_id := "u_%016x" % (index + 1)
		units.append(_unit(instance_id, index + 1))
		placements.append(
			BoardPlacementState.new(index >> 3, index % 8, instance_id)
		)
	var no_bench: Array[String] = []
	return BoardPreparationRequest.new(
		BoardState.new(placements),
		no_bench,
		units,
		base_level,
		sources
	)
