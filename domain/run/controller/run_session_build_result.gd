class_name RunSessionBuildResult
extends RefCounted

var ok: bool
var session: RunSession
var error: RunSessionBuildError

static func success(p_session: RunSession) -> RunSessionBuildResult:
	return RunSessionBuildResult.new(true, p_session, null)

static func failure(p_error: RunSessionBuildError) -> RunSessionBuildResult:
	return RunSessionBuildResult.new(false, null, p_error)

func _init(
	p_ok: bool,
	p_session: RunSession,
	p_error: RunSessionBuildError
) -> void:
	ResultInvariant.require(p_ok, p_error, p_session != null, p_session == null)
	ok = p_ok
	session = p_session
	error = p_error.deep_clone() if p_error != null else null
