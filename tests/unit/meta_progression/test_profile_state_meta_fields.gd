extends GutTest

## T03 (specs/meta-progression/tasks.md; design.md SS10): every existing state
## DTO in domain/run/ carries a deep_clone() that is a true independent copy
## (the codebase's copy-validate-save-swap transaction pattern in
## RunController/CampController depends on this -- see CLAUDE.md architecture
## conventions). This suite pins the same contract for the two new DTOs
## (ProfileLastSelectionState, CommanderChallengeRecordState) and for the
## extended deep_clone() on ProfileState/RunState that now must carry them.

func test_profile_last_selection_state_deep_clone_is_independent_copy() -> void:
	var original := ProfileLastSelectionState.new(&"commander.fixture", 2)
	var clone := original.deep_clone()
	assert_eq(clone.commander_id, &"commander.fixture")
	assert_eq(clone.challenge_level, 2)
	clone.challenge_level = 5
	assert_eq(original.challenge_level, 2, "deep_clone must not alias the source instance")


func test_commander_challenge_record_state_deep_clone_is_independent_copy() -> void:
	var original := CommanderChallengeRecordState.new(&"commander.fixture", 1)
	var clone := original.deep_clone()
	assert_eq(clone.commander_id, &"commander.fixture")
	assert_eq(clone.highest_cleared_level, 1)
	clone.highest_cleared_level = 4
	assert_eq(original.highest_cleared_level, 1, "deep_clone must not alias the source instance")


func test_profile_state_deep_clone_copies_last_selection_as_independent_instance() -> void:
	var profile := SaveRootFixture.create_valid_root().profile
	profile.last_selection = ProfileLastSelectionState.new(&"commander.fixture", 2)
	var clone := profile.deep_clone()
	assert_not_null(clone.last_selection)
	if clone.last_selection == null:
		return
	assert_eq(clone.last_selection.commander_id, &"commander.fixture")
	assert_eq(clone.last_selection.challenge_level, 2)
	clone.last_selection.challenge_level = 9
	assert_eq(
		profile.last_selection.challenge_level, 2,
		"ProfileState.deep_clone must deep-clone last_selection, not alias it"
	)


func test_profile_state_deep_clone_handles_null_last_selection() -> void:
	var profile := SaveRootFixture.create_valid_root().profile
	profile.last_selection = null
	var clone := profile.deep_clone()
	assert_null(clone.last_selection)


func test_profile_state_deep_clone_copies_commander_challenge_records_as_independent_list() -> void:
	var profile := SaveRootFixture.create_valid_root().profile
	var records: Array[CommanderChallengeRecordState] = [
		CommanderChallengeRecordState.new(&"commander.fixture", 2),
	]
	profile.commander_challenge_records = records
	var clone := profile.deep_clone()
	assert_eq(clone.commander_challenge_records.size(), 1)
	if clone.commander_challenge_records.size() != 1:
		return
	clone.commander_challenge_records[0].highest_cleared_level = 9
	assert_eq(
		profile.commander_challenge_records[0].highest_cleared_level, 2,
		"ProfileState.deep_clone must deep-clone each record, not alias the list elements"
	)
	clone.commander_challenge_records.append(
		CommanderChallengeRecordState.new(&"commander.other", 1)
	)
	assert_eq(
		profile.commander_challenge_records.size(), 1,
		"ProfileState.deep_clone must copy the array itself, not alias the backing Array"
	)


func test_run_state_deep_clone_copies_discovered_content_ids_as_independent_array() -> void:
	var run := SaveRootFixture.create_valid_root().run
	var ids: Array[StringName] = [&"unit.fixture"]
	run.discovered_content_ids = ids
	var clone := run.deep_clone()
	assert_eq(clone.discovered_content_ids, ids)
	clone.discovered_content_ids.append(&"relic.fixture")
	assert_eq(
		run.discovered_content_ids.size(), 1,
		"RunState.deep_clone must copy discovered_content_ids by value, not alias the backing Array"
	)
