class_name ExpeditionActionResult
extends RefCounted

var ok: bool
var run_state: RunState
var error: ExpeditionActionError

static func success(value: RunState) -> ExpeditionActionResult:
	return ExpeditionActionResult.new(true, value, null)

static func failure(code: StringName, path: StringName) -> ExpeditionActionResult:
	return ExpeditionActionResult.new(
		false, null, ExpeditionActionError.new(code, path)
	)

func _init(
	p_ok: bool,
	p_run_state: RunState,
	p_error: ExpeditionActionError
) -> void:
	ResultInvariant.require(p_ok, p_error, p_run_state != null, p_run_state == null)
	ok = p_ok
	run_state = p_run_state.deep_clone() if p_run_state != null else null
	error = p_error.deep_clone() if p_error != null else null
