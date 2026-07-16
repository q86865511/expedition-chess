extends GutTest

func test_replace_uses_larger_amount_then_duration_canonical_tuple() -> void:
	var values: Array[BattleTimedState] = [_timed(&"replace", 10, 20, 1)]
	assert_eq(
		BattleTimedStackResolver.apply(values, _timed(&"replace", 9, 30, 1), 3),
		&"none"
	)
	assert_eq(values[0].amount, 10)
	assert_eq(
		BattleTimedStackResolver.apply(values, _timed(&"replace", 10, 30, 1), 3),
		&"replace"
	)
	assert_eq(values[0].expires_tick, 30)

func test_refresh_keeps_amount_and_only_extends_duration() -> void:
	var values: Array[BattleTimedState] = [_timed(&"refresh_duration", 10, 20, 1)]
	assert_eq(
		BattleTimedStackResolver.apply(
			values, _timed(&"refresh_duration", 99, 15, 1), 3
		),
		&"none"
	)
	assert_eq(values[0].amount, 10)
	assert_eq(
		BattleTimedStackResolver.apply(
			values, _timed(&"refresh_duration", 99, 30, 1), 3
		),
		&"refresh"
	)
	assert_eq(values[0].amount, 10)
	assert_eq(values[0].expires_tick, 30)

func test_add_stacks_clamps_count_amount_and_takes_longer_duration() -> void:
	var values: Array[BattleTimedState] = [_timed(&"add_stacks", 10, 20, 1)]
	assert_eq(
		BattleTimedStackResolver.apply(values, _timed(&"add_stacks", 20, 30, 2), 2),
		&"stack"
	)
	assert_eq(values[0].stacks, 2)
	assert_eq(values[0].amount, 20)
	assert_eq(values[0].expires_tick, 30)
	assert_eq(
		BattleTimedStackResolver.apply(values, _timed(&"add_stacks", 50, 25, 1), 2),
		&"none"
	)

func test_independent_preserves_separate_application_sequences() -> void:
	var values: Array[BattleTimedState] = []
	var first := _timed(&"independent", 10, 20, 1)
	first.applied_sequence = 1
	var second := _timed(&"independent", 10, 20, 1)
	second.applied_sequence = 2
	assert_eq(BattleTimedStackResolver.apply(values, first, 1), &"apply")
	assert_eq(BattleTimedStackResolver.apply(values, second, 1), &"apply")
	assert_eq(values.size(), 2)
	assert_eq(values[0].applied_sequence, 1)
	assert_eq(values[1].applied_sequence, 2)

func _timed(
	stacking: StringName,
	amount: int,
	expires_tick: int,
	stacks: int
) -> BattleTimedState:
	var value := BattleTimedState.new()
	value.kind = &"status"
	value.state_id = &"effect.stack_test"
	value.source_instance_id = OptionalStringNameValue.of(&"u_0000000000000001")
	value.operation_index = 0
	value.amount = amount
	value.expires_tick = expires_tick
	value.stacks = stacks
	value.stacking = stacking
	return value
