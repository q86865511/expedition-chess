class_name ContentGenerationMigrationPortV2
extends ContentGenerationMigrationPort

## codec 2 → codec 3 的 exact allowlist migration port(requirements.md R1、
## design.md「CGM2／CGR2 exact migration contract」)。
##
## B4 硬化重點:port 不再對「pack 沒有 mapping 的 source id」做 identity 推定。
## 每一個被 active run 或 pinned selection 引用的 content id 都必須在 pack 內
## 有 exact mapping,且 mapping 的 target 必須真的存在於「已安裝的 target
## generation」——target entry 的 category 與 canonical entry digest 逐筆比對,
## localization catalog digest 亦以 target generation 實際安裝的 catalog bytes
## 重算值比對。任何一項缺漏都以具名 error fail-closed。

var _packs: Array[ContentGenerationMigrationPackV2] = []
var _allowlist: Array[ContentGenerationMigrationAllowlistEntryV2] = []
var _target_receipts_by_digest: Dictionary = {}
var _target_entries_by_manifest: Dictionary = {}
var _localization_digests_by_manifest: Dictionary = {}
var _codec := ContentGenerationMigrationCodecV2.new()


func _init(
	p_packs: Array,
	p_allowlist: Array,
	p_target_receipts_by_digest: Dictionary,
	p_target_entries_by_manifest: Dictionary = {},
	p_localization_digests_by_manifest: Dictionary = {}
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
	for key: Variant in p_target_entries_by_manifest.keys():
		var entries: Variant = p_target_entries_by_manifest[key]
		if not entries is Array:
			continue
		var by_id: Dictionary = {}
		for value: Variant in (entries as Array):
			if value is ContentGenerationMigrationTargetEntry:
				var entry: ContentGenerationMigrationTargetEntry = value
				by_id[entry.content_id] = entry.deep_clone()
		_target_entries_by_manifest[String(key)] = by_id
	for key: Variant in p_localization_digests_by_manifest.keys():
		var digest: Variant = p_localization_digests_by_manifest[key]
		if digest is String:
			_localization_digests_by_manifest[String(key)] = String(digest)


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
	var pack_error := _codec.try_reject_pack(pack, _allowlist)
	if pack_error != null:
		return ContentGenerationMigrationResult.failure(pack_error)
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
	):
		return _failure(
			ContentGenerationMigrationError.TARGET_MISMATCH,
			&"target_receipt"
		)
	var installed_entries: Dictionary = _target_entries_by_manifest.get(
		pack.expected_target_manifest_digest, {}
	)
	if installed_entries.is_empty():
		return _failure(
			ContentGenerationMigrationError.TARGET_MISMATCH,
			&"target_entry_digests"
		)
	if _localization_digests_by_manifest.get(
		pack.expected_target_manifest_digest, ""
	) != pack.localization_catalog_digest:
		return _failure(
			ContentGenerationMigrationError.PACK_INVALID,
			&"migration_pack.localization_catalog_digest"
		)
	var mapping_error := _validate_mappings_against_target(
		pack, target, installed_entries
	)
	if mapping_error != null:
		return ContentGenerationMigrationResult.failure(mapping_error)
	var coverage_error := _validate_reference_coverage(request, pack, target)
	if coverage_error != null:
		return ContentGenerationMigrationResult.failure(coverage_error)
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
	# 通過驗證的 mapping 表同時是套用計畫:呼叫端據此改寫 run 內的引用面,
	# 不得只換 content_snapshot 而讓舊 id 留在 run 裡(design.md:304-311)。
	return ContentGenerationMigrationResult.success(
		target, receipt, ContentGenerationMigrationPlan.new(pack.mappings)
	)


## 每一筆 IDENTITY／ALIAS mapping 的 target 都必須是 target generation 真的安裝的
## entry:存在、category 相符、canonical entry digest 相符,且列在 pinned receipt
## 的 active_entry_ids 內。
func _validate_mappings_against_target(
	pack: ContentGenerationMigrationPackV2,
	target: PinnedCatalogBuildReceipt,
	installed_entries: Dictionary
) -> ContentGenerationMigrationError:
	for mapping: ContentGenerationMigrationEntryV2 in pack.mappings:
		if mapping.mapping_kind \
			== ContentGenerationMigrationEntryV2.MappingKind.TOMBSTONE:
			continue
		var target_id := StringName(mapping.target_id)
		if not installed_entries.has(target_id):
			return _error(
				ContentGenerationMigrationError.TARGET_MISMATCH,
				&"migration_pack.mappings.target_id"
			)
		var installed: ContentGenerationMigrationTargetEntry = installed_entries[
			target_id
		]
		if String(installed.category) != mapping.source_category:
			return _error(
				ContentGenerationMigrationError.MAPPING_INVALID,
				&"migration_pack.mappings.source_category"
			)
		if installed.entry_digest != mapping.target_entry_digest:
			return _error(
				ContentGenerationMigrationError.TARGET_MISMATCH,
				&"migration_pack.mappings.target_entry_digest"
			)
		if not target.active_entry_ids.has(target_id):
			return _error(
				ContentGenerationMigrationError.TARGET_MISMATCH,
				&"target_receipt.active_entry_ids"
			)
	return null


## Active run 引用面(SaveMigrationRegistry traverse 產生)與 pinned selection 的
## 每一個 content id 都必須被 pack 明確覆蓋。
func _validate_reference_coverage(
	request: ContentGenerationMigrationRequest,
	pack: ContentGenerationMigrationPackV2,
	target: PinnedCatalogBuildReceipt
) -> ContentGenerationMigrationError:
	if request.referenced_entries.is_empty():
		# 呼叫端沒有 traverse run state 就等於沒有引用面可驗;不得放行。
		return _error(
			ContentGenerationMigrationError.CONFIG_INVALID,
			&"run.referenced_entries"
		)
	for reference: ContentGenerationMigrationReference in request.referenced_entries:
		var mapping := _mapping_for_reference(pack, reference)
		if mapping == null:
			return _error(
				ContentGenerationMigrationError.MAPPING_INVALID,
				reference.field_path
			)
		# ledger-bound 位置(claim receipt effect_id、node choice receipt 的
		# choice_set_id／choice_id)的 id 已進了已簽 digest 的 preimage,
		# 無法在 migration 內重算;只有 IDENTITY 才安全,其餘 fail-closed。
		if reference.ledger_bound and mapping.mapping_kind \
			!= ContentGenerationMigrationEntryV2.MappingKind.IDENTITY:
			return _error(
				ContentGenerationMigrationError.SELECTION_INCOMPATIBLE,
				reference.field_path
			)
		if mapping.mapping_kind \
			== ContentGenerationMigrationEntryV2.MappingKind.TOMBSTONE:
			if reference.structural:
				return _error(
					ContentGenerationMigrationError.SELECTION_INCOMPATIBLE,
					reference.field_path
				)
			continue
		if reference.structural and mapping.requirement \
			!= ContentGenerationMigrationEntryV2.Requirement.REQUIRED:
			return _error(
				ContentGenerationMigrationError.MAPPING_INVALID,
				reference.field_path
			)
		var target_id := StringName(mapping.target_id)
		if not target.active_entry_ids.has(target_id):
			return _error(
				ContentGenerationMigrationError.SELECTION_INCOMPATIBLE,
				reference.field_path
			)
		var field_error := _target_field_accepts(reference, target, target_id)
		if field_error != null:
			return field_error
	for content_id: StringName in request.enabled_content_ids:
		var selection_reference := ContentGenerationMigrationReference.new(
			&"", content_id, &"run.content_snapshot.enabled_content_ids", false
		)
		var selection_mapping := _mapping_for_reference(pack, selection_reference)
		if selection_mapping == null:
			return _error(
				ContentGenerationMigrationError.MAPPING_INVALID,
				selection_reference.field_path
			)
		if selection_mapping.mapping_kind \
			== ContentGenerationMigrationEntryV2.MappingKind.TOMBSTONE:
			continue
		if not target.active_entry_ids.has(StringName(selection_mapping.target_id)):
			return _error(
				ContentGenerationMigrationError.SELECTION_INCOMPATIBLE,
				selection_reference.field_path
			)
	return null


## Snapshot 的權威欄位(economy/combat config、meta reward table、reward table、
## map node、challenge unlock)映射後必須落在 target receipt 的同一欄位上。
func _target_field_accepts(
	reference: ContentGenerationMigrationReference,
	target: PinnedCatalogBuildReceipt,
	target_id: StringName
) -> ContentGenerationMigrationError:
	var accepted := true
	match reference.category:
		&"economy_config":
			accepted = target.economy_config_id == target_id
		&"combat_config":
			accepted = target.combat_config_id == target_id
		&"meta_reward_table":
			accepted = target.meta_reward_table_id == target_id
		&"reward_table":
			accepted = target.reward_table_ids.has(target_id)
		&"map_node":
			accepted = target.map_node_def_ids.has(target_id)
		&"unlock":
			accepted = target.challenge_unlock_def_ids.has(target_id)
	if not accepted:
		return _error(
			ContentGenerationMigrationError.TARGET_MISMATCH,
			reference.field_path
		)
	return null


## category 已知 → 必須 exact (category, id) 命中;category 未知(selection-only)
## → 只接受唯一一筆同 id 的 mapping,重複即視為 ambiguous 而拒絕。
func _mapping_for_reference(
	pack: ContentGenerationMigrationPackV2,
	reference: ContentGenerationMigrationReference
) -> ContentGenerationMigrationEntryV2:
	var found: ContentGenerationMigrationEntryV2 = null
	for mapping: ContentGenerationMigrationEntryV2 in pack.mappings:
		if mapping.source_id != String(reference.content_id):
			continue
		if not reference.category.is_empty():
			if mapping.source_category == String(reference.category):
				return mapping
			continue
		if found != null:
			return null
		found = mapping
	return found


func _error(
	code: StringName,
	path: StringName
) -> ContentGenerationMigrationError:
	return ContentGenerationMigrationError.new(code, path)


func _failure(
	code: StringName,
	path: StringName
) -> ContentGenerationMigrationResult:
	return ContentGenerationMigrationResult.failure(
		ContentGenerationMigrationError.new(code, path)
	)
