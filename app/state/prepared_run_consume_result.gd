class_name PreparedRunConsumeResult
extends RefCounted

var ok: bool
var profile: ProfileState
var run: RunState
var error: DiagnosticError


static func success(
	p_profile: ProfileState,
	p_run: RunState
) -> PreparedRunConsumeResult:
	return PreparedRunConsumeResult.new(true, p_profile, p_run, null)


static func failure(p_error: DiagnosticError) -> PreparedRunConsumeResult:
	return PreparedRunConsumeResult.new(false, null, null, p_error)


func _init(
	p_ok: bool,
	p_profile: ProfileState,
	p_run: RunState,
	p_error: DiagnosticError
) -> void:
	ResultInvariant.require(
		p_ok,
		p_error,
		p_profile != null and p_run != null,
		p_profile == null and p_run == null
	)
	ok = p_ok
	profile = p_profile.deep_clone() if p_profile != null else null
	run = p_run.deep_clone() if p_run != null else null
	error = p_error.deep_clone() if p_error != null else null
