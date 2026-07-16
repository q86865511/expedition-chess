class_name HealEventPayload
extends BattleEventPayload

var requested: int = 0
var applied: int = 0
var health_after: int = 0

func deep_clone() -> BattleEventPayload:
	var copied := HealEventPayload.new()
	copied.requested = requested
	copied.applied = applied
	copied.health_after = health_after
	return copied
