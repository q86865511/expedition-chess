class_name EncounterPreviewValidationResult
extends RefCounted

var ok: bool = false
var error: EncounterCompileError = null

static func success() -> EncounterPreviewValidationResult:
	return EncounterPreviewValidationResult.new(true, null)

static func failure(
	error_code: StringName,
	field_path: StringName,
	source_id: StringName = &""
) -> EncounterPreviewValidationResult:
	return EncounterPreviewValidationResult.new(
		false,
		EncounterCompileError.create(error_code, field_path, source_id)
	)

func _init(p_ok: bool, p_error: EncounterCompileError) -> void:
	ResultInvariant.require(p_ok, p_error, true, true)
	ok = p_ok
	error = p_error.deep_clone() if p_error != null else null
