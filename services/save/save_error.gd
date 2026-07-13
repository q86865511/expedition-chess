class_name SaveError
extends RefCounted

const BUSY: StringName = &"SAVE_BUSY"
const DTO_INVALID: StringName = &"SAVE_DTO_INVALID"
const CODEC_INVALID: StringName = &"SAVE_CODEC_INVALID"
const NO_VALID_COMMITTED: StringName = &"SAVE_NO_VALID_COMMITTED"
const TMP_READBACK_INVALID: StringName = &"SAVE_TMP_READBACK_INVALID"
const FINAL_READBACK_INVALID: StringName = &"SAVE_FINAL_READBACK_INVALID"
const RESTORE_FAILED: StringName = &"SAVE_RESTORE_FAILED"
const UTF8_INVALID: StringName = &"SAVE_UTF8_INVALID"

var code: StringName
var field_path: StringName
var source_id: OptionalStringNameValue
var diagnostic_values: Array[DiagnosticValue] = []
var storage_error: StorageError

func _init(
	p_code: StringName,
	p_field_path: StringName,
	p_source_id: OptionalStringNameValue = null,
	p_diagnostic_values: Array[DiagnosticValue] = [],
	p_storage_error: StorageError = null
) -> void:
	code = p_code
	field_path = p_field_path
	source_id = p_source_id.deep_clone() if p_source_id != null else null
	for value: DiagnosticValue in p_diagnostic_values:
		diagnostic_values.append(value.deep_clone())
	storage_error = p_storage_error.deep_clone() if p_storage_error != null else null

func deep_clone() -> SaveError:
	return SaveError.new(code, field_path, source_id, diagnostic_values, storage_error)
