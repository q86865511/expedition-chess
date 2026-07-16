class_name ManaEventPayload
extends BattleEventPayload

var reason: StringName = &""
var delta: int = 0
var mana_after: int = 0

func deep_clone() -> BattleEventPayload:
	var copied := ManaEventPayload.new()
	copied.reason = reason
	copied.delta = delta
	copied.mana_after = mana_after
	return copied
