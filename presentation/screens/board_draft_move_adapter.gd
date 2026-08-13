class_name BoardDraftMoveAdapter
extends RefCounted

const UNIT_INVALID: StringName = &"PREPARE_DRAFT_UNIT_INVALID"
const TARGET_INVALID: StringName = &"PREPARE_DRAFT_TARGET_INVALID"
const BOARD_FULL: StringName = &"PREPARE_BOARD_FULL"
const BENCH_FULL: StringName = &"PREPARE_BENCH_FULL"
const BOARD_WIDTH: int = BoardPreparationValidator.BOARD_WIDTH
const PLAYER_BOARD_HEIGHT: int = BoardPreparationValidator.PLAYER_MAX_Y + 1
const BENCH_SIZE: int = BoardPreparationValidator.BENCH_CAPACITY

var _board: BoardState
var _bench: Array[String] = []


func reset(board: BoardState, bench: Array[String]) -> void:
	if board != null:
		_board = board.deep_clone()
	else:
		var empty_placements: Array[BoardPlacementState] = []
		_board = BoardState.new(empty_placements)
	_bench.assign(bench)


func board_clone() -> BoardState:
	return _board.deep_clone() if _board != null else null


func bench_clone() -> Array[String]:
	return _bench.duplicate()


func move_to_first_open_board(unit_id: String) -> StringName:
	for logical_y: int in range(PLAYER_BOARD_HEIGHT):
		for logical_x: int in range(BOARD_WIDTH):
			if _unit_at(Vector2i(logical_x, logical_y)).is_empty():
				return move_to_board(unit_id, Vector2i(logical_x, logical_y))
	return BOARD_FULL


func move_to_board(unit_id: String, target: Vector2i) -> StringName:
	if unit_id.is_empty():
		return UNIT_INVALID
	if (
		target.x < 0
		or target.x >= BOARD_WIDTH
		or target.y < 0
		or target.y >= PLAYER_BOARD_HEIGHT
	):
		return TARGET_INVALID
	var source_cell := _cell_for(unit_id)
	var source_bench_index := _bench.find(unit_id)
	if source_cell.x < 0 and source_bench_index < 0:
		return UNIT_INVALID
	var occupant := _unit_at(target)
	_remove_from_board(unit_id)
	if not occupant.is_empty() and occupant != unit_id:
		_remove_from_board(occupant)
		if source_cell.x >= 0:
			_append_placement(occupant, source_cell)
		elif source_bench_index >= 0:
			_bench[source_bench_index] = occupant
	_bench.erase(unit_id)
	_append_placement(unit_id, target)
	return &""


func move_to_first_open_bench(unit_id: String) -> StringName:
	if _bench.has(unit_id):
		return &""
	if _bench.size() >= BENCH_SIZE:
		return BENCH_FULL
	return move_to_bench(unit_id, _bench.size())


func move_to_bench(unit_id: String, target_slot: int) -> StringName:
	if unit_id.is_empty() or target_slot < 0 or target_slot >= BENCH_SIZE:
		return TARGET_INVALID
	var source_cell := _cell_for(unit_id)
	var source_bench_index := _bench.find(unit_id)
	if source_cell.x < 0 and source_bench_index < 0:
		return UNIT_INVALID
	# A bench-to-bench drop onto an occupied slot is a swap, not an insert.
	# Keeping this branch before either removal makes both identities stable.
	if source_bench_index >= 0 and target_slot < _bench.size():
		if source_bench_index == target_slot:
			return &""
		var source_occupant := _bench[target_slot]
		_bench[target_slot] = unit_id
		_bench[source_bench_index] = source_occupant
		return &""
	var occupant := _bench[target_slot] if target_slot < _bench.size() else ""
	if source_bench_index >= 0:
		_bench.remove_at(source_bench_index)
		if source_bench_index < target_slot:
			target_slot -= 1
	_remove_from_board(unit_id)
	if not occupant.is_empty() and occupant != unit_id:
		_bench.erase(occupant)
		if source_cell.x >= 0:
			_append_placement(occupant, source_cell)
	var insert_at := mini(target_slot, _bench.size())
	_bench.insert(insert_at, unit_id)
	return &""


func _cell_for(unit_id: String) -> Vector2i:
	if _board != null:
		for placement: BoardPlacementState in _board.placements:
			if placement != null and placement.unit_instance_id == unit_id:
				return Vector2i(placement.logical_x, placement.logical_y)
	return Vector2i(-1, -1)


func _unit_at(cell: Vector2i) -> String:
	if _board != null:
		for placement: BoardPlacementState in _board.placements:
			if (
				placement != null
				and placement.logical_x == cell.x
				and placement.logical_y == cell.y
			):
				return placement.unit_instance_id
	return ""


func _remove_from_board(unit_id: String) -> void:
	if _board == null:
		return
	for index: int in range(_board.placements.size() - 1, -1, -1):
		if _board.placements[index].unit_instance_id == unit_id:
			_board.placements.remove_at(index)


func _append_placement(unit_id: String, cell: Vector2i) -> void:
	_board.placements.append(BoardPlacementState.new(cell.y, cell.x, unit_id))
