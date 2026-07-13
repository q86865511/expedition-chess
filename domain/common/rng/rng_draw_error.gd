class_name RngDrawError
extends RefCounted

var code: StringName = &""
var field_path: StringName = &""
var source_id: StringName = &""

static func create(error_code: StringName, path: StringName = &"") -> RngDrawError:
	var value := RngDrawError.new()
	value.code = error_code
	value.field_path = path
	return value
