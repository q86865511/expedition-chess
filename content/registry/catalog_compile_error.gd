class_name CatalogCompileError
extends RefCounted

var code: StringName
var field_path: StringName
var source_id: OptionalStringNameValue
var diagnostic_values: Array[DiagnosticValue] = []

func _init(p_code: StringName = &"CONTENT_VALIDATION_FAILED", p_path: StringName = &"", p_source: StringName = &"") -> void:
	code = p_code
	field_path = p_path
	source_id = OptionalStringNameValue.new(p_source) if not p_source.is_empty() else null
