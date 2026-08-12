extends GutTest


func test_board_swap_and_bench_to_board_share_one_clone_only_adapter() -> void:
	var adapter := BoardDraftMoveAdapter.new()
	var bench: Array[String] = ["bench_a"]
	adapter.reset(_board([
		_placement("board_a", Vector2i(0, 0)),
		_placement("board_b", Vector2i(1, 0)),
	]), bench)
	assert_eq(adapter.move_to_board("board_a", Vector2i(1, 0)), &"")
	assert_eq(_cell_for(adapter.board_clone(), "board_a"), Vector2i(1, 0))
	assert_eq(_cell_for(adapter.board_clone(), "board_b"), Vector2i(0, 0))

	assert_eq(adapter.move_to_board("bench_a", Vector2i(0, 0)), &"")
	assert_eq(_cell_for(adapter.board_clone(), "bench_a"), Vector2i(0, 0))
	assert_eq(adapter.bench_clone(), ["board_b"])


func test_board_to_occupied_bench_swaps_without_losing_identity() -> void:
	var adapter := BoardDraftMoveAdapter.new()
	var bench: Array[String] = ["bench_a", "bench_b"]
	adapter.reset(_board([
		_placement("board_a", Vector2i(3, 2)),
	]), bench)
	assert_eq(adapter.move_to_bench("board_a", 1), &"")
	assert_eq(adapter.bench_clone(), ["bench_a", "board_a"])
	assert_eq(_cell_for(adapter.board_clone(), "bench_b"), Vector2i(3, 2))


func test_bench_to_occupied_bench_swaps_without_losing_identity() -> void:
	var adapter := BoardDraftMoveAdapter.new()
	var bench: Array[String] = ["bench_a", "bench_b", "bench_c"]
	adapter.reset(_board([]), bench)
	assert_eq(adapter.move_to_bench("bench_a", 2), &"")
	assert_eq(adapter.bench_clone(), ["bench_c", "bench_b", "bench_a"])


func test_adapter_never_retains_callers_mutable_board_or_bench() -> void:
	var source := _board([_placement("unit_a", Vector2i(0, 0))])
	var bench: Array[String] = ["unit_b"]
	var adapter := BoardDraftMoveAdapter.new()
	adapter.reset(source, bench)
	source.placements.clear()
	bench.clear()
	assert_eq(_cell_for(adapter.board_clone(), "unit_a"), Vector2i(0, 0))
	assert_eq(adapter.bench_clone(), ["unit_b"])
	var returned := adapter.board_clone()
	returned.placements.clear()
	assert_eq(_cell_for(adapter.board_clone(), "unit_a"), Vector2i(0, 0))


func test_player_half_and_capacity_rejections_fail_closed() -> void:
	var adapter := BoardDraftMoveAdapter.new()
	var bench: Array[String] = ["u0", "u1", "u2", "u3", "u4", "u5", "u6", "u7", "u8"]
	adapter.reset(_board([_placement("board_a", Vector2i(0, 0))]), bench)
	assert_eq(
		adapter.move_to_board("board_a", Vector2i(0, 4)),
		BoardDraftMoveAdapter.TARGET_INVALID
	)
	assert_eq(
		adapter.move_to_first_open_bench("board_a"),
		BoardDraftMoveAdapter.BENCH_FULL
	)
	assert_eq(_cell_for(adapter.board_clone(), "board_a"), Vector2i(0, 0))


func _board(values: Array[BoardPlacementState]) -> BoardState:
	return BoardState.new(values)


func _placement(unit_id: String, cell: Vector2i) -> BoardPlacementState:
	return BoardPlacementState.new(cell.y, cell.x, unit_id)


func _cell_for(board: BoardState, unit_id: String) -> Vector2i:
	for placement: BoardPlacementState in board.placements:
		if placement.unit_instance_id == unit_id:
			return Vector2i(placement.logical_x, placement.logical_y)
	return Vector2i(-1, -1)
