class_name ModifierEventPayload
extends BattleEventPayload

var stat: StringName = &""
var mode: StringName = &""
var amount: int = 0
var expires_tick: int = 0
var action: StringName = &""

func deep_clone() -> BattleEventPayload:
	var copied := ModifierEventPayload.new()
	copied.stat = stat
	copied.mode = mode
	copied.amount = amount
	copied.expires_tick = expires_tick
	copied.action = action
	return copied
