class_name ShopUnitRule
extends RefCounted

var unit_id: StringName
var cost_tier: int
var cost: int

func _init(p_unit_id: StringName, p_cost_tier: int, p_cost: int) -> void:
	unit_id = p_unit_id
	cost_tier = p_cost_tier
	cost = p_cost

func deep_clone() -> ShopUnitRule:
	return ShopUnitRule.new(unit_id, cost_tier, cost)
