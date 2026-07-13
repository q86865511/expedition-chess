class_name ContentResolveError
extends RefCounted

var code: StringName
var field_path: StringName
var source_id: OptionalStringNameValue
var diagnostic_values: Array[DiagnosticValue] = []

func _init(
	p_code: StringName,
	p_field_path: StringName,
	p_source_id: StringName = &""
) -> void:
	code = p_code
	field_path = p_field_path
	source_id = OptionalStringNameValue.new(p_source_id) if not p_source_id.is_empty() else null

func deep_clone() -> ContentResolveError:
	return ContentResolveError.new(
		code,
		field_path,
		source_id.value if source_id != null else &""
	)
