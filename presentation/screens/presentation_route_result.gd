class_name PresentationRouteResult
extends RefCounted

var ok: bool
var state: PresentationRouteState
var error: DiagnosticError


static func success(p_state: PresentationRouteState) -> PresentationRouteResult:
	return PresentationRouteResult.new(true, p_state, null)


static func failure(p_error: DiagnosticError) -> PresentationRouteResult:
	return PresentationRouteResult.new(false, null, p_error)


func _init(
	p_ok: bool = false,
	p_state: PresentationRouteState = null,
	p_error: DiagnosticError = null
) -> void:
	ok = p_ok
	state = p_state.deep_clone() if p_state != null else null
	error = p_error.deep_clone() if p_error != null else null
