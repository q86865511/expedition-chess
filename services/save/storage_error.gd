class_name StorageError
extends RefCounted

const DIRECTORY_FAILED: StringName = &"SAVE_IO_DIRECTORY"
const EXISTS_FAILED: StringName = &"SAVE_IO_EXISTS"
const OPEN_FAILED: StringName = &"SAVE_IO_OPEN"
const WRITE_FAILED: StringName = &"SAVE_IO_WRITE"
const FLUSH_FAILED: StringName = &"SAVE_IO_FLUSH"
const CLOSE_FAILED: StringName = &"SAVE_IO_CLOSE"
const READ_FAILED: StringName = &"SAVE_IO_READ"
const RENAME_FAILED: StringName = &"SAVE_IO_RENAME"
const QUARANTINE_FAILED: StringName = &"SAVE_IO_QUARANTINE"
const RESTORE_FAILED: StringName = &"SAVE_IO_RESTORE"
const REMOVE_FAILED: StringName = &"SAVE_IO_REMOVE"
const INVALID_HANDLE: StringName = &"SAVE_IO_INVALID_HANDLE"

var code: StringName
var field_path: StringName
var source_id: OptionalStringNameValue
var diagnostic_values: Array[DiagnosticValue] = []
var operation_kind: StringName
var logical_path: StringName
var occurrence: int

func _init(
	p_code: StringName,
	p_operation_kind: StringName,
	p_logical_path: StringName,
	p_occurrence: int,
	p_field_path: StringName = &"storage",
	p_source_id: OptionalStringNameValue = null,
	p_diagnostic_values: Array[DiagnosticValue] = []
) -> void:
	code = p_code
	operation_kind = p_operation_kind
	logical_path = p_logical_path
	occurrence = p_occurrence
	field_path = p_field_path
	source_id = p_source_id.deep_clone() if p_source_id != null else null
	for value: DiagnosticValue in p_diagnostic_values:
		diagnostic_values.append(value.deep_clone())

func deep_clone() -> StorageError:
	return StorageError.new(
		code, operation_kind, logical_path, occurrence,
		field_path, source_id, diagnostic_values
	)
