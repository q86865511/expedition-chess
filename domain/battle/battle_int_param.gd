class_name BattleIntParam
extends RefCounted

var key: StringName = &""
var value: int = 0

func deep_clone() -> BattleIntParam:
	var copied := BattleIntParam.new()
	copied.key = key
	copied.value = value
	return copied
