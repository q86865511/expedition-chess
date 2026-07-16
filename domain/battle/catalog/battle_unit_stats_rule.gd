class_name BattleUnitStatsRule
extends RefCounted

var health: int
var attack: int
var armor: int
var magic_resist: int
var attack_speed_milli: int
var attack_range_cells: int
var start_mana: int
var max_mana: int
var move_speed_milli: int

func deep_clone() -> BattleUnitStatsRule:
	var copied := BattleUnitStatsRule.new()
	copied.health = health
	copied.attack = attack
	copied.armor = armor
	copied.magic_resist = magic_resist
	copied.attack_speed_milli = attack_speed_milli
	copied.attack_range_cells = attack_range_cells
	copied.start_mana = start_mana
	copied.max_mana = max_mana
	copied.move_speed_milli = move_speed_milli
	return copied
