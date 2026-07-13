class_name U64ShiftError
extends RefCounted

const INVALID_SHIFT: StringName = &"U64_INVALID_SHIFT"

var code: StringName = INVALID_SHIFT
var field_path: StringName = &"count"
var source_id: StringName = &""

static func create() -> U64ShiftError:
	return U64ShiftError.new()
