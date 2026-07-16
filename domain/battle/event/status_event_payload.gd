class_name StatusEventPayload
extends BattleEventPayload

var status_id: StringName = &""
var action: StringName = &""
var stacks: int = 0
var remaining_ticks: int = 0

func deep_clone() -> BattleEventPayload:
	var copied := StatusEventPayload.new()
	copied.status_id = status_id
	copied.action = action
	copied.stacks = stacks
	copied.remaining_ticks = remaining_ticks
	return copied
