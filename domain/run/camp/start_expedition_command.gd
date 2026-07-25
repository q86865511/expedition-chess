class_name StartExpeditionCommand
extends RefCounted

## T05 (specs/meta-progression/design.md SS4.2; requirements.md S5-AC-002,
## S5-AC-009 前置檢查段): the thin adapter performing design.md SS4.2 step 1's
## validation clauses (commander unlocked; challenge prerequisite) before
## delegating construction to RunBootstrapService.build(). Each clause is
## independently observable and reads the caller's `profile` argument directly
## (no clone) -- a rejecting call never touches the caller's object because
## nothing is assigned to it before the success branch. See
## tests/fixtures/camp/start_expedition_test_fixture.gd's header for the full
## pinned contract.

var _commander_id: StringName
var _commander_def: CommanderDef
var _challenge_level: int
var _pinned_receipt: PinnedCatalogBuildReceipt
var _catalog: EconomyExpeditionCatalog
var _bootstrap_service: RunBootstrapService

func _init(
	p_commander_id: StringName,
	p_commander_def: CommanderDef,
	p_challenge_level: int,
	p_pinned_receipt: PinnedCatalogBuildReceipt,
	p_catalog: EconomyExpeditionCatalog,
	p_bootstrap_service: RunBootstrapService = null
) -> void:
	_commander_id = p_commander_id
	_commander_def = p_commander_def
	_challenge_level = p_challenge_level
	_pinned_receipt = p_pinned_receipt
	# The pinned-generation catalog the new run's unit pool is dealt from; the
	# caller resolves it exactly like every other S3 service call site does.
	_catalog = p_catalog
	_bootstrap_service = (
		p_bootstrap_service if p_bootstrap_service != null else RunBootstrapService.new()
	)

func is_concrete() -> bool:
	return _commander_def != null and _pinned_receipt != null \
		and _catalog != null and _challenge_level >= 0

func apply_to(profile: ProfileState) -> StartExpeditionResult:
	# a. structural guard.
	if not is_concrete():
		return StartExpeditionResult.failure(
			StartExpeditionError.new(StartExpeditionError.INPUT_INVALID, &"command")
		)
	# b. commander must be unlocked.
	if not profile.unlocked_content_ids.has(_commander_id):
		return StartExpeditionResult.failure(
			StartExpeditionError.new(
				StartExpeditionError.EXPEDITION_COMMANDER_LOCKED,
				&"profile.unlocked_content_ids"
			)
		)
	# c. challenge prerequisite: level 0 always passes; otherwise this commander's
	#    highest cleared level must be >= challenge_level - 1.
	if _challenge_level > 0 and not _challenge_prerequisite_met(profile):
		return StartExpeditionResult.failure(
			StartExpeditionError.new(
				StartExpeditionError.EXPEDITION_CHALLENGE_PREREQUISITE_UNMET,
				&"profile.commander_challenge_records"
			)
		)
	# d. the success branch bumps next_run_serial; U64Bits.add() wraps silently at
	#    the ceiling, which would make the new run reuse the profile's very first
	#    run_key/run_id/run_seed. Checked here, before build(), so an exhausted
	#    profile changes nothing at all.
	if profile.next_run_serial.equals(U64Bits.max_value()):
		return StartExpeditionResult.failure(
			StartExpeditionError.new(
				StartExpeditionError.SERIAL_EXHAUSTED, &"profile.next_run_serial"
			)
		)
	# e. delegate construction; a structural build failure is not a domain
	#    rejection, so it surfaces as INPUT_INVALID.
	var bootstrap := _bootstrap_service.build(
		profile, _commander_def, _challenge_level, _pinned_receipt, _catalog
	)
	if not bootstrap.ok:
		return StartExpeditionResult.failure(
			StartExpeditionError.new(StartExpeditionError.INPUT_INVALID, &"run")
		)
	# f. success: profile' bumps next_run_serial and records the selection. The
	#    caller's profile argument is never mutated (clone before assigning).
	var profile_prime := profile.deep_clone()
	profile_prime.next_run_serial = profile.next_run_serial.add(U64Bits.one())
	profile_prime.last_selection = ProfileLastSelectionState.new(
		_commander_id, _challenge_level
	)
	return StartExpeditionResult.success(profile_prime, bootstrap.run)

func _challenge_prerequisite_met(profile: ProfileState) -> bool:
	for record: CommanderChallengeRecordState in profile.commander_challenge_records:
		if record.commander_id == _commander_id \
			and record.highest_cleared_level >= _challenge_level - 1:
			return true
	return false
