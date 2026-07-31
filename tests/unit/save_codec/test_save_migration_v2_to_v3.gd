extends GutTest

## T03 (specs/meta-progression/tasks.md; design.md SS2/SS10): a new v2->v3
## SaveMigration must upgrade schema-2 saves, defaulting the three new fields
## (profile.last_selection=null, profile.commander_challenge_records=[],
## run.discovered_content_ids=[]) while preserving every pre-existing value.
## tests/fixtures/save/schema_v2_fixture.gd is the frozen schema-2 fixture
## (REQ-SAVE-003) this suite migrates from.

func test_schema_two_fixture_is_frozen_pre_meta_progression_shape() -> void:
	# Guards the golden fixture itself so this suite provably exercises an
	# old-schema input rather than a coincidentally-current one.
	assert_true(SchemaV2Fixture.JSON_TEXT.begins_with("{\"schema_version\":2,"))
	assert_false(SchemaV2Fixture.JSON_TEXT.contains("last_selection"))
	assert_false(SchemaV2Fixture.JSON_TEXT.contains("commander_challenge_records"))
	assert_true(SchemaV2Fixture.JSON_TEXT_PROFILE_ONLY.begins_with("{\"schema_version\":2,"))
	assert_true(SchemaV2Fixture.JSON_TEXT_PROFILE_ONLY.ends_with("\"run\":null}"))


func test_schema_two_migrates_to_three_with_defaulted_new_fields() -> void:
	var registry := SaveMigrationRegistry.new(SaveRootFixture.create_codec())
	var migrated := registry.migrate(SchemaV2Fixture.JSON_TEXT)
	assert_true(migrated.ok)
	if not migrated.ok:
		return
	assert_not_null(migrated.root)
	if migrated.root == null:
		return
	assert_eq(migrated.root.schema_version, 4)
	assert_eq(migrated.target_schema_version, 4)
	assert_null(migrated.root.profile.last_selection)
	assert_true(migrated.root.profile.commander_challenge_records.is_empty())
	assert_not_null(migrated.root.run)
	if migrated.root.run != null:
		assert_true(migrated.root.run.discovered_content_ids.is_empty())


func test_schema_two_migration_preserves_existing_profile_and_run_data() -> void:
	var registry := SaveMigrationRegistry.new(SaveRootFixture.create_codec())
	var migrated := registry.migrate(SchemaV2Fixture.JSON_TEXT)
	assert_true(migrated.ok)
	if not migrated.ok or migrated.root == null:
		return
	assert_eq(migrated.root.profile.profile_id, SchemaV2Fixture.PROFILE_ID)
	assert_eq(migrated.root.profile.meta_currency, 0)
	var expected_unlocked: Array[StringName] = [SchemaV2Fixture.COMMANDER_ID]
	assert_eq(migrated.root.profile.unlocked_content_ids, expected_unlocked)
	assert_eq(migrated.root.profile.settings_ref, &"settings.default")
	assert_not_null(migrated.root.run)
	if migrated.root.run == null:
		return
	assert_eq(migrated.root.run.run_id, SchemaV2Fixture.RUN_ID)
	assert_eq(migrated.root.run.commander_id, SchemaV2Fixture.COMMANDER_ID)
	assert_eq(migrated.root.run.expedition_hp, 100)


func test_schema_two_profile_only_migrates_with_null_run_and_defaulted_profile_fields() -> void:
	var registry := SaveMigrationRegistry.new(SaveRootFixture.create_codec())
	var migrated := registry.migrate(SchemaV2Fixture.JSON_TEXT_PROFILE_ONLY)
	assert_true(migrated.ok)
	if not migrated.ok or migrated.root == null:
		return
	assert_eq(migrated.root.schema_version, 4)
	assert_null(migrated.root.run)
	assert_null(migrated.root.profile.last_selection)
	assert_true(migrated.root.profile.commander_challenge_records.is_empty())
	assert_eq(migrated.root.profile.profile_id, SchemaV2Fixture.PROFILE_ID)


func test_schema_two_migration_is_idempotent() -> void:
	var codec := SaveRootFixture.create_codec()
	var registry := SaveMigrationRegistry.new(codec)
	var migrated := registry.migrate(SchemaV2Fixture.JSON_TEXT)
	assert_true(migrated.ok)
	if not migrated.ok:
		return
	var second := registry.migrate(migrated.canonical_json_text.value)
	assert_true(second.ok)
	if not second.ok:
		return
	assert_eq(second.canonical_json_text.value, migrated.canonical_json_text.value)


func test_schema_two_migrated_root_passes_current_validator() -> void:
	# The migration's whole point is to produce a v3 root that is valid under
	# today's (post-bump) RunStateValidator, not merely parseable.
	var registry := SaveMigrationRegistry.new(SaveRootFixture.create_codec())
	var migrated := registry.migrate(SchemaV2Fixture.JSON_TEXT)
	assert_true(migrated.ok)
	if not migrated.ok or migrated.root == null:
		return
	assert_true(RunStateValidator.new().validate_root(migrated.root).ok)
