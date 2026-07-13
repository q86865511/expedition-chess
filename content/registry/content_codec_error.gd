class_name ContentCodecError
extends RefCounted

var code: StringName = &"CONTENT_CODEC_INVALID"
var field_path: StringName
var source_id: OptionalStringNameValue
var diagnostic_values: Array[DiagnosticValue] = []

func _init(p_field_path: StringName = &"", p_source_id: StringName = &"") -> void:
	field_path = p_field_path
	source_id = OptionalStringNameValue.new(p_source_id) if not p_source_id.is_empty() else null
