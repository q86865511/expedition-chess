class_name EncounterCompileResult
extends RefCounted

var ok: bool = false
var preview: EncounterPreviewSnapshot = null
var error: EncounterCompileError = null

static func success(value: EncounterPreviewSnapshot) -> EncounterCompileResult:
	return EncounterCompileResult.new(true, value, null)

static func failure(
	error_code: StringName,
	field_path: StringName = &"",
	source_id: StringName = &""
) -> EncounterCompileResult:
	return EncounterCompileResult.new(
		false,
		null,
		EncounterCompileError.create(error_code, field_path, source_id)
	)

func _init(
	p_ok: bool,
	p_preview: EncounterPreviewSnapshot,
	p_error: EncounterCompileError
) -> void:
	ResultInvariant.require(p_ok, p_error, p_preview != null, p_preview == null)
	ok = p_ok
	preview = p_preview.deep_clone() if p_preview != null else null
	error = p_error.deep_clone() if p_error != null else null
