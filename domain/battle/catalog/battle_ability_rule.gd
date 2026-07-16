class_name BattleAbilityRule
extends RefCounted

var ability_id: StringName
var start_mana: int
var max_mana: int
var target_rule: StringName
var cast_ticks: int
var effect_ids: Array[StringName] = []

func deep_clone() -> BattleAbilityRule:
	var copied := BattleAbilityRule.new()
	copied.ability_id = ability_id
	copied.start_mana = start_mana
	copied.max_mana = max_mana
	copied.target_rule = target_rule
	copied.cast_ticks = cast_ticks
	copied.effect_ids = effect_ids.duplicate()
	return copied
