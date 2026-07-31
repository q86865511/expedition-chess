extends GutTest

const PORT_SCRIPT := (
	"res://services/save/migration/content_generation_migration_port_v2.gd"
)


func test_codec_two_source_migrates_only_to_exact_allowlisted_codec_three_receipt() -> void:
	assert_true(FileAccess.file_exists(PORT_SCRIPT), "missing codec 2→3 migration port")
	if not FileAccess.file_exists(PORT_SCRIPT):
		return
	var port_script := load(PORT_SCRIPT) as Script
	assert_not_null(port_script)
	if port_script == null:
		return
	var target_digest := "b".repeat(64)
	var entry := ContentGenerationMigrationEntryV2.new(
		"unit",
		"unit.old",
		ContentGenerationMigrationEntryV2.Requirement.REQUIRED,
		ContentGenerationMigrationEntryV2.MappingKind.ALIAS,
		true,
		"unit.new",
		"c".repeat(64)
	)
	var codec := ContentGenerationMigrationCodecV2.new()
	var pack := ContentGenerationMigrationPackV2.new()
	pack.source_content_version = "legacy.2"
	pack.target_content_version = "production.3"
	pack.source_manifest_digest = "a".repeat(64)
	pack.expected_target_manifest_digest = target_digest
	pack.mappings = [entry]
	pack.mapping_digest = codec.mapping_digest(pack.mappings)
	pack.localization_catalog_digest = codec.localization_digest([])
	pack.pack_digest = codec.pack_digest(pack)
	var allowlist: Array[ContentGenerationMigrationAllowlistEntryV2] = [
		ContentGenerationMigrationAllowlistEntryV2.new(
			pack.source_content_version,
			pack.source_manifest_digest,
			pack.pack_digest
		),
	]
	var target := PinnedCatalogBuildReceipt.new(
		2,
		3,
		pack.target_content_version,
		"d".repeat(64),
		[
			&"config.combat_default",
			&"economy.default",
			&"map_node.normal",
			&"meta_reward.default",
			&"reward_table.default",
			&"unit.new",
			&"unlock.challenge_0",
		],
		&"economy.default",
		&"config.combat_default",
		[&"reward_table.default"],
		[&"map_node.normal"],
		[&"unlock.challenge_0"],
		&"meta_reward.default",
		target_digest
	)
	var receipts := {target_digest: target}
	var port: Variant = port_script.new([pack], allowlist, receipts)
	var request := ContentGenerationMigrationRequest.new(
		pack.source_content_version,
		pack.source_manifest_digest,
		[
			&"config.combat_default",
			&"economy.default",
			&"map_node.normal",
			&"meta_reward.default",
			&"reward_table.default",
			&"unit.old",
			&"unlock.challenge_0",
		],
		&"economy.default",
		[&"reward_table.default"],
		[&"map_node.normal"],
		[&"unlock.challenge_0"],
		&"meta_reward.default"
	)
	request.set("source_catalog_schema_version", 1)
	request.set("source_content_codec_version", 2)
	var migrated: Variant = port.call("migrate_generation", request)
	assert_true(migrated.ok)
	if migrated.ok:
		assert_eq(migrated.target_receipt.manifest_digest, target_digest)
		assert_eq(migrated.target_receipt.content_codec_version, 3)
		assert_eq(migrated.migration_receipt.from_codec, 2)
		assert_eq(migrated.migration_receipt.to_codec, 3)
		assert_eq(
			migrated.migration_receipt.receipt_digest,
			codec.receipt_digest(migrated.migration_receipt)
		)

	pack.expected_target_manifest_digest = "e".repeat(64)
	var rejected: Variant = port.call("migrate_generation", request)
	assert_false(rejected.ok, "tampered pack must fail closed")


func test_missing_or_ambiguous_allowlist_pack_is_rejected() -> void:
	assert_true(FileAccess.file_exists(PORT_SCRIPT), "missing codec 2→3 migration port")
	if not FileAccess.file_exists(PORT_SCRIPT):
		return
	var port_script := load(PORT_SCRIPT) as Script
	if port_script == null:
		return
	var request := ContentGenerationMigrationRequest.new(
		"legacy.2",
		"a".repeat(64),
		[],
		&"economy.default",
		[],
		[],
		[],
		&"meta_reward.default"
	)
	request.set("source_catalog_schema_version", 1)
	request.set("source_content_codec_version", 2)
	var empty_port: Variant = port_script.new([], [], {})
	var missing: Variant = empty_port.call("migrate_generation", request)
	assert_false(missing.ok)
	assert_eq(
		missing.error.code,
		ContentGenerationMigrationError.PACK_MISSING
	)
