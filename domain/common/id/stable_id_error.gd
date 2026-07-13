class_name StableIdError
extends RefCounted

const INVALID_FORMAT: StringName = &"ID_INVALID_FORMAT"

var code: StringName = INVALID_FORMAT
var field_path: StringName = &"stable_id"
var source_id: StringName = &""

static func create(path: StringName = &"stable_id") -> StableIdError:
	var value := StableIdError.new()
	value.field_path = path
	return value
