class_name SettingsStorageResult
extends RefCounted

## Named result for every SettingsStoragePort operation. Keeps the
## ok/exists/bytes shape SettingsRepository always drove, but as a typed
## boundary instead of an untyped Dictionary crossing services/settings'
## public API (project convention: JSON Dictionary only lives at the
## SaveJsonCodec boundary; public domain APIs use named types).

var ok: bool
var exists: bool
var bytes: OptionalBytesValue
var error: DiagnosticError


static func success(
	p_exists: bool = true,
	p_bytes: PackedByteArray = PackedByteArray()
) -> SettingsStorageResult:
	return SettingsStorageResult.new(true, p_exists, OptionalBytesValue.new(p_bytes), null)


static func failure(p_error_code: StringName) -> SettingsStorageResult:
	return SettingsStorageResult.new(
		false, false, null, DiagnosticError.new(p_error_code, &"error.settings.storage_fault")
	)


func _init(
	p_ok: bool,
	p_exists: bool,
	p_bytes: OptionalBytesValue,
	p_error: DiagnosticError
) -> void:
	ResultInvariant.require(p_ok, p_error, p_bytes != null, p_bytes == null)
	ok = p_ok
	exists = p_exists
	bytes = p_bytes.deep_clone() if p_bytes != null else null
	error = p_error.deep_clone() if p_error != null else null


func error_code() -> StringName:
	return error.source_code if error != null else &""


## Never null: empty bytes for a failed or non-existent read.
func bytes_value() -> PackedByteArray:
	return bytes.value.duplicate() if bytes != null else PackedByteArray()
