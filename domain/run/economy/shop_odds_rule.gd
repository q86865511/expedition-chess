class_name ShopOddsRule
extends RefCounted

var level: int
var tier_basis_points: Array[int] = []

func _init(p_level: int, p_tier_basis_points: Array[int]) -> void:
	level = p_level
	tier_basis_points.assign(p_tier_basis_points)

func deep_clone() -> ShopOddsRule:
	return ShopOddsRule.new(level, tier_basis_points)
