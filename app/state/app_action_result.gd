class_name AppActionResult
extends RefCounted

var ok: bool
var committed: bool
var presentation_ok: bool
var error: DiagnosticError


static func success(p_committed: bool = false) -> AppActionResult:
	return AppActionResult.new(true, p_committed, true, null)


static func failure(p_error: DiagnosticError) -> AppActionResult:
	return AppActionResult.new(false, false, false, p_error)


static func committed_presentation_failure(
	p_error: DiagnosticError
) -> AppActionResult:
	return AppActionResult.new(false, true, false, p_error)


func _init(
	p_ok: bool,
	p_committed: bool,
	p_presentation_ok: bool,
	p_error: DiagnosticError
) -> void:
	ResultInvariant.require(
		p_ok,
		p_error,
		p_presentation_ok,
		not p_presentation_ok
	)
	ok = p_ok
	committed = p_committed
	presentation_ok = p_presentation_ok
	error = p_error.deep_clone() if p_error != null else null
