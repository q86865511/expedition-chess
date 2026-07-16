class_name BattleAbilityRuleSnapshot
extends RefCounted

var ability_id: StringName
var target_rule: StringName
var cast_ticks: int
var effect_ids: Array[StringName] = []

func deep_clone() -> BattleAbilityRuleSnapshot:
	var copied := BattleAbilityRuleSnapshot.new()
	copied.ability_id = ability_id
	copied.target_rule = target_rule
	copied.cast_ticks = cast_ticks
	copied.effect_ids = effect_ids.duplicate()
	return copied
