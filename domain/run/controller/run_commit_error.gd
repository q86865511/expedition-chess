class_name RunCommitError
extends RefCounted

enum Kind { VALIDATION, SAVE, SERIAL_EXHAUSTED, BUSY }

var kind: Kind
var field_path: StringName
var source_code: StringName

func _init(p_kind: Kind, p_field_path: StringName, p_source_code: StringName) -> void:
	kind = p_kind
	field_path = p_field_path
	source_code = p_source_code

func deep_clone() -> RunCommitError:
	return RunCommitError.new(kind, field_path, source_code)
