class_name CombatCoordinatorStepResult
extends RefCounted

var ok: bool
var ticks_advanced: int
var result_committed: bool
var error: CombatCoordinatorError

static func success(ticks: int, committed: bool = false) -> CombatCoordinatorStepResult:
	return CombatCoordinatorStepResult.new(true, ticks, committed, null)

static func failure(value: CombatCoordinatorError) -> CombatCoordinatorStepResult:
	return CombatCoordinatorStepResult.new(false, 0, false, value)

func _init(
	p_ok: bool,
	p_ticks_advanced: int,
	p_result_committed: bool,
	p_error: CombatCoordinatorError
) -> void:
	ResultInvariant.require(
		p_ok,
		p_error,
		p_ticks_advanced >= 0,
		p_ticks_advanced == 0 and not p_result_committed
	)
	ok = p_ok
	ticks_advanced = p_ticks_advanced
	result_committed = p_result_committed
	error = p_error.deep_clone() if p_error != null else null
