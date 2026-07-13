class_name ContentValidationIssue
extends RefCounted

var severity: StringName = &"error"
var code: StringName
var source_id: StringName
var field_path: StringName
var diagnostic_values: Array[DiagnosticValue] = []

func _init(p_code: StringName = &"CONTENT_VALIDATION_FAILED", p_source_id: StringName = &"", p_path: StringName = &"", p_detail: String = "") -> void:
	code = p_code
	source_id = p_source_id
	field_path = p_path
	if not p_detail.is_empty(): diagnostic_values.append(DiagnosticValue.from_string(&"detail", p_detail))

func deep_clone() -> ContentValidationIssue:
	var result := ContentValidationIssue.new(code, source_id, field_path)
	for value in diagnostic_values: result.diagnostic_values.append(value.deep_clone())
	return result
