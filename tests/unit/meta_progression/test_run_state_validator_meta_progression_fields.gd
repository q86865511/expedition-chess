extends GutTest

## T03 (specs/meta-progression/tasks.md AC: "validator 驗新欄型別與 records 唯一性"):
## RunStateValidator must validate the type/shape of the three new fields and
## enforce commander_challenge_records uniqueness. Field-path assumptions follow
## this validator's established "parent.field_name" convention used throughout
## run_state_validator.gd (e.g. &"profile.settings_ref", &"run.income_claimed_node_ids");
## the canonical-ascending-order assumption for commander_challenge_records and
## discovered_content_ids mirrors every other array field validated in this file
## (unlocked_content_ids/discovered_content_ids/settlement_receipts all use
## strict sorted+unique checks, never uniqueness alone).

func test_profile_validates_with_null_last_selection() -> void:
	var profile := SaveRootFixture.create_valid_root().profile
	profile.last_selection = null
	assert_true(RunStateValidator.new().validate_profile(profile).ok)


func test_profile_validates_with_well_formed_last_selection() -> void:
	var profile := SaveRootFixture.create_valid_root().profile
	profile.last_selection = ProfileLastSelectionState.new(&"commander.fixture", 3)
	assert_true(RunStateValidator.new().validate_profile(profile).ok)


func test_profile_rejects_last_selection_with_non_stable_commander_id() -> void:
	var profile := SaveRootFixture.create_valid_root().profile
	profile.last_selection = ProfileLastSelectionState.new(&"NOT-A-STABLE-ID", 0)
	var result := RunStateValidator.new().validate_profile(profile)
	assert_false(result.ok)
	assert_eq(result.error.field_path, &"profile.last_selection")


func test_profile_rejects_last_selection_with_negative_challenge_level() -> void:
	var profile := SaveRootFixture.create_valid_root().profile
	profile.last_selection = ProfileLastSelectionState.new(&"commander.fixture", -1)
	var result := RunStateValidator.new().validate_profile(profile)
	assert_false(result.ok)
	assert_eq(result.error.field_path, &"profile.last_selection")


func test_profile_validates_with_empty_commander_challenge_records() -> void:
	var profile := SaveRootFixture.create_valid_root().profile
	var empty: Array[CommanderChallengeRecordState] = []
	profile.commander_challenge_records = empty
	assert_true(RunStateValidator.new().validate_profile(profile).ok)


func test_profile_validates_with_sorted_unique_commander_challenge_records() -> void:
	var profile := SaveRootFixture.create_valid_root().profile
	profile.commander_challenge_records = [
		CommanderChallengeRecordState.new(&"commander.alpha", 1),
		CommanderChallengeRecordState.new(&"commander.beta", 3),
	]
	assert_true(RunStateValidator.new().validate_profile(profile).ok)


func test_profile_rejects_commander_challenge_records_with_duplicate_commander_id() -> void:
	var profile := SaveRootFixture.create_valid_root().profile
	profile.commander_challenge_records = [
		CommanderChallengeRecordState.new(&"commander.alpha", 1),
		CommanderChallengeRecordState.new(&"commander.alpha", 2),
	]
	var result := RunStateValidator.new().validate_profile(profile)
	assert_false(result.ok, "duplicate commander_id must be rejected (T03 AC: records uniqueness)")
	assert_eq(result.error.field_path, &"profile.commander_challenge_records")


func test_profile_rejects_commander_challenge_records_out_of_canonical_order() -> void:
	var profile := SaveRootFixture.create_valid_root().profile
	profile.commander_challenge_records = [
		CommanderChallengeRecordState.new(&"commander.beta", 3),
		CommanderChallengeRecordState.new(&"commander.alpha", 1),
	]
	var result := RunStateValidator.new().validate_profile(profile)
	assert_false(result.ok)
	assert_eq(result.error.field_path, &"profile.commander_challenge_records")


func test_profile_rejects_commander_challenge_record_with_non_stable_commander_id() -> void:
	var profile := SaveRootFixture.create_valid_root().profile
	profile.commander_challenge_records = [
		CommanderChallengeRecordState.new(&"NOT-A-STABLE-ID", 1),
	]
	var result := RunStateValidator.new().validate_profile(profile)
	assert_false(result.ok)
	assert_eq(result.error.field_path, &"profile.commander_challenge_records")


func test_profile_rejects_commander_challenge_record_with_negative_highest_cleared_level() -> void:
	var profile := SaveRootFixture.create_valid_root().profile
	profile.commander_challenge_records = [
		CommanderChallengeRecordState.new(&"commander.fixture", -1),
	]
	var result := RunStateValidator.new().validate_profile(profile)
	assert_false(result.ok)
	assert_eq(result.error.field_path, &"profile.commander_challenge_records")


func test_run_validates_with_empty_discovered_content_ids() -> void:
	var run := SaveRootFixture.create_valid_root().run
	var empty: Array[StringName] = []
	run.discovered_content_ids = empty
	assert_true(RunStateValidator.new().validate_run(run).ok)


func test_run_validates_with_sorted_unique_discovered_content_ids() -> void:
	var run := SaveRootFixture.create_valid_root().run
	run.discovered_content_ids = [&"relic.fixture", &"unit.fixture"]
	assert_true(RunStateValidator.new().validate_run(run).ok)


func test_run_rejects_duplicate_discovered_content_ids() -> void:
	var run := SaveRootFixture.create_valid_root().run
	run.discovered_content_ids = [&"unit.fixture", &"unit.fixture"]
	var result := RunStateValidator.new().validate_run(run)
	assert_false(result.ok)
	assert_eq(result.error.field_path, &"run.discovered_content_ids")


func test_run_rejects_discovered_content_ids_out_of_canonical_order() -> void:
	var run := SaveRootFixture.create_valid_root().run
	run.discovered_content_ids = [&"unit.fixture", &"relic.fixture"]
	var result := RunStateValidator.new().validate_run(run)
	assert_false(result.ok)
	assert_eq(result.error.field_path, &"run.discovered_content_ids")


func test_run_rejects_non_stable_discovered_content_id() -> void:
	var run := SaveRootFixture.create_valid_root().run
	run.discovered_content_ids = [&"NOT-A-STABLE-ID"]
	var result := RunStateValidator.new().validate_run(run)
	assert_false(result.ok)
	assert_eq(result.error.field_path, &"run.discovered_content_ids")
