extends GutTest

## Phase E P0-1：設施共用投影只讀 ProfileState 既有欄位，且建構與每次
## accessor 都切斷可變物件／陣列的引用。


func test_facility_bundle_exposes_all_ea_ready_fields_from_one_snapshot() -> void:
	var profile := _profile_fixture()
	var bundle := CampFacilityBundle.new(profile)

	assert_eq(bundle.workshop_currency(), 37)
	assert_eq(bundle.highest_challenge_level(), 6)
	assert_eq(bundle.commander_ids(), [&"commander.alpha"])
	assert_eq(bundle.unlocked_ids(), [
		&"commander.alpha",
		&"unit.slice_player_00",
		&"relic.test_charm",
	])
	assert_eq(bundle.discovered_ids(), [&"unit.slice_player_01"])
	var selection := bundle.expedition_last_selection()
	assert_not_null(selection)
	if selection != null:
		assert_eq(selection.commander_id, &"commander.alpha")
		assert_eq(selection.challenge_level, 3)
	var records := bundle.challenge_records()
	assert_eq(records.size(), 1)
	if not records.is_empty():
		assert_eq(records[0].commander_id, &"commander.alpha")
		assert_eq(records[0].highest_cleared_level, 4)


func test_facility_bundle_never_leaks_live_profile_or_return_value_references() -> void:
	var profile := _profile_fixture()
	var bundle := CampFacilityBundle.new(profile)
	var digest := bundle.projection_digest()

	profile.meta_currency = 999
	profile.unlocked_content_ids.append(&"unit.injected")
	profile.last_selection.challenge_level = 99
	profile.commander_challenge_records[0].highest_cleared_level = 99
	var returned_ids := bundle.unlocked_ids()
	returned_ids.append(&"unit.returned_mutation")
	var returned_selection := bundle.expedition_last_selection()
	returned_selection.challenge_level = 88
	var returned_records := bundle.challenge_records()
	returned_records[0].highest_cleared_level = 88

	assert_eq(bundle.projection_digest(), digest)
	assert_eq(bundle.workshop_currency(), 37)
	assert_eq(bundle.unlocked_ids(), [
		&"commander.alpha",
		&"unit.slice_player_00",
		&"relic.test_charm",
	])
	assert_eq(bundle.expedition_last_selection().challenge_level, 3)
	assert_eq(bundle.challenge_records()[0].highest_cleared_level, 4)


func _profile_fixture() -> ProfileState:
	var unlocked: Array[StringName] = [
		&"commander.alpha",
		&"unit.slice_player_00",
		&"relic.test_charm",
	]
	var discovered: Array[StringName] = [&"unit.slice_player_01"]
	var receipts: Array[SettlementReceiptState] = []
	var records: Array[CommanderChallengeRecordState] = [
		CommanderChallengeRecordState.new(&"commander.alpha", 4),
	]
	return ProfileState.new(
		"profile.ea_ready",
		U64Bits.one(),
		37,
		unlocked,
		discovered,
		6,
		receipts,
		&"settings.default",
		ProfileLastSelectionState.new(&"commander.alpha", 3),
		records
	)
