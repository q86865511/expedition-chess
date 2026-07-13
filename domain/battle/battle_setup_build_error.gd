class_name BattleSetupBuildError
extends RefCounted

var code: StringName = &""
var field_path: StringName = &""
var source_id: StringName = &""

static func create(error_code: StringName, path: StringName = &"") -> BattleSetupBuildError:
	var value := BattleSetupBuildError.new()
	value.code = error_code
	value.field_path = path
	return value
