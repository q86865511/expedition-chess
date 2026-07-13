class_name BattleIdParam
extends RefCounted

var key: StringName = &""
var value: StringName = &""

func deep_clone() -> BattleIdParam:
	var copied := BattleIdParam.new()
	copied.key = key
	copied.value = value
	return copied
