class_name AttackEventPayload
extends BattleEventPayload

var raw_damage: int = 0
var presentation_profile: StringName = &""

func deep_clone() -> BattleEventPayload:
	var copied := AttackEventPayload.new()
	copied.raw_damage = raw_damage
	copied.presentation_profile = presentation_profile
	return copied
