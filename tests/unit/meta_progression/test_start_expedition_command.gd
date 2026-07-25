extends GutTest

## T05 (specs/meta-progression/design.md SS4.2; requirements.md S5-AC-002,
## S5-AC-009 前置檢查段): StartExpeditionCommand is the thin adapter performing
## design.md SS4.2 step 1's validation clauses (commander unlocked; challenge
## prerequisite) before delegating to RunBootstrapService.build(). See
## tests/fixtures/camp/start_expedition_test_fixture.gd's header for the full
## pinned contract.

func test_is_concrete_false_when_commander_def_missing() -> void:
	var command := StartExpeditionCommand.new(
		StartExpeditionTestFixture.COMMANDER_ALPHA_ID, null, 0,
		StartExpeditionTestFixture.receipt(), StartExpeditionTestFixture.catalog()
	)
	assert_false(command.is_concrete())


func test_is_concrete_false_when_pinned_receipt_missing() -> void:
	var command := StartExpeditionCommand.new(
		StartExpeditionTestFixture.COMMANDER_ALPHA_ID,
		StartExpeditionTestFixture.commander_alpha(), 0, null,
		StartExpeditionTestFixture.catalog()
	)
	assert_false(command.is_concrete())


func test_is_concrete_false_when_catalog_missing() -> void:
	var command := StartExpeditionCommand.new(
		StartExpeditionTestFixture.COMMANDER_ALPHA_ID,
		StartExpeditionTestFixture.commander_alpha(), 0,
		StartExpeditionTestFixture.receipt(), null
	)
	assert_false(command.is_concrete())


func test_apply_to_rejects_exhausted_run_serial_with_zero_profile_mutation() -> void:
	# U64Bits.add() wraps silently, so a maxed next_run_serial would make the new
	# run reuse the profile's very first run_id / run_seed. Same SERIAL_EXHAUSTED
	# convention the rest of the project's serial bumps follow.
	var profile := StartExpeditionTestFixture.base_profile(
		5, [StartExpeditionTestFixture.COMMANDER_ALPHA_ID], []
	)
	profile.next_run_serial = U64Bits.max_value()
	var command := StartExpeditionCommand.new(
		StartExpeditionTestFixture.COMMANDER_ALPHA_ID,
		StartExpeditionTestFixture.commander_alpha(), 0,
		StartExpeditionTestFixture.receipt(), StartExpeditionTestFixture.catalog()
	)

	var result := command.apply_to(profile)

	assert_false(result.ok)
	assert_eq(result.error.code, StartExpeditionError.SERIAL_EXHAUSTED)
	assert_eq(result.error.field_path, &"profile.next_run_serial")
	assert_eq(profile.next_run_serial.to_hex(), U64Bits.max_value().to_hex())
	assert_null(profile.last_selection)


func test_apply_to_rejects_locked_commander_with_zero_profile_mutation() -> void:
	var unlocked: Array[StringName] = [
		StartExpeditionTestFixture.COMMANDER_BETA_ID, StartExpeditionTestFixture.COMMANDER_GAMMA_ID,
	]
	var profile := StartExpeditionTestFixture.base_profile(5, unlocked)
	var before_serial := profile.next_run_serial.to_hex()
	var command := StartExpeditionCommand.new(
		StartExpeditionTestFixture.COMMANDER_ALPHA_ID,
		StartExpeditionTestFixture.commander_alpha(), 0,
		StartExpeditionTestFixture.receipt(), StartExpeditionTestFixture.catalog()
	)

	var result := command.apply_to(profile)

	assert_false(result.ok)
	assert_eq(result.error.code, StartExpeditionError.EXPEDITION_COMMANDER_LOCKED)
	assert_eq(profile.next_run_serial.to_hex(), before_serial)
	assert_null(profile.last_selection)


func test_apply_to_rejects_challenge_prerequisite_unmet_with_zero_profile_mutation() -> void:
	var records: Array[CommanderChallengeRecordState] = [
		StartExpeditionTestFixture.challenge_record(StartExpeditionTestFixture.COMMANDER_ALPHA_ID, 0),
	]
	var profile := StartExpeditionTestFixture.base_profile(
		5, [StartExpeditionTestFixture.COMMANDER_ALPHA_ID], records
	)
	var before_serial := profile.next_run_serial.to_hex()
	var command := StartExpeditionCommand.new(
		StartExpeditionTestFixture.COMMANDER_ALPHA_ID,
		StartExpeditionTestFixture.commander_alpha(), 2,
		StartExpeditionTestFixture.receipt(), StartExpeditionTestFixture.catalog()
	)

	var result := command.apply_to(profile)

	assert_false(result.ok)
	assert_eq(result.error.code, StartExpeditionError.EXPEDITION_CHALLENGE_PREREQUISITE_UNMET)
	assert_eq(profile.next_run_serial.to_hex(), before_serial)
	assert_null(profile.last_selection)


func test_apply_to_allows_challenge_level_zero_with_no_records_at_all() -> void:
	var profile := StartExpeditionTestFixture.base_profile(
		5, [StartExpeditionTestFixture.COMMANDER_ALPHA_ID], []
	)
	var command := StartExpeditionCommand.new(
		StartExpeditionTestFixture.COMMANDER_ALPHA_ID,
		StartExpeditionTestFixture.commander_alpha(), 0,
		StartExpeditionTestFixture.receipt(), StartExpeditionTestFixture.catalog()
	)

	var result := command.apply_to(profile)

	assert_true(result.ok)
	if not result.ok:
		return
	assert_eq(result.run.challenge_level, 0)


func test_apply_to_allows_challenge_level_at_exact_prerequisite_boundary() -> void:
	var records: Array[CommanderChallengeRecordState] = [
		StartExpeditionTestFixture.challenge_record(StartExpeditionTestFixture.COMMANDER_ALPHA_ID, 1),
	]
	var profile := StartExpeditionTestFixture.base_profile(
		5, [StartExpeditionTestFixture.COMMANDER_ALPHA_ID], records
	)
	var command := StartExpeditionCommand.new(
		StartExpeditionTestFixture.COMMANDER_ALPHA_ID,
		StartExpeditionTestFixture.commander_alpha(), 2,
		StartExpeditionTestFixture.receipt(), StartExpeditionTestFixture.catalog()
	)

	var result := command.apply_to(profile)

	assert_true(result.ok, "highest_cleared_level 1 must satisfy challenge_level 2's prerequisite (>= level-1)")


func test_apply_to_success_bumps_next_run_serial_and_sets_last_selection() -> void:
	var profile := StartExpeditionTestFixture.base_profile(
		5, [StartExpeditionTestFixture.COMMANDER_ALPHA_ID], []
	)
	var original_serial := profile.next_run_serial.to_hex()
	var command := StartExpeditionCommand.new(
		StartExpeditionTestFixture.COMMANDER_ALPHA_ID,
		StartExpeditionTestFixture.commander_alpha(), 0,
		StartExpeditionTestFixture.receipt(), StartExpeditionTestFixture.catalog()
	)

	var result := command.apply_to(profile)

	assert_true(result.ok)
	if not result.ok:
		return
	assert_eq(result.profile.next_run_serial.to_hex(), U64Bits.from_u32(0, 6).value.to_hex())
	assert_not_null(result.profile.last_selection)
	assert_eq(result.profile.last_selection.commander_id, StartExpeditionTestFixture.COMMANDER_ALPHA_ID)
	assert_eq(result.profile.last_selection.challenge_level, 0)
	assert_eq(result.run.commander_id, StartExpeditionTestFixture.COMMANDER_ALPHA_ID)
	# the caller's original profile argument must be untouched (never the same instance).
	assert_eq(profile.next_run_serial.to_hex(), original_serial)
	assert_null(profile.last_selection)
	assert_ne(result.profile, profile)
