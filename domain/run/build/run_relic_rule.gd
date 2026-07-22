class_name RunRelicRule
extends RefCounted

var relic_id: StringName
var category: StringName
var effect_ids: Array[StringName] = []

func deep_clone() -> RunRelicRule:
	var copied := RunRelicRule.new()
	copied.relic_id = relic_id
	copied.category = category
	copied.effect_ids = effect_ids.duplicate()
	return copied
