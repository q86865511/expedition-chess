class_name SaveWarning
extends RefCounted

var code: StringName
var field_path: StringName
var diagnostic_values: Array[DiagnosticValue] = []

func _init(p_code: StringName, p_field_path: StringName, p_values: Array[DiagnosticValue] = []) -> void:
	code = p_code
	field_path = p_field_path
	for value: DiagnosticValue in p_values:
		diagnostic_values.append(value.deep_clone())

func deep_clone() -> SaveWarning:
	return SaveWarning.new(code, field_path, diagnostic_values)
