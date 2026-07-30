class_name RunPresentationSessionResult
extends RefCounted

var ok: bool
var session: RunPresentationSession
var error: DiagnosticError


static func failure(p_error: DiagnosticError) -> RunPresentationSessionResult:
	return RunPresentationSessionResult.new(false, null, p_error)

static func success(
	p_session: RunPresentationSession
) -> RunPresentationSessionResult:
	return RunPresentationSessionResult.new(true, p_session, null)


func _init(
	p_ok: bool = false,
	p_session: RunPresentationSession = null,
	p_error: DiagnosticError = null
) -> void:
	ok = p_ok
	session = p_session
	error = p_error.deep_clone() if p_error != null else null
