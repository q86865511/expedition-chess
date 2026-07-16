class_name EncounterCompileError
extends RefCounted

var code: StringName = &""
var field_path: StringName = &""
var source_id: StringName = &""

static func create(
	error_code: StringName,
	path: StringName = &"",
	p_source_id: StringName = &""
) -> EncounterCompileError:
	var value := EncounterCompileError.new()
	value.code = error_code
	value.field_path = path
	value.source_id = p_source_id
	return value

func deep_clone() -> EncounterCompileError:
	return create(code, field_path, source_id)
