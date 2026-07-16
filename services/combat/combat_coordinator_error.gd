class_name CombatCoordinatorError
extends RefCounted

const LIFECYCLE_INVALID: StringName = &"COMBAT_COORDINATOR_LIFECYCLE_INVALID"
const COMMITTED_STATE_INVALID: StringName = &"COMBAT_COMMITTED_STATE_INVALID"
const SETUP_ENVELOPE_INVALID: StringName = &"COMBAT_SETUP_ENVELOPE_INVALID"
const SIMULATION_INITIALIZATION_FAILED: StringName = &"COMBAT_SIMULATION_INITIALIZATION_FAILED"
const SIMULATION_STEP_FAILED: StringName = &"COMBAT_SIMULATION_STEP_FAILED"
const RESULT_QUERY_FAILED: StringName = &"COMBAT_RESULT_QUERY_FAILED"
const RESULT_COMMIT_FAILED: StringName = &"COMBAT_RESULT_COMMIT_FAILED"

var code: StringName
var field_path: StringName
var source_code: StringName

func _init(
	p_code: StringName,
	p_field_path: StringName = &"",
	p_source_code: StringName = &""
) -> void:
	code = p_code
	field_path = p_field_path
	source_code = p_source_code

func deep_clone() -> CombatCoordinatorError:
	return CombatCoordinatorError.new(code, field_path, source_code)
