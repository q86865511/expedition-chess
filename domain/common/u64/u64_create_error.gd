class_name U64CreateError
extends RefCounted

const INVALID_LIMB: StringName = &"U64_INVALID_LIMB"

var code: StringName = INVALID_LIMB
var field_path: StringName = &""
var source_id: StringName = &""

static func create(path: StringName = &"") -> U64CreateError:
	var value := U64CreateError.new()
	value.field_path = path
	return value
