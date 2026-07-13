class_name ContentIdMigrationError
extends RefCounted

const ALIAS_INVALID: StringName = &"MIGRATION_ALIAS_INVALID"
const TOMBSTONE_REQUIRED: StringName = &"MIGRATION_TOMBSTONE_REQUIRED"

var code: StringName
var field_path: StringName
var source_id: OptionalStringNameValue
var diagnostic_values: Array[DiagnosticValue] = []

func _init(
	p_code: StringName,
	p_field_path: StringName,
	p_source_id: OptionalStringNameValue,
	p_diagnostic_values: Array[DiagnosticValue] = []
) -> void:
	code = p_code
	field_path = p_field_path
	source_id = p_source_id.deep_clone() if p_source_id != null else null
	for value: DiagnosticValue in p_diagnostic_values:
		diagnostic_values.append(value.deep_clone())

func deep_clone() -> ContentIdMigrationError:
	return ContentIdMigrationError.new(code, field_path, source_id, diagnostic_values)
