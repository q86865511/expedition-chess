class_name DiagnosticError
extends RefCounted

var source_code: StringName
var message_key: StringName


func _init(
	p_source_code: StringName = &"",
	p_message_key: StringName = &""
) -> void:
	source_code = p_source_code
	message_key = p_message_key


func deep_clone() -> DiagnosticError:
	return DiagnosticError.new(source_code, message_key)
