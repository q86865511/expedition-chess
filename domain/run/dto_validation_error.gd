class_name DtoValidationError
extends RefCounted

const CODE_INVALID: StringName = &"SAVE_DTO_INVALID"

var code: StringName
var field_path: StringName
var source_id: OptionalStringNameValue
var diagnostic_values: Array[DiagnosticValue] = []

func _init(
	p_field_path: StringName,
	p_source_id: OptionalStringNameValue = null,
	p_diagnostic_values: Array[DiagnosticValue] = []
) -> void:
	code = CODE_INVALID
	field_path = p_field_path
	source_id = p_source_id.deep_clone() if p_source_id != null else null
	for diagnostic: DiagnosticValue in p_diagnostic_values:
		diagnostic_values.append(diagnostic.deep_clone())

func deep_clone() -> DtoValidationError:
	return DtoValidationError.new(field_path, source_id, diagnostic_values)
