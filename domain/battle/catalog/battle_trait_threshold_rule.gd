class_name BattleTraitThresholdRule
extends RefCounted

var required_count: int
var effect_ids: Array[StringName] = []

func deep_clone() -> BattleTraitThresholdRule:
	var copied := BattleTraitThresholdRule.new()
	copied.required_count = required_count
	copied.effect_ids = effect_ids.duplicate()
	return copied
