class_name CommandApplyError
extends RefCounted

const ABSTRACT_COMMAND: StringName = &"RUN_ABSTRACT_COMMAND"
const ABSTRACT_EVENT: StringName = &"RUN_ABSTRACT_EVENT"
const APPLY_REJECTED: StringName = &"RUN_APPLY_REJECTED"

var code: StringName
var field_path: StringName
var source_id: OptionalStringNameValue
var diagnostic_values: Array[DiagnosticValue] = []

func _init(
	p_code: StringName,
	p_field_path: StringName,
	p_source_id: OptionalStringNameValue = null,
	p_diagnostic_values: Array[DiagnosticValue] = []
) -> void:
	code = p_code
	field_path = p_field_path
	source_id = p_source_id.deep_clone() if p_source_id != null else null
	for diagnostic: DiagnosticValue in p_diagnostic_values:
		diagnostic_values.append(diagnostic.deep_clone())

func deep_clone() -> CommandApplyError:
	return CommandApplyError.new(code, field_path, source_id, diagnostic_values)
