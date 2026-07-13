class_name RuntimeKeyError
extends RefCounted

var code: StringName = &""
var field_path: StringName = &""
var source_id: StringName = &""

static func create(error_code: StringName, path: StringName = &"") -> RuntimeKeyError:
	var value := RuntimeKeyError.new()
	value.code = error_code
	value.field_path = path
	return value
