class_name SummonFailureEventPayload
extends BattleEventPayload

var unit_id: StringName = &""
var request_ordinal: int = 0
var reason: StringName = &""

func deep_clone() -> BattleEventPayload:
	var copied := SummonFailureEventPayload.new()
	copied.unit_id = unit_id
	copied.request_ordinal = request_ordinal
	copied.reason = reason
	return copied
