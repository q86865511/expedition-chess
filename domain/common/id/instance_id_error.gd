class_name InstanceIdError
extends RefCounted

var code: StringName = &""
var field_path: StringName = &"serial"
var source_id: StringName = &""

static func create(error_code: StringName, path: StringName = &"serial") -> InstanceIdError:
	var value := InstanceIdError.new()
	value.code = error_code
	value.field_path = path
	return value
