class_name LoadDiagnostic
extends RefCounted

const RECOVERED_BACKUP: StringName = &"LOAD_RECOVERED_BACKUP"
const INCOMPATIBLE_RUN: StringName = &"LOAD_INCOMPATIBLE_RUN"

var code: StringName
var field_path: StringName
var diagnostic_values: Array[DiagnosticValue] = []

func _init(p_code: StringName, p_field_path: StringName, p_values: Array[DiagnosticValue] = []) -> void:
	code = p_code
	field_path = p_field_path
	for value: DiagnosticValue in p_values:
		diagnostic_values.append(value.deep_clone())

func deep_clone() -> LoadDiagnostic:
	return LoadDiagnostic.new(code, field_path, diagnostic_values)
