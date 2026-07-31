class_name ContentGenerationMigrationAdapter
extends ContentGenerationMigrationPort

# CGM1 (v1→v2) 產物固定 catalog schema 1;不得沿用已升版的
# ContentRegistryService.CATALOG_SCHEMA_VERSION
const _CGM1_TARGET_CATALOG_SCHEMA_VERSION: int = 1

var _registry: ContentRegistryService
var _packs: Array[ContentGenerationMigrationPackV1] = []
var _allowlist: Array[ContentGenerationMigrationAllowlistEntry] = []
var _codec := ContentGenerationMigrationCodec.new()
var _transcoder := ContentGenerationMigrationTranscoder.new()

func _init(
	registry: ContentRegistryService,
	packs: Array[ContentGenerationMigrationPackV1],
	allowlist: Array[ContentGenerationMigrationAllowlistEntry]
) -> void:
	_registry = registry
	for pack: ContentGenerationMigrationPackV1 in packs:
		if pack != null:
			_packs.append(pack.deep_clone())
	for entry: ContentGenerationMigrationAllowlistEntry in allowlist:
		if entry != null:
			_allowlist.append(entry.deep_clone())

func migrate_generation(
	request: ContentGenerationMigrationRequest
) -> ContentGenerationMigrationResult:
	if _registry == null:
		return _failure(
			ContentGenerationMigrationError.PORT_UNCONFIGURED,
			&"run.content_snapshot"
		)
	if request == null or request.source_content_version.is_empty() \
		or request.source_manifest_digest.is_empty():
		return _failure(
			ContentGenerationMigrationError.SOURCE_MISMATCH,
			&"run.content_snapshot"
		)
	var candidates := _matching_packs(request)
	if candidates.is_empty():
		return _failure(
			ContentGenerationMigrationError.PACK_MISSING,
			&"migration_pack.source"
		)
	if candidates.size() != 1:
		return _failure(
			ContentGenerationMigrationError.PACK_AMBIGUOUS,
			&"migration_pack.source"
		)
	return _migrate_with_pack(request, candidates[0])

func _matching_packs(
	request: ContentGenerationMigrationRequest
) -> Array[ContentGenerationMigrationPackV1]:
	var result: Array[ContentGenerationMigrationPackV1] = []
	for pack: ContentGenerationMigrationPackV1 in _packs:
		if pack.source_content_version == request.source_content_version \
			and pack.source_manifest_digest == request.source_manifest_digest:
			result.append(pack.deep_clone())
	return result

func _migrate_with_pack(
	request: ContentGenerationMigrationRequest,
	pack: ContentGenerationMigrationPackV1
) -> ContentGenerationMigrationResult:
	var validated := _codec.validate_pack(pack, _allowlist)
	if not validated.ok or validated.receipt == null:
		return ContentGenerationMigrationResult.failure(
			validated.error if validated.error != null else ContentGenerationMigrationError.new(
				ContentGenerationMigrationError.PACK_INVALID,
				&"migration_pack"
			)
		)
	if not _codec.validate_receipt(validated.receipt) \
		or not _receipt_matches_pack(validated.receipt, pack):
		return _failure(
			ContentGenerationMigrationError.PACK_INVALID,
			&"migration_receipt"
		)
	var legacy := _registry.legacy_v1_generation(
		request.source_content_version,
		request.source_manifest_digest
	)
	if not legacy.ok or legacy.snapshot == null:
		return _failure(
			ContentGenerationMigrationError.SOURCE_GENERATION_MISSING,
			&"run.content_snapshot.manifest_digest"
		)
	var draft_result := _transcoder.build(
		legacy.snapshot,
		request,
		pack.target_content_version,
		pack.combat_config_entry_bytes,
		pack.boss_mapping_entries
	)
	if not draft_result.ok:
		return ContentGenerationMigrationResult.failure(
			draft_result.error if draft_result.error != null else ContentGenerationMigrationError.new(
				ContentGenerationMigrationError.SOURCE_CATALOG_INVALID,
				&"source_catalog"
			)
		)
	if draft_result.snapshot.manifest_digest \
		!= pack.expected_target_manifest_digest:
		return _failure(
			ContentGenerationMigrationError.TARGET_MISMATCH,
			&"migration_pack.expected_target_manifest_digest"
		)
	var target_receipt := _target_receipt(draft_result)
	if not _target_receipt_valid(
		target_receipt,
		draft_result,
		pack.expected_target_manifest_digest
	):
		return _failure(
			ContentGenerationMigrationError.PUBLISH_FAILED,
			&"target_receipt"
		)
	var generation := CatalogGenerationDraft.new(
		draft_result.snapshot,
		CatalogHandle.new(
			pack.expected_target_manifest_digest,
			pack.target_content_version,
			false
		),
		target_receipt
	)
	var published := _registry._publish_migrated_generation(generation)
	if not published.ok or published.receipt == null:
		return _failure(
			ContentGenerationMigrationError.PUBLISH_FAILED,
			&"target_generation"
		)
	if not _target_receipt_valid(
		published.receipt,
		draft_result,
		pack.expected_target_manifest_digest
	):
		return _failure(
			ContentGenerationMigrationError.PUBLISH_FAILED,
			&"target_receipt"
		)
	return ContentGenerationMigrationResult.success(
		published.receipt,
		validated.receipt
	)

func _target_receipt(
	draft: ContentGenerationMigrationDraftResult
) -> PinnedCatalogBuildReceipt:
	var selection: CatalogSelection = draft.selection
	return PinnedCatalogBuildReceipt.new(
		_CGM1_TARGET_CATALOG_SCHEMA_VERSION,
		ContentCanonicalCodecV2.CONTENT_CODEC_VERSION_V2,
		selection.content_version,
		_registry._selection_digest(selection),
		draft.active_entry_ids,
		selection.economy_config_id,
		selection.combat_config_id,
		selection.reward_table_ids,
		selection.map_node_def_ids,
		selection.challenge_unlock_def_ids,
		selection.meta_reward_table_id,
		draft.snapshot.manifest_digest
	)

func _target_receipt_valid(
	receipt: PinnedCatalogBuildReceipt,
	draft: ContentGenerationMigrationDraftResult,
	expected_manifest_digest: String
) -> bool:
	if receipt == null or draft == null or not draft.ok \
		or draft.snapshot == null or draft.selection == null:
		return false
	var selection: CatalogSelection = draft.selection
	return receipt.catalog_schema_version \
		== _CGM1_TARGET_CATALOG_SCHEMA_VERSION \
		and receipt.content_codec_version \
		== ContentCanonicalCodecV2.CONTENT_CODEC_VERSION_V2 \
		and receipt.content_version == selection.content_version \
		and receipt.selection_digest == _registry._selection_digest(selection) \
		and receipt.active_entry_ids == draft.active_entry_ids \
		and receipt.economy_config_id == selection.economy_config_id \
		and receipt.combat_config_id == selection.combat_config_id \
		and receipt.reward_table_ids == selection.reward_table_ids \
		and receipt.map_node_def_ids == selection.map_node_def_ids \
		and receipt.challenge_unlock_def_ids \
		== selection.challenge_unlock_def_ids \
		and receipt.meta_reward_table_id == selection.meta_reward_table_id \
		and receipt.manifest_digest == expected_manifest_digest \
		and receipt.manifest_digest == draft.snapshot.manifest_digest

func _receipt_matches_pack(
	receipt: ContentGenerationMigrationReceipt,
	pack: ContentGenerationMigrationPackV1
) -> bool:
	return receipt != null and pack != null \
		and receipt.source_manifest_digest == pack.source_manifest_digest \
		and receipt.target_manifest_digest \
		== pack.expected_target_manifest_digest \
		and receipt.combat_config_entry_digest \
		== pack.combat_config_entry_digest \
		and receipt.boss_mapping_digest == pack.boss_mapping_digest \
		and receipt.pack_digest == pack.pack_digest \
		and receipt.from_codec == pack.from_codec \
		and receipt.to_codec == pack.to_codec

func _failure(
	code: StringName,
	field_path: StringName
) -> ContentGenerationMigrationResult:
	return ContentGenerationMigrationResult.failure(
		ContentGenerationMigrationError.new(code, field_path)
	)
