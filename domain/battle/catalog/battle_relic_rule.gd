class_name BattleRelicRule
extends RefCounted

var relic_id: StringName
var battle_effect_ids: Array[StringName] = []

func deep_clone() -> BattleRelicRule:
	var copied := BattleRelicRule.new()
	copied.relic_id = relic_id
	copied.battle_effect_ids = battle_effect_ids.duplicate()
	return copied
