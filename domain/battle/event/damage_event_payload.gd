class_name DamageEventPayload
extends BattleEventPayload

var damage_type: StringName = &""
var raw_amount: int = 0
var post_resistance_amount: int = 0
var shield_absorbed: int = 0
var health_damage: int = 0
var health_after: int = 0

func deep_clone() -> BattleEventPayload:
	var copied := DamageEventPayload.new()
	copied.damage_type = damage_type
	copied.raw_amount = raw_amount
	copied.post_resistance_amount = post_resistance_amount
	copied.shield_absorbed = shield_absorbed
	copied.health_damage = health_damage
	copied.health_after = health_after
	return copied
