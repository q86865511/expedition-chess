class_name StartExpeditionResult
extends RefCounted

## T05 (design.md SS4.2): typed result of StartExpeditionCommand.apply_to(). On
## success it carries BOTH the bumped profile' and the freshly bootstrapped run,
## which CampController commits atomically in one SaveRoot. Mutual exclusion
## (ok <=> profile != null and run != null and error == null).

var ok: bool
var profile: ProfileState
var run: RunState
var error: StartExpeditionError

static func success(p_profile: ProfileState, p_run: RunState) -> StartExpeditionResult:
	return StartExpeditionResult.new(true, p_profile, p_run, null)

static func failure(p_error: StartExpeditionError) -> StartExpeditionResult:
	return StartExpeditionResult.new(false, null, null, p_error)

func _init(
	p_ok: bool,
	p_profile: ProfileState,
	p_run: RunState,
	p_error: StartExpeditionError
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
