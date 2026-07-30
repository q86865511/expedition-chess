class_name RunPresentationResult
extends RefCounted

var ok: bool
var committed: bool
var presentation_ok: bool
var snapshot: RunPresentationSnapshot
var error: DiagnosticError
var source: DiagnosticError


static func failure(p_error: DiagnosticError) -> RunPresentationResult:
	return precommit_failure(p_error, RunPresentationSnapshot.new())


static func success(p_snapshot: RunPresentationSnapshot) -> RunPresentationResult:
	return RunPresentationResult.new(true, true, true, p_snapshot, null)


static func precommit_failure(
	p_error: DiagnosticError,
	p_snapshot: RunPresentationSnapshot
) -> RunPresentationResult:
	return RunPresentationResult.new(false, false, false, p_snapshot, p_error)


static func postcommit_failure(
	p_error: DiagnosticError,
	p_snapshot: RunPresentationSnapshot
) -> RunPresentationResult:
	return RunPresentationResult.new(false, true, false, p_snapshot, p_error)


func _init(
	p_ok: bool,
	p_committed: bool,
	p_presentation_ok: bool,
	p_snapshot: RunPresentationSnapshot,
	p_error: DiagnosticError = null
) -> void:
	ResultInvariant.require(
		p_ok,
		p_error,
		p_committed and p_presentation_ok and p_snapshot != null,
		not p_presentation_ok and p_snapshot != null
	)
	ok = p_ok
	committed = p_committed
	presentation_ok = p_presentation_ok
	snapshot = p_snapshot.deep_clone() if p_snapshot != null else null
	error = p_error.deep_clone() if p_error != null else null
	source = p_error.deep_clone() if p_error != null else null
