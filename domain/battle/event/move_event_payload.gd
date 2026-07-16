class_name MoveEventPayload
extends BattleEventPayload

var from_y: int = 0
var from_x: int = 0
var to_y: int = 0
var to_x: int = 0

func deep_clone() -> BattleEventPayload:
	var copied := MoveEventPayload.new()
	copied.from_y = from_y
	copied.from_x = from_x
	copied.to_y = to_y
	copied.to_x = to_x
	return copied
