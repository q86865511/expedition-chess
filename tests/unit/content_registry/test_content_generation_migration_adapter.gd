extends GutTest

var _fixtures: Array[ContentGenerationMigrationTestFixture] = []

func after_each() -> void:
	for fixture: ContentGenerationMigrationTestFixture in _fixtures:
		fixture.dispose()
	_fixtures.clear()

func test_valid_v1_to_v2_publishes_pinned_non_latest_generation() -> void:
	var fixture := _fixture()
	assert_eq(fixture.build_error, "")
	var count_before := fixture.registry._generation_count()
	var result := fixture.adapter_for().migrate_generation(fixture.request)
	assert_true(result.ok, _error_text(result))
	assert_not_null(result.target_receipt)
	assert_eq(result.target_receipt.manifest_digest, fixture.expected_target_digest)
	assert_eq(result.target_receipt.content_codec_version, 2)
	assert_eq(fixture.registry._generation_count(), count_before + 1)
	assert_eq(
		fixture.registry.latest_catalog_handle().value.manifest_digest,
		fixture.latest_digest_before_migration
	)
	var config := fixture.registry.resolve(ContentRef.new(
		fixture.expected_target_digest, &"config.combat_default"
	))
	assert_true(config.ok)

func test_alias_selection_migrates_to_active_identity() -> void:
	var fixture := _fixture()
	var result := fixture.adapter_for().migrate_generation(fixture.alias_request())
	assert_true(result.ok, _error_text(result))
	assert_true(result.target_receipt.active_entry_ids.has(&"unit.player_00"))
	assert_false(result.target_receipt.active_entry_ids.has(&"unit.legacy_player"))

func test_required_tombstone_is_incompatible_and_publishes_nothing() -> void:
	var fixture := _fixture()
	var before := fixture.registry._state_fingerprint()
	var result := fixture.adapter_for().migrate_generation(fixture.tombstone_request())
	assert_false(result.ok)
	assert_eq(result.error.code, ContentGenerationMigrationError.SELECTION_INCOMPATIBLE)
	assert_eq(fixture.registry._state_fingerprint(), before)

func test_missing_legacy_generation_fails_without_publish() -> void:
	var fixture := _fixture(false)
	var before := fixture.registry._state_fingerprint()
	var result := fixture.adapter_for().migrate_generation(fixture.request)
	assert_false(result.ok)
	assert_eq(result.error.code, ContentGenerationMigrationError.SOURCE_GENERATION_MISSING)
	assert_eq(fixture.registry._state_fingerprint(), before)

func test_ambiguous_pack_fails_before_catalog_mutation() -> void:
	var fixture := _fixture()
	var packs: Array[ContentGenerationMigrationPackV1] = [
		fixture.pack.deep_clone(), fixture.pack.deep_clone()
	]
	var adapter := ContentGenerationMigrationAdapter.new(
		fixture.registry, packs, fixture.allowlist
	)
	var before := fixture.registry._state_fingerprint()
	var result := adapter.migrate_generation(fixture.request)
	assert_false(result.ok)
	assert_eq(result.error.code, ContentGenerationMigrationError.PACK_AMBIGUOUS)
	assert_eq(fixture.registry._state_fingerprint(), before)

func test_invalid_combat_config_is_rejected_atomically() -> void:
	var fixture := _fixture()
	var corrupt := PackedByteArray([0x00])
	var pack := fixture.make_pack(fixture.boss_mapping, corrupt)
	_assert_failure_without_publish(
		fixture,
		fixture.adapter_for(pack).migrate_generation(fixture.request),
		ContentGenerationMigrationError.CONFIG_INVALID
	)

func test_invalid_boss_source_mapping_is_rejected_atomically() -> void:
	var fixture := _fixture()
	var mapping: Array[BossSourceMigrationEntryV1] = []
	for entry: BossSourceMigrationEntryV1 in fixture.boss_mapping:
		mapping.append(entry.deep_clone())
	assert_gt(mapping.size(), 0)
	mapping[0].source_spawn_key = &"missing_spawn"
	var pack := fixture.make_pack(mapping, fixture.config_entry_bytes)
	_assert_failure_without_publish(
		fixture,
		fixture.adapter_for(pack).migrate_generation(fixture.request),
		ContentGenerationMigrationError.MAPPING_INVALID
	)

func test_target_digest_mismatch_is_rejected_atomically() -> void:
	var fixture := _fixture()
	var pack := fixture.make_pack(
		fixture.boss_mapping,
		fixture.config_entry_bytes,
		"0000000000000000000000000000000000000000000000000000000000000000"
	)
	_assert_failure_without_publish(
		fixture,
		fixture.adapter_for(pack).migrate_generation(fixture.request),
		ContentGenerationMigrationError.TARGET_MISMATCH
	)

func _fixture(register_legacy: bool = true) -> ContentGenerationMigrationTestFixture:
	var fixture := ContentGenerationMigrationTestFixture.new(register_legacy, true)
	_fixtures.append(fixture)
	return fixture

func _assert_failure_without_publish(
	fixture: ContentGenerationMigrationTestFixture,
	result: ContentGenerationMigrationResult,
	expected_code: StringName
) -> void:
	var before_latest := fixture.latest_digest_before_migration
	assert_false(result.ok)
	assert_not_null(result.error)
	assert_eq(result.error.code, expected_code)
	assert_eq(
		fixture.registry.latest_catalog_handle().value.manifest_digest,
		before_latest
	)
	assert_false(fixture.registry.catalog_handle(fixture.expected_target_digest).ok)

func _error_text(result: ContentGenerationMigrationResult) -> String:
	if result == null or result.error == null:
		return "unknown migration failure"
	return "%s at %s" % [String(result.error.code), String(result.error.field_path)]
