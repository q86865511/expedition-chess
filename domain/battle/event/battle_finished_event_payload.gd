class_name BattleFinishedEventPayload
extends BattleEventPayload

var outcome: StringName = &""
var expedition_damage: int = 0

func deep_clone() -> BattleEventPayload:
	var copied := BattleFinishedEventPayload.new()
	copied.outcome = outcome
	copied.expedition_damage = expedition_damage
	return copied
