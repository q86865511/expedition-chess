extends GutTest

const PORT_SCRIPT := (
	"res://services/save/migration/content_generation_migration_port_v2.gd"
)

var TARGET_DIGEST := "b".repeat(64)
var SOURCE_DIGEST := "a".repeat(64)


func test_codec_two_source_migrates_only_to_exact_allowlisted_codec_three_receipt() -> void:
	assert_true(FileAccess.file_exists(PORT_SCRIPT), "missing codec 2→3 migration port")
	if not FileAccess.file_exists(PORT_SCRIPT):
		return
	var port_script := load(PORT_SCRIPT) as Script
	assert_not_null(port_script)
	if port_script == null:
		return
	var codec := ContentGenerationMigrationCodecV2.new()
	var target_entries := _target_entries()
	var localization_digest := codec.localization_digest(_localization_rows())
	var pack := ContentGenerationMigrationPackV2.new()
	pack.source_content_version = "legacy.2"
	pack.target_content_version = "production.3"
	pack.source_manifest_digest = SOURCE_DIGEST
	pack.expected_target_manifest_digest = TARGET_DIGEST
	pack.mappings = _mappings(target_entries)
	pack.mapping_digest = codec.mapping_digest(pack.mappings)
	pack.localization_catalog_digest = localization_digest
	pack.pack_digest = codec.pack_digest(pack)
	var allowlist: Array[ContentGenerationMigrationAllowlistEntryV2] = [
		ContentGenerationMigrationAllowlistEntryV2.new(
			pack.source_content_version,
			pack.source_manifest_digest,
			pack.pack_digest
		),
	]
	var target := _target_receipt(pack.target_content_version)
	var port: Variant = port_script.new(
		[pack],
		allowlist,
		{TARGET_DIGEST: target},
		{TARGET_DIGEST: target_entries},
		{TARGET_DIGEST: localization_digest}
	)
	var request := _request()
	var migrated: Variant = port.call("migrate_generation", request)
	assert_true(migrated.ok)
	if migrated.ok:
		assert_eq(migrated.target_receipt.manifest_digest, TARGET_DIGEST)
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
	var empty: Array[StringName] = []
	var request := ContentGenerationMigrationRequest.new(
		"legacy.2",
		SOURCE_DIGEST,
		empty,
		&"economy.default",
		empty,
		empty,
		empty,
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


## Exact allowlist 的語意是「來源世代的每一個 content id 都必須逐筆宣告」,
## 因此 pack 必須覆蓋 request 的全部引用面,而不是只宣告會改名的那一筆。
func _mappings(
	target_entries: Array[ContentGenerationMigrationTargetEntry]
) -> Array[ContentGenerationMigrationEntryV2]:
	var digests: Dictionary = {}
	for entry: ContentGenerationMigrationTargetEntry in target_entries:
		digests[entry.content_id] = entry.entry_digest
	var required := ContentGenerationMigrationEntryV2.Requirement.REQUIRED
	var identity := ContentGenerationMigrationEntryV2.MappingKind.IDENTITY
	var alias := ContentGenerationMigrationEntryV2.MappingKind.ALIAS
	var result: Array[ContentGenerationMigrationEntryV2] = [
		ContentGenerationMigrationEntryV2.new(
			"combat_config", "config.combat_default", required, identity,
			true, "config.combat_default", digests[&"config.combat_default"]
		),
		ContentGenerationMigrationEntryV2.new(
			"economy_config", "economy.default", required, identity,
			true, "economy.default", digests[&"economy.default"]
		),
		ContentGenerationMigrationEntryV2.new(
			"map_node", "map_node.normal", required, identity,
			true, "map_node.normal", digests[&"map_node.normal"]
		),
		ContentGenerationMigrationEntryV2.new(
			"meta_reward_table", "meta_reward.default", required, identity,
			true, "meta_reward.default", digests[&"meta_reward.default"]
		),
		ContentGenerationMigrationEntryV2.new(
			"reward_table", "reward_table.default", required, identity,
			true, "reward_table.default", digests[&"reward_table.default"]
		),
		ContentGenerationMigrationEntryV2.new(
			"unit", "unit.old", required, alias,
			true, "unit.new", digests[&"unit.new"]
		),
		ContentGenerationMigrationEntryV2.new(
			"unlock", "unlock.challenge_0", required, identity,
			true, "unlock.challenge_0", digests[&"unlock.challenge_0"]
		),
	]
	return result


func _target_entries() -> Array[ContentGenerationMigrationTargetEntry]:
	var result: Array[ContentGenerationMigrationTargetEntry] = [
		ContentGenerationMigrationTargetEntry.new(
			&"combat_config", &"config.combat_default", "1".repeat(64)
		),
		ContentGenerationMigrationTargetEntry.new(
			&"economy_config", &"economy.default", "2".repeat(64)
		),
		ContentGenerationMigrationTargetEntry.new(
			&"map_node", &"map_node.normal", "3".repeat(64)
		),
		ContentGenerationMigrationTargetEntry.new(
			&"meta_reward_table", &"meta_reward.default", "4".repeat(64)
		),
		ContentGenerationMigrationTargetEntry.new(
			&"reward_table", &"reward_table.default", "5".repeat(64)
		),
		ContentGenerationMigrationTargetEntry.new(
			&"unit", &"unit.new", "6".repeat(64)
		),
		ContentGenerationMigrationTargetEntry.new(
			&"unlock", &"unlock.challenge_0", "7".repeat(64)
		),
	]
	return result


func _target_receipt(content_version: String) -> PinnedCatalogBuildReceipt:
	var active_ids: Array[StringName] = [
		&"config.combat_default",
		&"economy.default",
		&"map_node.normal",
		&"meta_reward.default",
		&"reward_table.default",
		&"unit.new",
		&"unlock.challenge_0",
	]
	var reward_tables: Array[StringName] = [&"reward_table.default"]
	var map_nodes: Array[StringName] = [&"map_node.normal"]
	var challenges: Array[StringName] = [&"unlock.challenge_0"]
	return PinnedCatalogBuildReceipt.new(
		2,
		3,
		content_version,
		"d".repeat(64),
		active_ids,
		&"economy.default",
		&"config.combat_default",
		reward_tables,
		map_nodes,
		challenges,
		&"meta_reward.default",
		TARGET_DIGEST
	)


func _request() -> ContentGenerationMigrationRequest:
	var enabled: Array[StringName] = [
		&"config.combat_default",
		&"economy.default",
		&"map_node.normal",
		&"meta_reward.default",
		&"reward_table.default",
		&"unit.old",
		&"unlock.challenge_0",
	]
	var reward_tables: Array[StringName] = [&"reward_table.default"]
	var map_nodes: Array[StringName] = [&"map_node.normal"]
	var challenges: Array[StringName] = [&"unlock.challenge_0"]
	var references: Array[ContentGenerationMigrationReference] = [
		ContentGenerationMigrationReference.new(
			&"economy_config", &"economy.default",
			&"run.content_snapshot.economy_config_id", true
		),
		ContentGenerationMigrationReference.new(
			&"combat_config", &"config.combat_default",
			&"run.content_snapshot.combat_config_id", true
		),
		ContentGenerationMigrationReference.new(
			&"meta_reward_table", &"meta_reward.default",
			&"run.content_snapshot.meta_reward_table_id", true
		),
		ContentGenerationMigrationReference.new(
			&"reward_table", &"reward_table.default",
			&"run.content_snapshot.reward_table_ids", true
		),
		ContentGenerationMigrationReference.new(
			&"map_node", &"map_node.normal",
			&"run.content_snapshot.map_node_def_ids", true
		),
		ContentGenerationMigrationReference.new(
			&"unlock", &"unlock.challenge_0",
			&"run.content_snapshot.challenge_unlock_def_ids", true
		),
		ContentGenerationMigrationReference.new(
			&"unit", &"unit.old",
			&"run.roster_state.unit_instances.def_id", true
		),
	]
	var request := ContentGenerationMigrationRequest.new(
		"legacy.2",
		SOURCE_DIGEST,
		enabled,
		&"economy.default",
		reward_tables,
		map_nodes,
		challenges,
		&"meta_reward.default",
		1,
		2,
		references
	)
	return request


func _localization_rows() -> Array[PackedStringArray]:
	var row := PackedStringArray()
	row.append("loc.unit_new")
	row.append("新單位")
	row.append("New Unit")
	var rows: Array[PackedStringArray] = [row]
	return rows
