class_name CampCommandResult
extends RefCounted

## T04 (design.md §4.1): typed result of CampController.dispatch(). Mutual
## exclusion (ok <=> profile != null and error == null) mirrors the
## CommandApplyResult family.

var ok: bool
var profile: ProfileState
var error: CampCommandError

static func success(p_profile: ProfileState) -> CampCommandResult:
	return CampCommandResult.new(true, p_profile, null)

static func failure(p_error: CampCommandError) -> CampCommandResult:
	return CampCommandResult.new(false, null, p_error)

func _init(
	p_ok: bool,
	p_profile: ProfileState,
	p_error: CampCommandError
) -> void:
	ResultInvariant.require(p_ok, p_error, p_profile != null, p_profile == null)
	ok = p_ok
	profile = p_profile.deep_clone() if p_profile != null else null
	error = p_error.deep_clone() if p_error != null else null
