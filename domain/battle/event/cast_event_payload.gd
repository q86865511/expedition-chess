class_name CastEventPayload
extends BattleEventPayload

var ability_id: StringName = &""
var action: StringName = &""
var fizzle_reason: StringName = &"none"
var resolve_tick: int = 0

func deep_clone() -> BattleEventPayload:
	var copied := CastEventPayload.new()
	copied.ability_id = ability_id
	copied.action = action
	copied.fizzle_reason = fizzle_reason
	copied.resolve_tick = resolve_tick
	return copied
