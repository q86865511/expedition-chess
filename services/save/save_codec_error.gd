class_name SaveCodecError
extends RefCounted

const INVALID: StringName = &"SAVE_CODEC_INVALID"
const UTF8_INVALID: StringName = &"SAVE_CODEC_UTF8_INVALID"

var code: StringName
var field_path: StringName
var diagnostic_values: Array[DiagnosticValue] = []

func _init(
	p_field_path: StringName,
	p_values: Array[DiagnosticValue] = [],
	p_code: StringName = INVALID
) -> void:
	code = p_code
	field_path = p_field_path
	for value: DiagnosticValue in p_values:
		diagnostic_values.append(value.deep_clone())

func deep_clone() -> SaveCodecError:
	return SaveCodecError.new(field_path, diagnostic_values, code)
