extends GutTest

const FIXTURE_ROOT := "res://tests/fixtures/save/content_production"
const FIXTURES: Array[String] = [
	"5ddf80a",
	"9362e7d",
	"5e78ccf",
]


func test_three_historical_schema_three_codec_two_fixtures_migrate_exactly_once() -> void:
	for fixture_name: String in FIXTURES:
		var fixture_path := "%s/%s.schema3.codec2.json" % [FIXTURE_ROOT, fixture_name]
		var hash_path := "%s/%s.sha256" % [FIXTURE_ROOT, fixture_name]
		assert_true(FileAccess.file_exists(fixture_path), "missing fixture: %s" % fixture_path)
		assert_true(FileAccess.file_exists(hash_path), "missing fixture hash: %s" % hash_path)
		if not FileAccess.file_exists(fixture_path) or not FileAccess.file_exists(hash_path):
			continue
		var raw := _read_text(fixture_path)
		var expected_hash := _read_text(hash_path).strip_edges().split(" ")[0]
		assert_eq(FileAccess.get_sha256(fixture_path), expected_hash)
		var source: Dictionary = JSON.parse_string(raw)
		assert_eq(source.get("schema_version"), 3)
		assert_false(source.run.has("node_choice_receipts"))
		assert_false(source.run.content_snapshot.has("catalog_schema_version"))
		assert_false(source.run.content_snapshot.has("content_codec_version"))
		var registry := _registry_for(source)
		var migrated := registry.migrate(raw)
		assert_true(migrated.ok, "%s must migrate" % fixture_name)
		assert_eq(migrated.run_status, LoadResult.RunStatus.LOADED)
		assert_not_null(migrated.root)
		if migrated.root == null:
			continue
		assert_eq(migrated.root.schema_version, 4)
		assert_eq(migrated.root.run.content_snapshot.catalog_schema_version, 2)
		assert_eq(migrated.root.run.content_snapshot.content_codec_version, 3)
		assert_true(migrated.migration_receipt is ContentGenerationMigrationReceiptV2)
		var repeated := registry.migrate(migrated.canonical_json_text.value)
		assert_true(repeated.ok)
		assert_eq(repeated.canonical_json_text.value, migrated.canonical_json_text.value)
		assert_eq(raw, _read_text(fixture_path), "source fixture bytes must remain unchanged")


func test_unsafe_historical_active_state_is_preserved_byte_for_byte() -> void:
	var fixture_path := "%s/5e78ccf.schema3.codec2.json" % FIXTURE_ROOT
	assert_true(FileAccess.file_exists(fixture_path))
	if not FileAccess.file_exists(fixture_path):
		return
	var source: Dictionary = JSON.parse_string(_read_text(fixture_path))
	source.run.run_phase = "PREPARE"
	var unsafe := JSON.stringify(source)
	var migrated := _registry_for(source).migrate(unsafe)
	assert_true(migrated.ok)
	assert_eq(migrated.run_status, LoadResult.RunStatus.INCOMPATIBLE_PRESERVED)
	assert_null(migrated.root)
	assert_eq(migrated.canonical_json_text.value, unsafe)


func _registry_for(source: Dictionary) -> SaveMigrationRegistry:
	var snapshot: Dictionary = source.run.content_snapshot
	var active_ids := _names(snapshot.enabled_content_ids)
	var target_digest := ("target-codec3|" + str(snapshot.manifest_digest)).sha256_text()
	var target := PinnedCatalogBuildReceipt.new(
		2,
		3,
		"0.2.0-content-production",
		("selection|" + str(snapshot.manifest_digest)).sha256_text(),
		active_ids,
		StringName(snapshot.economy_config_id),
		&"config.combat_default",
		_names(snapshot.reward_table_ids),
		_names(snapshot.map_node_def_ids),
		_names(snapshot.challenge_unlock_def_ids),
		StringName(snapshot.meta_reward_table_id),
		target_digest
	)
	var migration_codec := ContentGenerationMigrationCodecV2.new()
	var pack := ContentGenerationMigrationPackV2.new()
	pack.source_content_version = str(snapshot.content_version)
	pack.target_content_version = target.content_version
	pack.source_manifest_digest = str(snapshot.manifest_digest)
	pack.expected_target_manifest_digest = target_digest
	pack.mapping_digest = migration_codec.mapping_digest([])
	pack.localization_catalog_digest = migration_codec.localization_digest([])
	pack.pack_digest = migration_codec.pack_digest(pack)
	var allowlist: Array[ContentGenerationMigrationAllowlistEntryV2] = [
		ContentGenerationMigrationAllowlistEntryV2.new(
			pack.source_content_version,
			pack.source_manifest_digest,
			pack.pack_digest
		),
	]
	var port := ContentGenerationMigrationPortV2.new(
		[pack],
		allowlist,
		{target_digest: target}
	)
	var save_codec := SaveJsonCodec.new(
		FakePinnedCatalogReceiptPort.new(target),
		FakeContentIdMigrationPort.new()
	)
	return SaveMigrationRegistry.new(save_codec, port)


func _names(values: Array) -> Array[StringName]:
	var result: Array[StringName] = []
	for value: Variant in values:
		result.append(StringName(value))
	return result


func _read_text(path: String) -> String:
	var handle := FileAccess.open(path, FileAccess.READ)
	return handle.get_as_text() if handle != null else ""
