class_name CatalogLeaseError
extends RefCounted

var code: StringName
var field_path: StringName
var source_id: OptionalStringNameValue
var diagnostic_values: Array[DiagnosticValue] = []

func _init(p_code: StringName = &"CONTENT_CATALOG_MISSING", p_path: StringName = &"catalog_handle") -> void:
	code = p_code
	field_path = p_path
