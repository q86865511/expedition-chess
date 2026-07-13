class_name U64ParseError
extends RefCounted

const INVALID_HEX: StringName = &"U64_INVALID_HEX"

var code: StringName = INVALID_HEX
var field_path: StringName = &""
var source_id: StringName = &""

static func create(path: StringName = &"") -> U64ParseError:
	var value := U64ParseError.new()
	value.field_path = path
	return value
