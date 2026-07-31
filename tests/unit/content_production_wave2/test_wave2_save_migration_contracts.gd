extends GutTest

const REQUIRED_SCRIPTS: Array[String] = [
	"res://domain/run/node_choice_pending_state.gd",
	"res://domain/run/node_choice_commit_receipt_state.gd",
	"res://domain/run/node_choice_receipt_ledger_entry.gd",
	"res://services/save/migration/content_generation_migration_entry_v2.gd",
	"res://services/save/migration/content_generation_migration_pack_v2.gd",
	"res://services/save/migration/content_generation_migration_codec_v2.gd",
]


func test_save_schema_four_and_wave2_public_types_exist() -> void:
	assert_eq(SaveSchemaContract.CURRENT, 4)
	for path: String in REQUIRED_SCRIPTS:
		assert_true(FileAccess.file_exists(path), "missing Wave 2 script: %s" % path)


func test_content_snapshot_persists_catalog_and_codec_versions() -> void:
	var receipt := PinnedCatalogBuildReceipt.new(
		2,
		3,
		"production.1",
		"a".repeat(64),
		[
			&"config.combat_default",
			&"economy.default",
			&"meta_reward.default",
			&"reward_table.default",
			&"map_node.normal",
			&"unlock.challenge_0",
		],
		&"economy.default",
		&"config.combat_default",
		[&"reward_table.default"],
		[&"map_node.normal"],
		[&"unlock.challenge_0"],
		&"meta_reward.default",
		"b".repeat(64)
	)
	var built := ContentSnapshotState.from_pinned_receipt(receipt)
	assert_true(built.ok)
	if not built.ok:
		return
	assert_eq(built.snapshot.call("catalog_schema_version_value"), 2)
	assert_eq(built.snapshot.call("content_codec_version_value"), 3)
	var clone: Variant = built.snapshot.deep_clone()
	assert_true(built.snapshot.canonical_equals(clone))
	clone.set("_content_codec_version", 2)
	assert_false(built.snapshot.canonical_equals(clone))


func test_node_choice_pending_digest_is_canonical_clone_isolated_and_tamper_sensitive() -> void:
	var script := _required_script(
		"res://domain/run/node_choice_pending_state.gd"
	)
	if script == null:
		return
	var pending: Variant = script.new(
		StringName("node_" + "a".repeat(64)),
		&"choice_set.event_01",
		[&"choice.a", &"choice.b"],
		"production.1",
		2,
		3,
		"a".repeat(64),
		"0000000000000001"
	)
	assert_true(pending.call("is_valid"))
	assert_eq(String(pending.pending_digest).length(), 64)
	var clone: Variant = pending.deep_clone()
	clone.choice_ids[0] = &"choice.changed"
	assert_ne(clone.choice_ids, pending.choice_ids)
	assert_false(clone.call("is_valid"), "tampered choices must invalidate digest")


func test_cgm2_normative_golden_vectors_are_exact() -> void:
	var entry_script := _required_script(
		"res://services/save/migration/content_generation_migration_entry_v2.gd"
	)
	var codec_script := _required_script(
		"res://services/save/migration/content_generation_migration_codec_v2.gd"
	)
	if entry_script == null or codec_script == null:
		return
	var target_digest := PackedByteArray()
	for value: int in range(32):
		target_digest.append(value)
	var entry: Variant = entry_script.new(
		"unit",
		"unit.old",
		1,
		2,
		true,
		"unit.new",
		target_digest.hex_encode()
	)
	var codec: Variant = codec_script.new()
	assert_eq(
		codec.call("encode_entry", entry).hex_encode(),
		"434d523200000004756e697400000008756e69742e6f6c640000000100000002"
		+ "0100000008756e69742e6e6577000102030405060708090a0b0c0d0e0f101112"
		+ "131415161718191a1b1c1d1e1f"
	)
	var entries: Array[ContentGenerationMigrationEntryV2] = [entry]
	assert_eq(
		codec.call("mapping_digest", entries),
		"8ef8d3ebd6de4cb7b14caf68c3afbcf44c008440431e091c6d4593523b576a2b"
	)
	var no_rows: Array[PackedStringArray] = []
	assert_eq(
		codec.call("localization_digest", no_rows),
		"b97c9b707aadfc40186db9d5d9b6c30f98aff38f9e61b00ef414759428838d50"
	)


func _required_script(path: String) -> Script:
	if not FileAccess.file_exists(path):
		fail_test("missing Wave 2 script: %s" % path)
		return null
	var script := load(path) as Script
	assert_not_null(script, "could not load Wave 2 script: %s" % path)
	return script
