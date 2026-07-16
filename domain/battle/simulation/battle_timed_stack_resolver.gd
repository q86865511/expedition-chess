class_name BattleTimedStackResolver
extends RefCounted

static func apply(
	values: Array[BattleTimedState],
	candidate: BattleTimedState,
	max_stacks: int
) -> StringName:
	var matching: Array[BattleTimedState] = []
	for value: BattleTimedState in values:
		if _same_identity(value, candidate):
			matching.append(value)
	if candidate.stacking == &"independent":
		candidate.stacks = mini(max_stacks, maxi(1, candidate.stacks))
		values.append(candidate)
		return &"apply"
	if matching.is_empty():
		candidate.stacks = mini(max_stacks, maxi(1, candidate.stacks))
		values.append(candidate)
		return &"apply"
	var current := matching[0]
	if candidate.stacking == &"replace":
		if candidate.amount < current.amount \
			or (candidate.amount == current.amount \
				and candidate.expires_tick <= current.expires_tick):
			return &"none"
		for index: int in range(values.size() - 1, -1, -1):
			if _same_identity(values[index], candidate):
				values.remove_at(index)
		values.append(candidate)
		return &"replace"
	if candidate.stacking == &"refresh_duration":
		if candidate.expires_tick <= current.expires_tick:
			return &"none"
		current.expires_tick = candidate.expires_tick
		return &"refresh"
	var before_stacks := maxi(1, current.stacks)
	var added_stacks := mini(
		maxi(1, candidate.stacks), maxi(0, max_stacks - before_stacks)
	)
	if added_stacks <= 0 and candidate.expires_tick <= current.expires_tick:
		return &"none"
	current.stacks = before_stacks + added_stacks
	if candidate.stacks > 0:
		current.amount += candidate.amount * added_stacks / candidate.stacks
	current.expires_tick = maxi(current.expires_tick, candidate.expires_tick)
	return &"stack"

static func _same_identity(
	left: BattleTimedState,
	right: BattleTimedState
) -> bool:
	var left_source := &"" if left.source_instance_id == null \
		else left.source_instance_id.value
	var right_source := &"" if right.source_instance_id == null \
		else right.source_instance_id.value
	return left.kind == right.kind and left.state_id == right.state_id \
		and left_source == right_source \
		and left.operation_index == right.operation_index
