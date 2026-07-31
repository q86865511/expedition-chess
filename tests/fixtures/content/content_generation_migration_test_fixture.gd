class_name ContentGenerationMigrationTestFixture
extends RefCounted

const SOURCE_VERSION := "fixture.legacy.1"
const TARGET_VERSION := "fixture.migrated.2"

var registry := ContentRegistryService.new()
var source_snapshot: ContentCatalogSnapshot
var source_catalog_bytes := PackedByteArray()
var request: ContentGenerationMigrationRequest
var boss_mapping: Array[BossSourceMigrationEntryV1] = []
var config_entry_bytes := PackedByteArray()
var expected_target_digest: String
var pack: ContentGenerationMigrationPackV1
var allowlist: Array[ContentGenerationMigrationAllowlistEntry] = []
var latest_digest_before_migration: String
var build_error: String

func _init(
	register_legacy: bool = true,
	install_latest: bool = true
) -> void:
	_build(register_legacy, install_latest)

func dispose() -> void:
	if registry != null:
		registry.free()
		registry = null

func adapter_for(
	value: ContentGenerationMigrationPackV1 = null
) -> ContentGenerationMigrationAdapter:
	var packs: Array[ContentGenerationMigrationPackV1] = []
	packs.append(value if value != null else pack)
	return ContentGenerationMigrationAdapter.new(registry, packs, allowlist_for(packs[0]))

func allowlist_for(
	value: ContentGenerationMigrationPackV1
) -> Array[ContentGenerationMigrationAllowlistEntry]:
	return [ContentGenerationMigrationAllowlistEntry.new(
		value.source_content_version,
		value.source_manifest_digest,
		value.pack_digest
	)]

func make_pack(
	mapping: Array[BossSourceMigrationEntryV1],
	config_bytes: PackedByteArray,
	target_digest: String = ""
) -> ContentGenerationMigrationPackV1:
	var codec := ContentGenerationMigrationCodec.new()
	var content_codec := ContentCanonicalCodecV2.new()
	var resolved_target := target_digest \
		if not target_digest.is_empty() else expected_target_digest
	var result := ContentGenerationMigrationPackV1.new(
		SOURCE_VERSION,
		source_snapshot.manifest_digest,
		TARGET_VERSION,
		resolved_target,
		config_bytes,
		content_codec.sha256_bytes(config_bytes).hex_encode(),
		mapping,
		codec.boss_mapping_digest(mapping),
		1,
		2,
		""
	)
	result.pack_digest = codec.pack_digest(result)
	return result

func alias_request() -> ContentGenerationMigrationRequest:
	var result := request.deep_clone()
	var index := result.enabled_content_ids.find(&"unit.player_00")
	if index >= 0:
		result.enabled_content_ids[index] = &"unit.legacy_player"
	result.enabled_content_ids.sort_custom(_name_less)
	return result

func tombstone_request() -> ContentGenerationMigrationRequest:
	var result := request.deep_clone()
	var index := result.enabled_content_ids.find(&"unit.player_00")
	if index >= 0:
		result.enabled_content_ids[index] = &"unit.removed_player"
	result.enabled_content_ids.sort_custom(_name_less)
	return result

func _build(register_legacy: bool, install_latest: bool) -> void:
	var input := SyntheticContentFixture.build_valid()
	input.aliases = [ContentAliasValue.new(
		&"unit.legacy_player", &"unit.player_00"
	)]
	input.tombstones = [ContentTombstoneValue.new(
		&"unit.removed_player",
		&"unit",
		&"incompatible_required",
		&"",
		false,
		&"removed"
	)]
	if install_latest:
		var installed := registry.install_validated(
			input,
			"fixture.latest.9",
			[&"pack.synthetic"]
		)
		if not installed.ok:
			build_error = "latest install failed"
			return
		latest_digest_before_migration = installed.handle.manifest_digest
	source_snapshot = _build_legacy_catalog(input)
	if source_snapshot == null:
		return
	source_catalog_bytes = source_snapshot.diagnostic_catalog_bytes.duplicate()
	request = _request_for(source_snapshot)
	boss_mapping = _mapping_for(input)
	config_entry_bytes = _config_bytes(input)
	if config_entry_bytes.is_empty():
		return
	var transcoded := ContentGenerationMigrationTranscoder.new().build(
		source_snapshot,
		request,
		TARGET_VERSION,
		config_entry_bytes,
		boss_mapping
	)
	if not transcoded.ok:
		build_error = "target transcode failed: %s" % String(
			transcoded.error.code if transcoded.error != null else &"unknown"
		)
		return
	expected_target_digest = transcoded.snapshot.manifest_digest
	pack = make_pack(boss_mapping, config_entry_bytes)
	allowlist = allowlist_for(pack)
	if register_legacy:
		var registered := registry.register_legacy_v1_generation(
			source_catalog_bytes
		)
		if not registered.ok:
			build_error = "legacy registration failed"

func _build_legacy_catalog(
	input: ContentValidationInput
) -> ContentCatalogSnapshot:
	var codec := ContentCanonicalCodecV1.new()
	var compiler := ContentDefinitionCompiler.new()
	var entries: Array[ContentEntryValue] = []
	for definition: ContentDefinition in input.definitions:
		# CombatConfigDef／UnitPresentationDef 是 v3-only 類別，codec-v1 compiler
		# 沒有對應的 payload 規則（_compile_specifics 落到空陣列），legacy catalog 一律跳過。
		if definition is CombatConfigDef or definition is UnitPresentationDef:
			continue
		# Unit/Effect 的來源 resource 已升級為 schema_version=2，v1 compiler 只收 1；
		# 用副本降版餵給 compiler，不可就地改動原 input（同一份 input 先被 install_validated 用過）。
		var legacy_definition: ContentDefinition = definition
		if definition is UnitDef or definition is EffectDef:
			legacy_definition = definition.duplicate() as ContentDefinition
			legacy_definition.schema_version = 1
		var compiled := compiler.compile(legacy_definition)
		if not compiled.ok:
			build_error = "legacy entry compile failed: %s" % String(definition.id)
			return null
		entries.append(compiled.entry)
	entries.sort_custom(_entry_less)
	var entry_bytes: Array[PackedByteArray] = []
	var indexes: Array[ContentEntryIndexValue] = []
	for entry: ContentEntryValue in entries:
		var encoded := codec.encode_entry(entry)
		if not encoded.ok:
			build_error = "legacy entry encode failed: %s" % String(entry.content_id)
			return null
		entry_bytes.append(encoded.canonical_bytes)
		indexes.append(ContentEntryIndexValue.new(
			entry.category,
			entry.content_id,
			entry.resource_schema_version,
			codec.sha256_bytes(encoded.canonical_bytes)
		))
	var manifest := ContentManifestValue.new()
	manifest.catalog_schema_version = 1
	manifest.content_version = SOURCE_VERSION
	manifest.pack_ids = [&"pack.synthetic"]
	for alias: ContentAliasValue in input.aliases:
		manifest.aliases.append(alias.deep_clone())
	for tombstone: ContentTombstoneValue in input.tombstones:
		manifest.tombstones.append(tombstone.deep_clone())
	manifest.entry_indexes = indexes
	var encoded_manifest := codec.encode_manifest(manifest)
	if not encoded_manifest.ok:
		build_error = "legacy manifest encode failed"
		return null
	var digest := codec.sha256_bytes(encoded_manifest.canonical_bytes)
	var encoded_catalog := codec.encode_catalog(
		digest,
		encoded_manifest.canonical_bytes,
		entry_bytes
	)
	if not encoded_catalog.ok:
		build_error = "legacy catalog encode failed"
		return null
	var decoded := codec.decode_catalog(encoded_catalog.canonical_bytes)
	if not decoded.ok:
		build_error = "legacy catalog read-back failed"
		return null
	return decoded.catalog

func _request_for(
	snapshot: ContentCatalogSnapshot
) -> ContentGenerationMigrationRequest:
	var active_ids: Array[StringName] = []
	for entry: ContentEntryValue in snapshot.entries:
		active_ids.append(entry.content_id)
	active_ids.sort_custom(_name_less)
	return ContentGenerationMigrationRequest.new(
		SOURCE_VERSION,
		snapshot.manifest_digest,
		active_ids,
		&"economy.default",
		[&"reward_table.default"],
		[&"map_node.normal"],
		[
			&"unlock.challenge_0",
			&"unlock.challenge_1",
			&"unlock.challenge_2",
			&"unlock.challenge_3",
			&"unlock.challenge_4",
			&"unlock.challenge_5",
		],
		&"meta_reward.default"
	)

func _mapping_for(
	input: ContentValidationInput
) -> Array[BossSourceMigrationEntryV1]:
	var result: Array[BossSourceMigrationEntryV1] = []
	for definition: ContentDefinition in input.definitions:
		if not definition is EncounterDef:
			continue
		var encounter := definition as EncounterDef
		for phase: BossPhaseDef in encounter.boss_phases:
			result.append(BossSourceMigrationEntryV1.new(
				encounter.id,
				phase.phase_index,
				phase.source_spawn_key
			))
	result.sort_custom(_mapping_less)
	return result

func _config_bytes(input: ContentValidationInput) -> PackedByteArray:
	for definition: ContentDefinition in input.definitions:
		if definition is CombatConfigDef:
			var compiled := ContentDefinitionCompilerV2.new().compile(definition)
			if not compiled.ok:
				build_error = "config compile failed"
				return PackedByteArray()
			var encoded := ContentCanonicalCodecV2.new().encode_entry(
				compiled.entry
			)
			if not encoded.ok:
				build_error = "config encode failed"
				return PackedByteArray()
			return encoded.canonical_bytes
	build_error = "config missing"
	return PackedByteArray()

func _entry_less(
	left: ContentEntryValue,
	right: ContentEntryValue
) -> bool:
	var left_code := ContentCategory.code_for_name(left.category)
	var right_code := ContentCategory.code_for_name(right.category)
	return String(left.content_id) < String(right.content_id) \
		if left_code == right_code else left_code < right_code

func _mapping_less(
	left: BossSourceMigrationEntryV1,
	right: BossSourceMigrationEntryV1
) -> bool:
	if left.encounter_id != right.encounter_id:
		return String(left.encounter_id) < String(right.encounter_id)
	return left.phase_index < right.phase_index

func _name_less(left: StringName, right: StringName) -> bool:
	return String(left) < String(right)
