class_name RunCommitResult
extends RefCounted

var ok: bool
var view_state: RunViewState
var error: RunCommitError

static func success(p_view_state: RunViewState) -> RunCommitResult:
	return RunCommitResult.new(true, p_view_state, null)

static func failure(p_error: RunCommitError) -> RunCommitResult:
	return RunCommitResult.new(false, null, p_error)

func _init(p_ok: bool, p_view_state: RunViewState, p_error: RunCommitError) -> void:
	ResultInvariant.require(
		p_ok, p_error, p_view_state != null, p_view_state == null
	)
	ok = p_ok
	view_state = p_view_state.deep_clone() if p_view_state != null else null
	error = p_error.deep_clone() if p_error != null else null
