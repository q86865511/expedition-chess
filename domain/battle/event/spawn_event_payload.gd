class_name SpawnEventPayload
extends BattleEventPayload

var unit_id: StringName = &""
var side: StringName = &""
var origin: StringName = &""
var logical_y: int = 0
var logical_x: int = 0

func deep_clone() -> BattleEventPayload:
	var copied := SpawnEventPayload.new()
	copied.unit_id = unit_id
	copied.side = side
	copied.origin = origin
	copied.logical_y = logical_y
	copied.logical_x = logical_x
	return copied
