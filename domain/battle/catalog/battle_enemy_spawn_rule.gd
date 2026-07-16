class_name BattleEnemySpawnRule
extends RefCounted

var side: StringName
var logical_y: int
var logical_x: int
var spawn_key: String
var unit_id: StringName
var star: int
var effect_ids: Array[StringName] = []

func deep_clone() -> BattleEnemySpawnRule:
	var copied := BattleEnemySpawnRule.new()
	copied.side = side
	copied.logical_y = logical_y
	copied.logical_x = logical_x
	copied.spawn_key = spawn_key
	copied.unit_id = unit_id
	copied.star = star
	copied.effect_ids = effect_ids.duplicate()
	return copied
