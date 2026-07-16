class_name BattleEntityIdError
extends RefCounted

var code: StringName = &""
var field_path: StringName = &""

static func create(error_code: StringName, path: StringName = &"") -> BattleEntityIdError:
	var value := BattleEntityIdError.new()
	value.code = error_code
	value.field_path = path
	return value

func deep_clone() -> BattleEntityIdError:
	return create(code, field_path)
