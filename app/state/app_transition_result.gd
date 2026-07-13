class_name AppTransitionResult
extends RefCounted

var ok: bool
var state: int
var error: AppTransitionError

static func success(p_state: int) -> AppTransitionResult:
	return AppTransitionResult.new(true, p_state, null)

static func failure(p_state: int, p_error: AppTransitionError) -> AppTransitionResult:
	return AppTransitionResult.new(false, p_state, p_error)

func _init(p_ok: bool, p_state: int, p_error: AppTransitionError) -> void:
	ResultInvariant.require(p_ok, p_error, true, true)
	ok = p_ok
	state = p_state
	error = p_error.deep_clone() if p_error != null else null
