class_name ContentGenerationMigrationPortV2
extends ContentGenerationMigrationPort

var _packs: Array[ContentGenerationMigrationPackV2] = []
var _allowlist: Array[ContentGenerationMigrationAllowlistEntryV2] = []
var _target_receipts_by_digest: Dictionary = {}
var _codec := ContentGenerationMigrationCodecV2.new()


func _init(
	p_packs: Array,
	p_allowlist: Array,
	p_target_receipts_by_digest: Dictionary
) -> void:
	for value: Variant in p_packs:
		if value is ContentGenerationMigrationPackV2:
			_packs.append(value)
	for value: Variant in p_allowlist:
		if value is ContentGenerationMigrationAllowlistEntryV2:
			_allowlist.append(value)
	for key: Variant in p_target_receipts_by_digest.keys():
		var receipt: Variant = p_target_receipts_by_digest[key]
		if receipt is PinnedCatalogBuildReceipt:
			_target_receipts_by_digest[String(key)] = receipt.deep_clone()


func migrate_generation(
	request: ContentGenerationMigrationRequest
) -> ContentGenerationMigrationResult:
	if request == null \
		or request.source_catalog_schema_version != 1 \
		or request.source_content_codec_version != 2:
		return _failure(
			ContentGenerationMigrationError.SOURCE_MISMATCH,
			&"run.content_snapshot.content_codec_version"
		)
	var matching: Array[ContentGenerationMigrationPackV2] = []
	for pack: ContentGenerationMigrationPackV2 in _packs:
		if (
			pack.source_content_version == request.source_content_version
			and pack.source_manifest_digest == request.source_manifest_digest
		):
			matching.append(pack)
	if matching.is_empty():
		return _failure(
			ContentGenerationMigrationError.PACK_MISSING,
			&"run.content_snapshot.manifest_digest"
		)
	if matching.size() != 1:
		return _failure(
			ContentGenerationMigrationError.PACK_AMBIGUOUS,
			&"run.content_snapshot.manifest_digest"
		)
	var pack := matching[0]
	if not _codec.validate_pack(pack, _allowlist):
		return _failure(
			ContentGenerationMigrationError.PACK_INVALID, &"migration_pack"
		)
	if not _target_receipts_by_digest.has(
		pack.expected_target_manifest_digest
	):
		return _failure(
			ContentGenerationMigrationError.TARGET_MISMATCH,
			&"target_manifest_digest"
		)
	var target: PinnedCatalogBuildReceipt = _target_receipts_by_digest[
		pack.expected_target_manifest_digest
	]
	if (
		target.catalog_schema_version != 2
		or target.content_codec_version != 3
		or target.content_version != pack.target_content_version
		or target.manifest_digest != pack.expected_target_manifest_digest
		or not _selection_maps_to_target(request, pack, target)
	):
		return _failure(
			ContentGenerationMigrationError.TARGET_MISMATCH,
			&"target_receipt"
		)
	var receipt := ContentGenerationMigrationReceiptV2.new()
	receipt.source_content_version = pack.source_content_version
	receipt.target_content_version = pack.target_content_version
	receipt.source_manifest_digest = pack.source_manifest_digest
	receipt.target_manifest_digest = pack.expected_target_manifest_digest
	receipt.mapping_digest = pack.mapping_digest
	receipt.localization_catalog_digest = pack.localization_catalog_digest
	receipt.pack_digest = pack.pack_digest
	receipt.source_catalog_schema_version = pack.source_catalog_schema_version
	receipt.target_catalog_schema_version = pack.target_catalog_schema_version
	receipt.from_codec = pack.from_codec
	receipt.to_codec = pack.to_codec
	receipt.receipt_digest = _codec.receipt_digest(receipt)
	if receipt.receipt_digest.is_empty():
		return _failure(
			ContentGenerationMigrationError.PACK_INVALID, &"receipt_digest"
		)
	return ContentGenerationMigrationResult.success(target, receipt)


func _selection_maps_to_target(
	request: ContentGenerationMigrationRequest,
	pack: ContentGenerationMigrationPackV2,
	target: PinnedCatalogBuildReceipt
) -> bool:
	var mapped_ids: Array[StringName] = []
	for source_id: StringName in request.enabled_content_ids:
		var mapping := _mapping_for(pack, source_id)
		if mapping == null:
			mapped_ids.append(source_id)
		elif mapping.mapping_kind == ContentGenerationMigrationEntryV2.MappingKind.TOMBSTONE:
			if mapping.requirement == ContentGenerationMigrationEntryV2.Requirement.REQUIRED:
				return false
		elif mapping.has_target:
			mapped_ids.append(StringName(mapping.target_id))
	for content_id: StringName in mapped_ids:
		if not target.active_entry_ids.has(content_id):
			return false
	return true


func _mapping_for(
	pack: ContentGenerationMigrationPackV2,
	source_id: StringName
) -> ContentGenerationMigrationEntryV2:
	for mapping: ContentGenerationMigrationEntryV2 in pack.mappings:
		if mapping.source_id == String(source_id):
			return mapping
	return null


func _failure(
	code: StringName,
	path: StringName
) -> ContentGenerationMigrationResult:
	return ContentGenerationMigrationResult.failure(
		ContentGenerationMigrationError.new(code, path)
	)
