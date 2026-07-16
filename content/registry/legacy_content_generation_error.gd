class_name LegacyContentGenerationError
extends RefCounted

const INPUT_INVALID: StringName = &"LEGACY_CONTENT_GENERATION_INPUT_INVALID"
const CODEC_INVALID: StringName = &"LEGACY_CONTENT_GENERATION_CODEC_INVALID"
const SOURCE_MISMATCH: StringName = &"LEGACY_CONTENT_GENERATION_SOURCE_MISMATCH"
const DUPLICATE_CONFLICT: StringName = &"LEGACY_CONTENT_GENERATION_DUPLICATE_CONFLICT"

var code: StringName
var field_path: StringName

func _init(p_code: StringName, p_field_path: StringName = &"") -> void:
	code = p_code
	field_path = p_field_path

func deep_clone() -> LegacyContentGenerationError:
	return LegacyContentGenerationError.new(code, field_path)
