class_name IdLedgerError
extends RefCounted

var code: StringName = &""
var field_path: StringName = &""
var source_id: StringName = &""

static func create(error_code: StringName, id: StringName, path: StringName = &"stable_id") -> IdLedgerError:
	var value := IdLedgerError.new()
	value.code = error_code
	value.source_id = id
	value.field_path = path
	return value
