class_name ShieldEventPayload
extends BattleEventPayload

var delta: int = 0
var remaining: int = 0
var expires_tick: int = 0

func deep_clone() -> BattleEventPayload:
	var copied := ShieldEventPayload.new()
	copied.delta = delta
	copied.remaining = remaining
	copied.expires_tick = expires_tick
	return copied
