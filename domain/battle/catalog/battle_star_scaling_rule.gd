class_name BattleStarScalingRule
extends RefCounted

var star: int
var health_bps: int
var attack_bps: int
var armor_bps: int
var magic_resist_bps: int
var attack_speed_bps: int
var attack_range_bps: int
var start_mana_bps: int
var max_mana_bps: int
var move_speed_bps: int

func deep_clone() -> BattleStarScalingRule:
	var copied := BattleStarScalingRule.new()
	copied.star = star
	copied.health_bps = health_bps
	copied.attack_bps = attack_bps
	copied.armor_bps = armor_bps
	copied.magic_resist_bps = magic_resist_bps
	copied.attack_speed_bps = attack_speed_bps
	copied.attack_range_bps = attack_range_bps
	copied.start_mana_bps = start_mana_bps
	copied.max_mana_bps = max_mana_bps
	copied.move_speed_bps = move_speed_bps
	return copied
