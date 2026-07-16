class_name DeathEventPayload
extends BattleEventPayload

var origin: StringName = &""
var logical_y: int = 0
var logical_x: int = 0

func deep_clone() -> BattleEventPayload:
	var copied := DeathEventPayload.new()
	copied.origin = origin
	copied.logical_y = logical_y
	copied.logical_x = logical_x
	return copied
