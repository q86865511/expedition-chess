class_name CommandError
extends RefCounted

const INVALID_COMMAND: StringName = &"RUN_INVALID_COMMAND"
const APPLY_FAILED: StringName = &"RUN_COMMAND_APPLY_FAILED"
const VALIDATION_FAILED: StringName = &"RUN_VALIDATION_FAILED"
const SAVE_FAILED: StringName = &"RUN_SAVE_FAILED"
const PUBLICATION_SERIAL_EXHAUSTED: StringName = &"RUN_PUBLICATION_SERIAL_EXHAUSTED"
const TRANSACTION_BUSY: StringName = &"RUN_TRANSACTION_BUSY"

var code: StringName
var phase: RunState.RunPhase
var field_path: StringName
var source_id: OptionalStringNameValue
var diagnostic_values: Array[DiagnosticValue] = []

func _init(
	p_code: StringName,
	p_phase: RunState.RunPhase,
	p_field_path: StringName,
	p_source_id: OptionalStringNameValue = null,
	p_diagnostic_values: Array[DiagnosticValue] = []
) -> void:
	code = p_code
	phase = p_phase
	field_path = p_field_path
	source_id = p_source_id.deep_clone() if p_source_id != null else null
	for diagnostic: DiagnosticValue in p_diagnostic_values:
		diagnostic_values.append(diagnostic.deep_clone())

func deep_clone() -> CommandError:
	return CommandError.new(code, phase, field_path, source_id, diagnostic_values)
