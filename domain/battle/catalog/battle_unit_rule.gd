class_name BattleUnitRule
extends RefCounted

var unit_id: StringName
var cost_tier: int
var trait_ids: Array[StringName] = []
var base_stats: BattleUnitStatsRule
var star_scalings: Array[BattleStarScalingRule] = []
var ability_id: OptionalStringNameValue
var ai_profile: StringName
var basic_attack_profile: StringName
var availability: StringName
var shop_condition: StringName
var effect_ids: Array[StringName] = []

func deep_clone() -> BattleUnitRule:
	var copied := BattleUnitRule.new()
	copied.unit_id = unit_id
	copied.cost_tier = cost_tier
	copied.trait_ids = trait_ids.duplicate()
	copied.base_stats = base_stats.deep_clone() if base_stats != null else null
	for scaling: BattleStarScalingRule in star_scalings:
		copied.star_scalings.append(scaling.deep_clone())
	copied.ability_id = ability_id.deep_clone() if ability_id != null else null
	copied.ai_profile = ai_profile
	copied.basic_attack_profile = basic_attack_profile
	copied.availability = availability
	copied.shop_condition = shop_condition
	copied.effect_ids = effect_ids.duplicate()
	return copied
