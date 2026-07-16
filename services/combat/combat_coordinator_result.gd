class_name CombatCoordinatorResult
extends RefCounted

var ok: bool
var resumed_committed_result: bool
var error: CombatCoordinatorError

static func success(resumed_result: bool = false) -> CombatCoordinatorResult:
	return CombatCoordinatorResult.new(true, resumed_result, null)

static func failure(value: CombatCoordinatorError) -> CombatCoordinatorResult:
	return CombatCoordinatorResult.new(false, false, value)

func _init(
	p_ok: bool,
	p_resumed_committed_result: bool,
	p_error: CombatCoordinatorError
) -> void:
	ResultInvariant.require(
		p_ok, p_error, true, not p_resumed_committed_result
	)
	ok = p_ok
	resumed_committed_result = p_resumed_committed_result
	error = p_error.deep_clone() if p_error != null else null
