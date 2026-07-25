class_name StartExpeditionCampResult
extends RefCounted

## T05 (design.md SS4.2): typed result of
## CampController.dispatch_start_expedition(). Carries profile' and the created
## run back to the caller (the run is needed for T11's same-turn AppStateMachine
## transition, out of scope here). Mutual exclusion
## (ok <=> profile != null and run != null and error == null); on failure the
## error is a CampCommandError (structural CAMP_* code, or a domain rejection
## code passed straight through from StartExpeditionError).

var ok: bool
var profile: ProfileState
var run: RunState
var error: CampCommandError

static func success(p_profile: ProfileState, p_run: RunState) -> StartExpeditionCampResult:
	return StartExpeditionCampResult.new(true, p_profile, p_run, null)

static func failure(p_error: CampCommandError) -> StartExpeditionCampResult:
	return StartExpeditionCampResult.new(false, null, null, p_error)

func _init(
	p_ok: bool,
	p_profile: ProfileState,
	p_run: RunState,
	p_error: CampCommandError
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
