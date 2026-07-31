extends GutTest

## B4 回歸:codec 2→3 的 allowlist pack 與 port 必須 fail-closed。
##
## 每個 negative case 都以「攻擊者自己重算 mapping/pack digest 並自己簽 allowlist」
## 的最強姿態建構(_port_for 一律由被測 pack 推導 allowlist),因此測到的是語意約束
## 本身,而不是 digest 對不上這種弱保護。

const SOURCE_VERSION := "legacy.2"
const SOURCE_MANIFEST := "a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1"
const TARGET_VERSION := "production.3"
const TARGET_MANIFEST := "b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2"
const COMBAT_DIGEST := "1111111111111111111111111111111111111111111111111111111111111111"
const ECONOMY_DIGEST := "2222222222222222222222222222222222222222222222222222222222222222"
const META_DIGEST := "3333333333333333333333333333333333333333333333333333333333333333"
const UNIT_DIGEST := "4444444444444444444444444444444444444444444444444444444444444444"


func test_reference_without_mapping_is_rejected_instead_of_identity_assumed() -> void:
	var mappings := _mappings()
	mappings.remove_at(mappings.size() - 1)  # 移除 unit.old 的 mapping
	var pack := _pack_for(mappings, _localization_digest())
	var result := _port_for(pack).migrate_generation(_request())
	assert_false(result.ok, "缺 mapping 的引用不得被當成 identity 放行")
	if result.ok:
		return
	assert_eq(result.error.code, ContentGenerationMigrationError.MAPPING_INVALID)


func test_empty_mapping_pack_is_rejected_even_when_allowlisted() -> void:
	var no_mappings: Array[ContentGenerationMigrationEntryV2] = []
	var pack := _pack_for(no_mappings, _localization_digest())
	var result := _port_for(pack).migrate_generation(_request())
	assert_false(result.ok, "空 mappings 的 pack 不得簽出 CGR2")
	if result.ok:
		return
	assert_eq(result.error.code, ContentGenerationMigrationError.MAPPING_INVALID)


func test_identity_mapping_must_keep_the_same_id() -> void:
	var mappings := _mappings()
	mappings[0] = _entry(
		"combat_config", "config.combat_default",
		ContentGenerationMigrationEntryV2.Requirement.REQUIRED,
		ContentGenerationMigrationEntryV2.MappingKind.IDENTITY,
		"config.combat_other", COMBAT_DIGEST
	)
	var result := _port_for(
		_pack_for(mappings, _localization_digest())
	).migrate_generation(_request())
	assert_false(result.ok, "IDENTITY 不得改 id")
	if result.ok:
		return
	assert_eq(result.error.code, ContentGenerationMigrationError.MAPPING_INVALID)


func test_alias_mapping_must_change_the_id() -> void:
	var mappings := _mappings()
	mappings[1] = _entry(
		"economy_config", "economy.old",
		ContentGenerationMigrationEntryV2.Requirement.REQUIRED,
		ContentGenerationMigrationEntryV2.MappingKind.ALIAS,
		"economy.old", ECONOMY_DIGEST
	)
	var result := _port_for(
		_pack_for(mappings, _localization_digest())
	).migrate_generation(_request())
	assert_false(result.ok, "ALIAS 的 target 不得與 source 同 id")
	if result.ok:
		return
	assert_eq(result.error.code, ContentGenerationMigrationError.MAPPING_INVALID)


func test_target_entry_digest_must_match_installed_entry() -> void:
	var mappings := _mappings()
	mappings[4] = _entry(
		"unit", "unit.old",
		ContentGenerationMigrationEntryV2.Requirement.REQUIRED,
		ContentGenerationMigrationEntryV2.MappingKind.ALIAS,
		"unit.new", COMBAT_DIGEST
	)
	var result := _port_for(
		_pack_for(mappings, _localization_digest())
	).migrate_generation(_request())
	assert_false(result.ok, "target entry digest 必須對上安裝中的 entry")
	if result.ok:
		return
	assert_eq(result.error.code, ContentGenerationMigrationError.TARGET_MISMATCH)


func test_mapping_category_must_match_installed_target_entry() -> void:
	var mappings := _mappings()
	mappings[4] = _entry(
		"unit", "unit.old",
		ContentGenerationMigrationEntryV2.Requirement.REQUIRED,
		ContentGenerationMigrationEntryV2.MappingKind.ALIAS,
		"economy.new", ECONOMY_DIGEST
	)
	var result := _port_for(
		_pack_for(mappings, _localization_digest())
	).migrate_generation(_request())
	assert_false(result.ok, "category 不符的 target 必須拒絕")
	if result.ok:
		return
	assert_eq(result.error.code, ContentGenerationMigrationError.MAPPING_INVALID)


func test_localization_digest_must_match_installed_catalog() -> void:
	var pack := _pack_for(_mappings(), _foreign_localization_digest())
	var result := _port_for(pack).migrate_generation(_request())
	assert_false(result.ok, "L10N2 digest 必須綁定安裝中的 catalog bytes")
	if result.ok:
		return
	assert_eq(result.error.code, ContentGenerationMigrationError.PACK_INVALID)


func test_structural_reference_cannot_be_tombstoned() -> void:
	var mappings := _mappings()
	mappings[4] = _entry(
		"unit", "unit.old",
		ContentGenerationMigrationEntryV2.Requirement.OPTIONAL,
		ContentGenerationMigrationEntryV2.MappingKind.TOMBSTONE,
		"", ""
	)
	var result := _port_for(
		_pack_for(mappings, _localization_digest())
	).migrate_generation(_request())
	assert_false(result.ok, "active run 引用的 id 不得 TOMBSTONE")
	if result.ok:
		return
	assert_eq(
		result.error.code,
		ContentGenerationMigrationError.SELECTION_INCOMPATIBLE
	)


func test_request_without_traversed_references_is_rejected() -> void:
	var request := _request()
	request.referenced_entries.clear()
	var result := _port_for(
		_pack_for(_mappings(), _localization_digest())
	).migrate_generation(request)
	assert_false(result.ok, "沒有 traverse run state 的請求不得放行")
	if result.ok:
		return
	assert_eq(result.error.code, ContentGenerationMigrationError.CONFIG_INVALID)


func test_fully_declared_pack_migrates_and_signs_receipt() -> void:
	var pack := _pack_for(_mappings(), _localization_digest())
	var result := _port_for(pack).migrate_generation(_request())
	assert_true(result.ok, "完整宣告的 pack 必須可以升級")
	if not result.ok:
		return
	assert_eq(result.target_receipt.manifest_digest, TARGET_MANIFEST)
	assert_eq(result.migration_receipt.from_codec, 2)
	assert_eq(result.migration_receipt.to_codec, 3)
	assert_eq(
		result.migration_receipt.receipt_digest,
		ContentGenerationMigrationCodecV2.new().receipt_digest(
			result.migration_receipt
		)
	)


func _mappings() -> Array[ContentGenerationMigrationEntryV2]:
	var required := ContentGenerationMigrationEntryV2.Requirement.REQUIRED
	var optional := ContentGenerationMigrationEntryV2.Requirement.OPTIONAL
	var identity := ContentGenerationMigrationEntryV2.MappingKind.IDENTITY
	var alias := ContentGenerationMigrationEntryV2.MappingKind.ALIAS
	var tombstone := ContentGenerationMigrationEntryV2.MappingKind.TOMBSTONE
	var result: Array[ContentGenerationMigrationEntryV2] = [
		_entry(
			"combat_config", "config.combat_default", required, identity,
			"config.combat_default", COMBAT_DIGEST
		),
		_entry(
			"economy_config", "economy.old", required, alias,
			"economy.new", ECONOMY_DIGEST
		),
		_entry(
			"meta_reward_table", "meta.old", required, alias,
			"meta.new", META_DIGEST
		),
		_entry("relic", "relic.old", optional, tombstone, "", ""),
		_entry("unit", "unit.old", required, alias, "unit.new", UNIT_DIGEST),
	]
	return result


func _entry(
	category: String,
	source_id: String,
	requirement: int,
	mapping_kind: int,
	target_id: String,
	target_entry_digest: String
) -> ContentGenerationMigrationEntryV2:
	return ContentGenerationMigrationEntryV2.new(
		category,
		source_id,
		requirement,
		mapping_kind,
		not target_id.is_empty(),
		target_id,
		target_entry_digest
	)


func _pack_for(
	mappings: Array[ContentGenerationMigrationEntryV2],
	localization_digest: String
) -> ContentGenerationMigrationPackV2:
	var codec := ContentGenerationMigrationCodecV2.new()
	var pack := ContentGenerationMigrationPackV2.new()
	pack.source_content_version = SOURCE_VERSION
	pack.target_content_version = TARGET_VERSION
	pack.source_manifest_digest = SOURCE_MANIFEST
	pack.expected_target_manifest_digest = TARGET_MANIFEST
	pack.mappings = mappings
	pack.mapping_digest = codec.mapping_digest(mappings)
	pack.localization_catalog_digest = localization_digest
	pack.pack_digest = codec.pack_digest(pack)
	return pack


## allowlist 由被測 pack 自身推導:模擬「攻擊者能自簽 allowlist」的最壞情況。
func _port_for(
	pack: ContentGenerationMigrationPackV2
) -> ContentGenerationMigrationPortV2:
	var packs: Array[ContentGenerationMigrationPackV2] = [pack]
	var allowlist: Array[ContentGenerationMigrationAllowlistEntryV2] = [
		ContentGenerationMigrationAllowlistEntryV2.new(
			pack.source_content_version,
			pack.source_manifest_digest,
			pack.pack_digest
		),
	]
	return ContentGenerationMigrationPortV2.new(
		packs,
		allowlist,
		{TARGET_MANIFEST: _target_receipt()},
		{TARGET_MANIFEST: _target_entries()},
		{TARGET_MANIFEST: _localization_digest()}
	)


func _target_receipt() -> PinnedCatalogBuildReceipt:
	var active_ids: Array[StringName] = [
		&"config.combat_default", &"economy.new", &"meta.new", &"unit.new",
	]
	var empty: Array[StringName] = []
	return PinnedCatalogBuildReceipt.new(
		2,
		3,
		TARGET_VERSION,
		"c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3",
		active_ids,
		&"economy.new",
		&"config.combat_default",
		empty,
		empty,
		empty,
		&"meta.new",
		TARGET_MANIFEST
	)


func _target_entries() -> Array[ContentGenerationMigrationTargetEntry]:
	var result: Array[ContentGenerationMigrationTargetEntry] = [
		ContentGenerationMigrationTargetEntry.new(
			&"combat_config", &"config.combat_default", COMBAT_DIGEST
		),
		ContentGenerationMigrationTargetEntry.new(
			&"economy_config", &"economy.new", ECONOMY_DIGEST
		),
		ContentGenerationMigrationTargetEntry.new(
			&"meta_reward_table", &"meta.new", META_DIGEST
		),
		ContentGenerationMigrationTargetEntry.new(
			&"unit", &"unit.new", UNIT_DIGEST
		),
	]
	return result


func _localization_digest() -> String:
	return ContentGenerationMigrationCodecV2.new().localization_digest(
		_localization_rows("介面", "UI")
	)


func _foreign_localization_digest() -> String:
	return ContentGenerationMigrationCodecV2.new().localization_digest(
		_localization_rows("介面(竄改)", "UI (tampered)")
	)


func _localization_rows(zh: String, en: String) -> Array[PackedStringArray]:
	var row := PackedStringArray()
	row.append("ui.title")
	row.append(zh)
	row.append(en)
	var rows: Array[PackedStringArray] = [row]
	return rows


func _request() -> ContentGenerationMigrationRequest:
	var enabled: Array[StringName] = [
		&"config.combat_default", &"economy.old", &"meta.old", &"relic.old",
		&"unit.old",
	]
	var empty: Array[StringName] = []
	var references: Array[ContentGenerationMigrationReference] = [
		ContentGenerationMigrationReference.new(
			&"economy_config", &"economy.old",
			&"run.content_snapshot.economy_config_id", true
		),
		ContentGenerationMigrationReference.new(
			&"combat_config", &"config.combat_default",
			&"run.content_snapshot.combat_config_id", true
		),
		ContentGenerationMigrationReference.new(
			&"meta_reward_table", &"meta.old",
			&"run.content_snapshot.meta_reward_table_id", true
		),
		ContentGenerationMigrationReference.new(
			&"unit", &"unit.old",
			&"run.roster_state.unit_instances.def_id", true
		),
	]
	return ContentGenerationMigrationRequest.new(
		SOURCE_VERSION,
		SOURCE_MANIFEST,
		enabled,
		&"economy.old",
		empty,
		empty,
		empty,
		&"meta.old",
		1,
		2,
		references
	)
