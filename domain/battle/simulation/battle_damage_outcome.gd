class_name BattleDamageOutcome
extends RefCounted

var request: BattleDamageRequest
var applied_amount: int = 0
var post_resistance_amount: int = 0
var shield_absorbed: int = 0
var health_damage: int = 0

func deep_clone() -> BattleDamageOutcome:
	var copied := BattleDamageOutcome.new()
	copied.request = request.deep_clone() if request != null else null
	copied.applied_amount = applied_amount
	copied.post_resistance_amount = post_resistance_amount
	copied.shield_absorbed = shield_absorbed
	copied.health_damage = health_damage
	return copied
