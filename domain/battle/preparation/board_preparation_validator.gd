class_name BoardPreparationValidator
extends RefCounted

const BOARD_WIDTH: int = 8
const BOARD_HEIGHT: int = 8
const PLAYER_MAX_Y: int = 3
const PLAYER_HALF_CAPACITY: int = 32
const BENCH_CAPACITY: int = 9

var _population_calculator := PopulationCalculator.new()

func validate(request: BoardPreparationRequest) -> BoardValidationReport:
	var issues: Array[BoardValidationIssue] = []
	if request == null or request.board == null:
		issues.append(BoardValidationIssue.new(BoardValidationIssue.REQUEST_INVALID))
		return BoardValidationReport.new(-1, issues)
	var population := _population_calculator.calculate(
		request.base_level,
		request.population_sources
	)
	var derived_capacity := population.derived_capacity if population.ok else -1
	if not population.ok:
		issues.append(BoardValidationIssue.new(BoardValidationIssue.POPULATION_INVALID))

	var unit_ids: Array[String] = []
	for unit: UnitInstance in request.unit_instances:
		if unit == null or unit.instance_id.is_empty() or unit_ids.has(unit.instance_id):
			issues.append(BoardValidationIssue.new(
				BoardValidationIssue.UNIT_DUPLICATE,
				-1,
				-1,
				unit.instance_id if unit != null else ""
			))
			continue
		unit_ids.append(unit.instance_id)

	var board_ids: Array[String] = []
	var occupied_cells: Array[String] = []
	for placement: BoardPlacementState in request.board.placements:
		if placement == null:
			issues.append(BoardValidationIssue.new(BoardValidationIssue.REQUEST_INVALID))
			continue
		var inside_board := placement.logical_x >= 0 and placement.logical_x < BOARD_WIDTH \
			and placement.logical_y >= 0 and placement.logical_y < BOARD_HEIGHT
		if not inside_board:
			issues.append(_placement_issue(BoardValidationIssue.OUT_OF_BOUNDS, placement))
		elif placement.logical_y > PLAYER_MAX_Y:
			issues.append(_placement_issue(BoardValidationIssue.WRONG_HALF, placement))
		var cell := "%d,%d" % [placement.logical_y, placement.logical_x]
		if occupied_cells.has(cell):
			issues.append(_placement_issue(BoardValidationIssue.CELL_OVERLAP, placement))
		else:
			occupied_cells.append(cell)
		if board_ids.has(placement.unit_instance_id):
			issues.append(_placement_issue(BoardValidationIssue.UNIT_DUPLICATE, placement))
		else:
			board_ids.append(placement.unit_instance_id)
		if not unit_ids.has(placement.unit_instance_id):
			issues.append(_placement_issue(BoardValidationIssue.UNIT_REFERENCE_MISSING, placement))

	if request.board.placements.size() > PLAYER_HALF_CAPACITY:
		issues.append(BoardValidationIssue.new(BoardValidationIssue.PHYSICAL_LIMIT))
	if population.ok and request.board.placements.size() > derived_capacity:
		issues.append(BoardValidationIssue.new(BoardValidationIssue.OVER_CAPACITY))

	if request.bench_unit_instance_ids.size() > BENCH_CAPACITY:
		issues.append(BoardValidationIssue.new(BoardValidationIssue.BENCH_TOO_LARGE))
	var bench_seen: Array[String] = []
	for instance_id: String in request.bench_unit_instance_ids:
		if instance_id.is_empty():
			issues.append(BoardValidationIssue.new(BoardValidationIssue.BENCH_EMPTY_SLOT))
			continue
		if bench_seen.has(instance_id) or board_ids.has(instance_id):
			issues.append(BoardValidationIssue.new(
				BoardValidationIssue.UNIT_DUPLICATE, -1, -1, instance_id
			))
		else:
			bench_seen.append(instance_id)
		if not unit_ids.has(instance_id):
			issues.append(BoardValidationIssue.new(
				BoardValidationIssue.UNIT_REFERENCE_MISSING, -1, -1, instance_id
			))

	for instance_id: String in unit_ids:
		if not board_ids.has(instance_id) and not bench_seen.has(instance_id):
			issues.append(BoardValidationIssue.new(
				BoardValidationIssue.UNIT_UNASSIGNED, -1, -1, instance_id
			))
	issues.sort_custom(_issue_precedes)
	return BoardValidationReport.new(derived_capacity, issues)

func _placement_issue(code: StringName, placement: BoardPlacementState) -> BoardValidationIssue:
	return BoardValidationIssue.new(
		code,
		placement.logical_y,
		placement.logical_x,
		placement.unit_instance_id
	)

func _issue_precedes(left: BoardValidationIssue, right: BoardValidationIssue) -> bool:
	return left.precedes(right)
