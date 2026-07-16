class_name BattlePathfinder
extends RefCounted

const DIRECTIONS: Array[Vector2i] = [
	Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 0), Vector2i(1, 1),
	Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(-1, -1),
]

func path_cost_to_attack_position(
	mover: BattleEntityState,
	target: BattleEntityState,
	entities: Array[BattleEntityState],
	width: int,
	height: int,
	attack_range: int
) -> int:
	return _search(mover, target, entities, width, height, attack_range, false).y

func next_step_toward_attack_position(
	mover: BattleEntityState,
	target: BattleEntityState,
	entities: Array[BattleEntityState],
	width: int,
	height: int,
	attack_range: int
) -> Vector2i:
	var result := _search(mover, target, entities, width, height, attack_range, true)
	return Vector2i(result.x, result.z)

func forward_step(
	mover: BattleEntityState,
	entities: Array[BattleEntityState],
	width: int,
	height: int
) -> Vector2i:
	var delta := Vector2i(0, 1 if mover.side == &"player" else -1)
	var start := Vector2i(mover.logical_x, mover.logical_y)
	var candidate := start + delta
	return candidate if _can_step(start, candidate, mover.instance_id, entities, width, height) else Vector2i(-1, -1)

func away_step(
	mover: BattleEntityState,
	target: BattleEntityState,
	entities: Array[BattleEntityState],
	width: int,
	height: int
) -> Vector2i:
	var start := Vector2i(mover.logical_x, mover.logical_y)
	var best := Vector2i(-1, -1)
	var best_distance := -1
	for delta: Vector2i in DIRECTIONS:
		var candidate := start + delta
		if not _can_step(start, candidate, mover.instance_id, entities, width, height):
			continue
		var distance := maxi(
			absi(candidate.y - target.logical_y),
			absi(candidate.x - target.logical_x)
		)
		if distance > best_distance:
			best_distance = distance
			best = candidate
	return best

func can_step(
	from_cell: Vector2i,
	to_cell: Vector2i,
	mover_id: StringName,
	entities: Array[BattleEntityState],
	width: int,
	height: int
) -> bool:
	return _can_step(from_cell, to_cell, mover_id, entities, width, height)

func _search(
	mover: BattleEntityState,
	target: BattleEntityState,
	entities: Array[BattleEntityState],
	width: int,
	height: int,
	attack_range: int,
	_need_step: bool
) -> Vector3i:
	var start := Vector2i(mover.logical_x, mover.logical_y)
	if _in_attack_range(start, target, attack_range):
		return Vector3i(start.x, 0, start.y)
	var queue: Array[Vector2i] = [start]
	var costs: Array[int] = [0]
	var first_steps: Array[Vector2i] = [start]
	var visited: Dictionary = {_key(start): true}
	var cursor := 0
	while cursor < queue.size():
		var current := queue[cursor]
		var cost := costs[cursor]
		var first_step := first_steps[cursor]
		cursor += 1
		for delta: Vector2i in DIRECTIONS:
			var candidate := current + delta
			var key := _key(candidate)
			if visited.has(key) or not _can_step(
				current, candidate, mover.instance_id, entities, width, height
			):
				continue
			visited[key] = true
			var next_first := candidate if cost == 0 else first_step
			if _in_attack_range(candidate, target, attack_range):
				return Vector3i(next_first.x, cost + 1, next_first.y)
			queue.append(candidate)
			costs.append(cost + 1)
			first_steps.append(next_first)
	return Vector3i(-1, -1, -1)

func _can_step(
	from_cell: Vector2i,
	to_cell: Vector2i,
	mover_id: StringName,
	entities: Array[BattleEntityState],
	width: int,
	height: int
) -> bool:
	if not _inside(to_cell, width, height) \
		or _occupied(to_cell, mover_id, entities):
		return false
	var dx := to_cell.x - from_cell.x
	var dy := to_cell.y - from_cell.y
	if absi(dx) == 1 and absi(dy) == 1:
		var side_a := Vector2i(from_cell.x + dx, from_cell.y)
		var side_b := Vector2i(from_cell.x, from_cell.y + dy)
		if not _inside(side_a, width, height) or not _inside(side_b, width, height) \
			or _occupied(side_a, mover_id, entities) or _occupied(side_b, mover_id, entities):
			return false
	return true

func _occupied(
	cell: Vector2i,
	ignored_id: StringName,
	entities: Array[BattleEntityState]
) -> bool:
	for entity: BattleEntityState in entities:
		if entity == null or not entity.alive or entity.instance_id == ignored_id:
			continue
		if entity.logical_x == cell.x and entity.logical_y == cell.y:
			return true
	return false

func _in_attack_range(cell: Vector2i, target: BattleEntityState, attack_range: int) -> bool:
	return maxi(absi(cell.y - target.logical_y), absi(cell.x - target.logical_x)) <= attack_range

func _inside(cell: Vector2i, width: int, height: int) -> bool:
	return cell.x >= 0 and cell.x < width and cell.y >= 0 and cell.y < height

func _key(cell: Vector2i) -> String:
	return "%d:%d" % [cell.y, cell.x]
