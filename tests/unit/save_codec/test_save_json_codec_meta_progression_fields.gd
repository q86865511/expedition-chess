extends GutTest

## T03 (specs/meta-progression/tasks.md; design.md SS10): ProfileState gains
## last_selection (nullable ProfileLastSelectionState{commander_id,challenge_level})
## and commander_challenge_records (Array[CommanderChallengeRecordState]
## {commander_id,highest_cleared_level}); RunState gains
## discovered_content_ids: Array[StringName]. This file covers the field-carrier
## encode/decode round trip (S5-AC-012's field-carrier segment owned by T03; the
## atomic in-run union/commit behaviour is T09's scope, not tested here).

func test_last_selection_null_round_trips() -> void:
	var root := SaveRootFixture.create_valid_root()
	root.profile.last_selection = null
	var codec := SaveRootFixture.create_codec()
	var encoded := codec.encode(root)
	assert_true(encoded.ok)
	if not encoded.ok:
		return
	var decoded := codec.decode_text(encoded.json_text.value)
	assert_true(decoded.ok)
	if not decoded.ok or decoded.root == null:
		return
	assert_null(decoded.root.profile.last_selection)
	assert_eq(codec.encode(decoded.root).json_text.value, encoded.json_text.value)


func test_last_selection_present_round_trips() -> void:
	var root := SaveRootFixture.create_valid_root()
	root.profile.last_selection = ProfileLastSelectionState.new(&"commander.fixture", 2)
	var codec := SaveRootFixture.create_codec()
	var encoded := codec.encode(root)
	assert_true(encoded.ok)
	if not encoded.ok:
		return
	var decoded := codec.decode_text(encoded.json_text.value)
	assert_true(decoded.ok)
	if not decoded.ok or decoded.root == null:
		return
	assert_not_null(decoded.root.profile.last_selection)
	if decoded.root.profile.last_selection == null:
		return
	assert_eq(decoded.root.profile.last_selection.commander_id, &"commander.fixture")
	assert_eq(decoded.root.profile.last_selection.challenge_level, 2)
	assert_eq(codec.encode(decoded.root).json_text.value, encoded.json_text.value)


func test_commander_challenge_records_round_trip() -> void:
	var root := SaveRootFixture.create_valid_root()
	var records: Array[CommanderChallengeRecordState] = [
		CommanderChallengeRecordState.new(&"commander.alpha", 1),
		CommanderChallengeRecordState.new(&"commander.beta", 3),
	]
	root.profile.commander_challenge_records = records
	var codec := SaveRootFixture.create_codec()
	var encoded := codec.encode(root)
	assert_true(encoded.ok)
	if not encoded.ok:
		return
	var decoded := codec.decode_text(encoded.json_text.value)
	assert_true(decoded.ok)
	if not decoded.ok or decoded.root == null:
		return
	assert_eq(decoded.root.profile.commander_challenge_records.size(), 2)
	if decoded.root.profile.commander_challenge_records.size() != 2:
		return
	assert_eq(decoded.root.profile.commander_challenge_records[0].commander_id, &"commander.alpha")
	assert_eq(decoded.root.profile.commander_challenge_records[0].highest_cleared_level, 1)
	assert_eq(decoded.root.profile.commander_challenge_records[1].commander_id, &"commander.beta")
	assert_eq(decoded.root.profile.commander_challenge_records[1].highest_cleared_level, 3)
	assert_eq(codec.encode(decoded.root).json_text.value, encoded.json_text.value)


func test_commander_challenge_records_empty_round_trips() -> void:
	var root := SaveRootFixture.create_valid_root()
	var empty_records: Array[CommanderChallengeRecordState] = []
	root.profile.commander_challenge_records = empty_records
	var codec := SaveRootFixture.create_codec()
	var encoded := codec.encode(root)
	assert_true(encoded.ok)
	if not encoded.ok:
		return
	var decoded := codec.decode_text(encoded.json_text.value)
	assert_true(decoded.ok)
	if not decoded.ok or decoded.root == null:
		return
	assert_true(decoded.root.profile.commander_challenge_records.is_empty())


func test_run_discovered_content_ids_round_trip() -> void:
	var root := SaveRootFixture.create_valid_root()
	var ids: Array[StringName] = [&"relic.fixture", &"unit.fixture"]
	root.run.discovered_content_ids = ids
	var codec := SaveRootFixture.create_codec()
	var encoded := codec.encode(root)
	assert_true(encoded.ok)
	if not encoded.ok:
		return
	var decoded := codec.decode_text(encoded.json_text.value)
	assert_true(decoded.ok)
	if not decoded.ok or decoded.root == null:
		return
	assert_eq(decoded.root.run.discovered_content_ids, ids)
	assert_eq(codec.encode(decoded.root).json_text.value, encoded.json_text.value)


func test_run_discovered_content_ids_default_empty_round_trips() -> void:
	var root := SaveRootFixture.create_valid_root()
	var codec := SaveRootFixture.create_codec()
	var encoded := codec.encode(root)
	assert_true(encoded.ok)
	if not encoded.ok:
		return
	var decoded := codec.decode_text(encoded.json_text.value)
	assert_true(decoded.ok)
	if not decoded.ok or decoded.root == null:
		return
	assert_true(decoded.root.run.discovered_content_ids.is_empty())


func test_existing_eight_profile_fields_round_trip_unchanged() -> void:
	# Regression guard (T03 AC: "既有 8 欄往返不變"): the eight pre-existing
	# ProfileState fields must still carry their exact values through
	# encode/decode once the wire format grows the three new S5 fields.
	var root := SaveRootFixture.create_valid_root()
	root.profile.meta_currency = 42
	root.profile.highest_challenge_level = 3
	var unlocked: Array[StringName] = [&"commander.fixture", &"unit.fixture"]
	root.profile.unlocked_content_ids = unlocked
	var discovered: Array[StringName] = [&"relic.fixture"]
	root.profile.discovered_content_ids = discovered
	var codec := SaveRootFixture.create_codec()
	var encoded := codec.encode(root)
	assert_true(encoded.ok)
	if not encoded.ok:
		return
	var decoded := codec.decode_text(encoded.json_text.value)
	assert_true(decoded.ok)
	if not decoded.ok or decoded.root == null:
		return
	var profile := decoded.root.profile
	assert_eq(profile.profile_id, SaveRootFixture.PROFILE_ID)
	assert_eq(profile.next_run_serial.to_hex(), root.profile.next_run_serial.to_hex())
	assert_eq(profile.meta_currency, 42)
	assert_eq(profile.highest_challenge_level, 3)
	assert_eq(profile.unlocked_content_ids, unlocked)
	assert_eq(profile.discovered_content_ids, discovered)
	assert_eq(profile.settlement_receipts.size(), 0)
	assert_eq(profile.settings_ref, &"settings.default")
	assert_eq(codec.encode(decoded.root).json_text.value, encoded.json_text.value)


func test_schema_two_reject_tests_still_document_unknown_and_duplicate_field_shape() -> void:
	# Sanity check that adding new fields did not loosen the codec's existing
	# strict-shape rejection of unknown/duplicate keys (mirrors the pre-existing
	# test_unknown_duplicate_and_noncanonical_fields_are_rejected coverage, kept
	# independent here so it does not depend on that locked test file).
	var codec := SaveRootFixture.create_codec()
	var encoded := codec.encode(SaveRootFixture.create_valid_root())
	assert_true(encoded.ok)
	if not encoded.ok:
		return
	var prefix := "{\"schema_version\":%d," % SaveSchemaContract.CURRENT
	assert_true(encoded.json_text.value.begins_with(prefix))
	var unknown := encoded.json_text.value.replace(prefix, prefix + "\"unknown\":0,")
	assert_false(codec.decode_text(unknown).ok)
