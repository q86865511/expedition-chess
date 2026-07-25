class_name RunBootstrapResult
extends RefCounted

## T05 (design.md SS4.2): typed result of RunBootstrapService.build(). Mutual
## exclusion (ok <=> run != null and error == null) mirrors the CommandApplyResult
## family (domain/run/controller/command_apply_result.gd).

var ok: bool
var run: RunState
var error: RunBootstrapError

static func success(p_run: RunState) -> RunBootstrapResult:
	return RunBootstrapResult.new(true, p_run, null)

static func failure(p_error: RunBootstrapError) -> RunBootstrapResult:
	return RunBootstrapResult.new(false, null, p_error)

func _init(
	p_ok: bool,
	p_run: RunState,
	p_error: RunBootstrapError
) -> void:
	ResultInvariant.require(p_ok, p_error, p_run != null, p_run == null)
	ok = p_ok
	run = p_run.deep_clone() if p_run != null else null
	error = p_error.deep_clone() if p_error != null else null
