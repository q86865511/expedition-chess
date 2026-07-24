class_name UnlockPurchaseResult
extends RefCounted

## T04 (design.md §4.3): typed result of UnlockPurchaseService.purchase(). Mutual
## exclusion (ok <=> profile != null and error == null) mirrors the
## CommandApplyResult family (domain/run/controller/command_apply_result.gd).

var ok: bool
var profile: ProfileState
var error: UnlockPurchaseError

static func success(p_profile: ProfileState) -> UnlockPurchaseResult:
	return UnlockPurchaseResult.new(true, p_profile, null)

static func failure(p_error: UnlockPurchaseError) -> UnlockPurchaseResult:
	return UnlockPurchaseResult.new(false, null, p_error)

func _init(
	p_ok: bool,
	p_profile: ProfileState,
	p_error: UnlockPurchaseError
) -> void:
	ResultInvariant.require(p_ok, p_error, p_profile != null, p_profile == null)
	ok = p_ok
	profile = p_profile.deep_clone() if p_profile != null else null
	error = p_error.deep_clone() if p_error != null else null
