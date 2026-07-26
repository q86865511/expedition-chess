class_name StartExpeditionCampResult
extends RefCounted

## T05 (design.md SS4.2): typed result of
## CampController.dispatch_start_expedition(). Carries profile' and the created
## run back to the caller (the run is needed for T11's same-turn AppStateMachine
## transition). Mutual exclusion
## (ok <=> profile != null and run != null and error == null); on failure the
## error is a CampCommandError (structural CAMP_* code, or a domain rejection
## code passed straight through from StartExpeditionError).
##
## T11 (design.md SS4.4): `save_result` is the SaveResult object the successful
## dispatch's own SaveRepository.save() call returned -- AppStateMachine
## .transition_after_save(START_RUN, ...) consumes a ONE-TIME capability token
## minted by that exact call (save_repository.gd:230-242), so the composition
## root cannot construct or reuse one; it has to be handed the original object.
## It is deliberately NOT deep-cloned (a clone would carry no capability and be
## rejected) and is null on failure -- an added field, not a changed signature:
## success(profile, run) keeps working for callers that do not need the proof.

var ok: bool
var profile: ProfileState
var run: RunState
var save_result: SaveResult
var error: CampCommandError

static func success(
	p_profile: ProfileState,
	p_run: RunState,
	p_save_result: SaveResult = null
) -> StartExpeditionCampResult:
	return StartExpeditionCampResult.new(true, p_profile, p_run, p_save_result, null)

static func failure(p_error: CampCommandError) -> StartExpeditionCampResult:
	return StartExpeditionCampResult.new(false, null, null, null, p_error)

func _init(
	p_ok: bool,
	p_profile: ProfileState,
	p_run: RunState,
	p_save_result: SaveResult,
	p_error: CampCommandError
) -> void:
	ResultInvariant.require(
		p_ok,
		p_error,
		p_profile != null and p_run != null,
		p_profile == null and p_run == null and p_save_result == null
	)
	ok = p_ok
	profile = p_profile.deep_clone() if p_profile != null else null
	run = p_run.deep_clone() if p_run != null else null
	save_result = p_save_result
	error = p_error.deep_clone() if p_error != null else null
