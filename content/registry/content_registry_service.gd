class_name ContentRegistryService
extends Node

const CATALOG_SCHEMA_VERSION := 2

var _codec := ContentCanonicalCodecV3.new()
var _compiler := ContentDefinitionCompilerV3.new()
var _authoring_by_id: Dictionary = {}
var _content_version: String
var _pack_ids: Array[StringName] = []
var _aliases: Array[ContentAliasValue] = []
var _tombstones: Array[ContentTombstoneValue] = []
var _catalogs_by_digest: Dictionary = {}
var _legacy_v1_catalogs_by_digest: Dictionary = {}
var _receipts_by_digest: Dictionary = {}
var _lease_counts: Dictionary = {}
var _latest_digest: String
var _validation_input: ContentValidationInput
var _stable_id_validator := StableIdValidator.new()

func install_validated(
	validation_input: ContentValidationInput,
	content_version: String,
	pack_ids: Array[StringName]
) -> CatalogCompileResult:
	if validation_input == null:
		return CatalogCompileResult.failure(&"CONTENT_VALIDATION_FAILED", &"validation_input")
	var report := ContentValidator.new().validate(validation_input)
	if not report.valid:
		var first := report.issues[0]
		return CatalogCompileResult.failure(first.code, first.field_path, first.source_id)
	return _install_authoring_unchecked(
		validation_input.definitions,
		content_version,
		pack_ids,
		validation_input.aliases,
		validation_input.tombstones,
		validation_input
	)

func _install_authoring_unchecked(
	definitions: Array[ContentDefinition],
	content_version: String,
	pack_ids: Array[StringName],
	aliases: Array[ContentAliasValue],
	tombstones: Array[ContentTombstoneValue],
	validated_input: ContentValidationInput
) -> CatalogCompileResult:
	var prepared := _prepare_authoring(definitions, aliases, tombstones)
	if not prepared.ok:
		return prepared
	var candidate_authoring: Dictionary = {}
	for definition in definitions:
		candidate_authoring[definition.id] = definition.duplicate(true)
	var candidate_pack_ids := pack_ids.duplicate()
	candidate_pack_ids.sort_custom(_canonical_id_less)
	var candidate_aliases := _flatten_aliases(aliases)
	candidate_aliases.sort_custom(_alias_less)
	var candidate_tombstones: Array[ContentTombstoneValue] = []
	for tombstone in tombstones: candidate_tombstones.append(tombstone.deep_clone())
	candidate_tombstones.sort_custom(_tombstone_less)
	var all_ids: Array[StringName] = []
	for key in candidate_authoring.keys(): all_ids.append(key as StringName)
	all_ids.sort_custom(_string_name_less)
	var build := _build_generation(candidate_authoring, content_version, candidate_pack_ids, candidate_aliases,
		candidate_tombstones, all_ids, "", true)
	if not build.ok:
		return _compile_failure(build.error)
	_authoring_by_id = candidate_authoring
	_content_version = content_version
	_pack_ids = candidate_pack_ids
	_aliases = candidate_aliases
	_tombstones = candidate_tombstones
	_validation_input = validated_input.deep_clone()
	_publish_generation(build.draft)
	_latest_digest = build.draft.handle.manifest_digest
	return CatalogCompileResult.success(build.draft.handle)

func compile_pinned_generation(selection: CatalogSelection) -> CatalogCompileResult:
	var build := _build_pinned_generation(selection)
	if not build.ok: return _compile_failure(build.error)
	_publish_generation(build.draft)
	return CatalogCompileResult.success(build.draft.handle, build.draft.receipt)

func register_legacy_v1_generation(
	catalog_bytes: PackedByteArray
) -> LegacyContentGenerationResult:
	if catalog_bytes.is_empty():
		return LegacyContentGenerationResult.failure(
			LegacyContentGenerationError.INPUT_INVALID,
			&"catalog_bytes"
		)
	var decoded := ContentCanonicalCodecV1.new().decode_catalog(catalog_bytes)
	if not decoded.ok or decoded.catalog == null:
		return LegacyContentGenerationResult.failure(
			LegacyContentGenerationError.CODEC_INVALID,
			decoded.error.field_path if decoded.error != null else &"catalog_bytes"
		)
	var snapshot: ContentCatalogSnapshot = decoded.catalog
	if snapshot.manifest == null or snapshot.manifest.content_version.is_empty() \
		or snapshot.manifest_digest.is_empty():
		return LegacyContentGenerationResult.failure(
			LegacyContentGenerationError.CODEC_INVALID,
			&"catalog.manifest"
		)
	if _legacy_v1_catalogs_by_digest.has(snapshot.manifest_digest):
		var existing: ContentCatalogSnapshot = \
			_legacy_v1_catalogs_by_digest[snapshot.manifest_digest]
		if existing.diagnostic_catalog_bytes != snapshot.diagnostic_catalog_bytes:
			return LegacyContentGenerationResult.failure(
				LegacyContentGenerationError.DUPLICATE_CONFLICT,
				&"catalog.manifest_digest"
			)
		return LegacyContentGenerationResult.success(existing)
	_legacy_v1_catalogs_by_digest[snapshot.manifest_digest] = snapshot.deep_clone()
	return LegacyContentGenerationResult.success(snapshot)

func legacy_v1_generation(
	content_version: String,
	manifest_digest: String
) -> LegacyContentGenerationResult:
	if content_version.is_empty() or manifest_digest.is_empty():
		return LegacyContentGenerationResult.failure(
			LegacyContentGenerationError.INPUT_INVALID,
			&"source"
		)
	if not _legacy_v1_catalogs_by_digest.has(manifest_digest):
		return LegacyContentGenerationResult.failure(
			LegacyContentGenerationError.SOURCE_MISMATCH,
			&"source_manifest_digest"
		)
	var snapshot: ContentCatalogSnapshot = _legacy_v1_catalogs_by_digest[manifest_digest]
	if snapshot.manifest == null \
		or snapshot.manifest.content_version != content_version \
		or snapshot.manifest_digest != manifest_digest:
		return LegacyContentGenerationResult.failure(
			LegacyContentGenerationError.SOURCE_MISMATCH,
			&"source_content_version"
		)
	return LegacyContentGenerationResult.success(snapshot)

func resolve(content_ref: ContentRef) -> ContentResolveResult:
	if content_ref == null or not content_ref.is_valid():
		return ContentResolveResult.failure(&"CONTENT_REF_INVALID", &"content_ref")
	if not _catalogs_by_digest.has(content_ref.manifest_digest):
		return ContentResolveResult.failure(&"CONTENT_CATALOG_MISSING", &"manifest_digest", content_ref.content_id)
	var snapshot: ContentCatalogSnapshot = _catalogs_by_digest[content_ref.manifest_digest]
	var entry := snapshot._find_entry(content_ref.content_id)
	if entry == null:
		return ContentResolveResult.failure(&"CONTENT_ENTRY_MISSING", &"content_id", content_ref.content_id)
	return ContentResolveResult.success(ContentDefinitionView.new(content_ref.manifest_digest, entry))

func try_resolve(content_ref: ContentRef) -> ContentDefinitionView:
	var result := resolve(content_ref)
	return result.value if result.ok else null

func validate_all() -> ContentValidationReport:
	if _validation_input == null:
		return ContentValidationReport.failure(&"CONTENT_VALIDATION_FAILED", &"registry.validation_input")
	return ContentValidator.new().validate(_validation_input)

func latest_catalog_handle() -> CatalogHandleResult:
	if _latest_digest.is_empty() or not _catalogs_by_digest.has(_latest_digest):
		return CatalogHandleResult.failure(&"CONTENT_CATALOG_MISSING", &"latest")
	var snapshot: ContentCatalogSnapshot = _catalogs_by_digest[_latest_digest]
	return CatalogHandleResult.success(CatalogHandle.new(_latest_digest, snapshot.manifest.content_version, true))

func catalog_handle(manifest_digest: String) -> CatalogHandleResult:
	if not _catalogs_by_digest.has(manifest_digest):
		return CatalogHandleResult.failure(&"CONTENT_CATALOG_MISSING", &"manifest_digest")
	var snapshot: ContentCatalogSnapshot = _catalogs_by_digest[manifest_digest]
	return CatalogHandleResult.success(CatalogHandle.new(manifest_digest, snapshot.manifest.content_version, manifest_digest == _latest_digest))

func acquire_catalog_lease(handle: CatalogHandle) -> CatalogLeaseResult:
	if handle == null or not _catalogs_by_digest.has(handle.manifest_digest): return CatalogLeaseResult.failure(&"CONTENT_CATALOG_MISSING")
	var count := int(_lease_counts.get(handle.manifest_digest, 0))
	_lease_counts[handle.manifest_digest] = count + 1
	return CatalogLeaseResult.success(CatalogLease.new(self, handle.manifest_digest))

func release_catalog_lease(manifest_digest: String) -> void:
	var count := int(_lease_counts.get(manifest_digest, 0))
	if count <= 1: _lease_counts.erase(manifest_digest)
	else: _lease_counts[manifest_digest] = count - 1

func _lease_is_active(manifest_digest: String) -> bool:
	return _catalogs_by_digest.has(manifest_digest) \
		and int(_lease_counts.get(manifest_digest, 0)) > 0

func _remove_unleased_generation(manifest_digest: String) -> bool:
	if manifest_digest == _latest_digest or int(_lease_counts.get(manifest_digest, 0)) > 0:
		return false
	_receipts_by_digest.erase(manifest_digest)
	return _catalogs_by_digest.erase(manifest_digest)

## 已安裝 generation 的 manifest entry index(category / content_id / entry digest)。
## codec 2→3 migration pack 需要逐筆比對 target entry,不得只信 pack 自報的 digest。
func _entry_indexes_for_digest(manifest_digest: String) -> Array[ContentEntryIndexValue]:
	var result: Array[ContentEntryIndexValue] = []
	if not _catalogs_by_digest.has(manifest_digest):
		return result
	var snapshot: ContentCatalogSnapshot = _catalogs_by_digest[manifest_digest]
	if snapshot.manifest == null:
		return result
	for index: ContentEntryIndexValue in snapshot.manifest.entry_indexes:
		result.append(index.deep_clone())
	return result

func _receipt_for_digest(manifest_digest: String) -> PinnedCatalogBuildReceipt:
	if not _receipts_by_digest.has(manifest_digest): return null
	var receipt: PinnedCatalogBuildReceipt = _receipts_by_digest[manifest_digest]
	return receipt.deep_clone()

func _migration_lookup(content_id: StringName) -> ContentMigrationLookup:
	if _authoring_by_id.has(content_id):
		var definition: ContentDefinition = _authoring_by_id[content_id]
		return ContentMigrationLookup.active(definition.category_name(), content_id)
	for alias in _aliases:
		if alias.source_id == content_id:
			if not _authoring_by_id.has(alias.target_id): return ContentMigrationLookup.missing()
			var target: ContentDefinition = _authoring_by_id[alias.target_id]
			return ContentMigrationLookup.alias(target.category_name(), alias.target_id)
	for tombstone in _tombstones:
		if tombstone.original_id == content_id: return ContentMigrationLookup.tombstone_value(tombstone)
	return ContentMigrationLookup.missing()

func rebuild_from_probe(probe: ContentSnapshotProbe) -> CatalogCompileResult:
	if probe == null:
		return CatalogCompileResult.failure(&"PINNED_CATALOG_SELECTION_INVALID", &"probe")
	var selection := CatalogSelection.new(
		probe.content_version,
		probe.enabled_content_ids,
		probe.economy_config_id,
		probe.combat_config_id,
		probe.reward_table_ids, probe.map_node_def_ids, probe.challenge_unlock_def_ids, probe.meta_reward_table_id)
	var build := _build_pinned_generation(selection)
	if not build.ok: return _compile_failure(build.error)
	if build.draft.handle.manifest_digest != probe.manifest_digest:
		return CatalogCompileResult.failure(&"PINNED_CATALOG_MANIFEST_MISMATCH", &"manifest_digest")
	_publish_generation(build.draft)
	return CatalogCompileResult.success(build.draft.handle, build.draft.receipt)

func _build_pinned_generation(selection: CatalogSelection) -> CatalogGenerationBuildResult:
	if selection == null:
		return CatalogGenerationBuildResult.failure(&"PINNED_CATALOG_SELECTION_INVALID", &"selection")
	if selection.content_version != _content_version:
		return CatalogGenerationBuildResult.failure(&"PINNED_CATALOG_PACK_MISSING", &"content_version")
	var selection_error := _validate_selection(selection)
	if selection_error != null:
		return CatalogGenerationBuildResult.failure(
			selection_error.code,
			selection_error.field_path,
			_optional_source_value(selection_error.source_id)
		)
	var roots: Array[StringName] = selection.root_enabled_content_ids.duplicate()
	roots.append(selection.economy_config_id)
	roots.append(selection.combat_config_id)
	roots.append_array(selection.reward_table_ids)
	roots.append_array(selection.map_node_def_ids)
	roots.append_array(selection.challenge_unlock_def_ids)
	roots.append(selection.meta_reward_table_id)
	var closure := _reference_closure(_authoring_by_id, roots)
	if not closure.ok:
		return CatalogGenerationBuildResult.failure(
			closure.error.code,
			closure.error.field_path,
			_optional_source_value(closure.error.source_id)
		)
	return _build_generation(
		_authoring_by_id,
		_content_version,
		_pack_ids,
		_aliases,
		_tombstones,
		closure.active_ids,
		_selection_digest(selection),
		false,
		selection
	)

func _validate_selection(selection: CatalogSelection) -> CatalogCompileError:
	if selection.content_version.is_empty():
		return CatalogCompileError.new(&"PINNED_CATALOG_SELECTION_INVALID", &"content_version")
	for content_id in selection.root_enabled_content_ids:
		var root_error := _validate_selection_reference(content_id, &"", &"root_enabled_content_ids")
		if root_error != null: return root_error
	var economy_error := _validate_selection_reference(selection.economy_config_id, &"economy_config", &"economy_config_id")
	if economy_error != null: return economy_error
	if selection.combat_config_id != &"config.combat_default":
		return CatalogCompileError.new(
			&"PINNED_CATALOG_SELECTION_INVALID",
			&"combat_config_id",
			selection.combat_config_id
		)
	var combat_error := _validate_selection_reference(
		selection.combat_config_id,
		&"combat_config",
		&"combat_config_id"
	)
	if combat_error != null: return combat_error
	for content_id in selection.reward_table_ids:
		var reward_error := _validate_selection_reference(content_id, &"reward_table", &"reward_table_ids")
		if reward_error != null: return reward_error
	for content_id in selection.map_node_def_ids:
		var map_error := _validate_selection_reference(content_id, &"map_node", &"map_node_def_ids")
		if map_error != null: return map_error
	for content_id in selection.challenge_unlock_def_ids:
		var unlock_error := _validate_selection_reference(content_id, &"unlock", &"challenge_unlock_def_ids")
		if unlock_error != null: return unlock_error
	var meta_error := _validate_selection_reference(selection.meta_reward_table_id, &"meta_reward_table", &"meta_reward_table_id")
	if meta_error != null: return meta_error
	return null

func _validate_selection_reference(content_id: StringName, expected_category: StringName, path: StringName) -> CatalogCompileError:
	if not _stable_id_validator.is_valid(content_id) or not _authoring_by_id.has(content_id):
		return CatalogCompileError.new(&"PINNED_CATALOG_REFERENCE_MISSING", path, content_id)
	if not expected_category.is_empty():
		var definition: ContentDefinition = _authoring_by_id[content_id]
		if definition.category_name() != expected_category:
			return CatalogCompileError.new(&"PINNED_CATALOG_SELECTION_INVALID", path, content_id)
	return null

func _reference_closure(authoring_by_id: Dictionary, roots: Array[StringName]) -> CatalogClosureResult:
	var pending: Array[StringName] = roots.duplicate()
	var seen: Dictionary = {}
	while not pending.is_empty():
		var content_id: StringName = pending.pop_back()
		if seen.has(content_id): continue
		if not authoring_by_id.has(content_id):
			return CatalogClosureResult.failure(&"PINNED_CATALOG_REFERENCE_MISSING", &"selection.reference", content_id)
		seen[content_id] = true
		var definition: ContentDefinition = authoring_by_id[content_id]
		for reference in _compiler.collect_references(definition):
			if not seen.has(reference): pending.append(reference)
	var active_ids: Array[StringName] = []
	for key in seen.keys(): active_ids.append(key as StringName)
	active_ids.sort_custom(_string_name_less)
	return CatalogClosureResult.success(active_ids)

func _build_generation(
	authoring_by_id: Dictionary,
	content_version: String,
	pack_ids: Array[StringName],
	aliases: Array[ContentAliasValue],
	tombstones: Array[ContentTombstoneValue],
	active_ids: Array[StringName],
	selection_digest: String,
	is_latest: bool,
	selection: CatalogSelection = null
) -> CatalogGenerationBuildResult:
	var compiler := ContentDefinitionCompilerV3.new()
	var entries: Array[ContentEntryValue] = []
	for content_id in active_ids:
		if not authoring_by_id.has(content_id):
			return CatalogGenerationBuildResult.failure(&"CONTENT_ENTRY_MISSING", &"active_ids", content_id)
		var definition: ContentDefinition = authoring_by_id[content_id]
		var compile_result := compiler.compile(definition)
		if not compile_result.ok:
			return CatalogGenerationBuildResult.failure(&"CONTENT_CODEC_INVALID", compile_result.error.field_path, content_id)
		entries.append(compile_result.entry)
	entries.sort_custom(_entry_less)
	var entry_bytes: Array[PackedByteArray] = []
	var indexes: Array[ContentEntryIndexValue] = []
	for entry in entries:
		var encoded := _codec.encode_entry(entry)
		if not encoded.ok:
			return CatalogGenerationBuildResult.failure(&"CONTENT_CODEC_INVALID", encoded.error.field_path, entry.content_id)
		entry_bytes.append(encoded.canonical_bytes)
		indexes.append(ContentEntryIndexValue.new(entry.category, entry.content_id, entry.resource_schema_version, _codec.sha256_bytes(encoded.canonical_bytes)))
	var manifest := ContentManifestValue.new()
	manifest.catalog_schema_version = CATALOG_SCHEMA_VERSION
	manifest.content_version = content_version
	manifest.pack_ids = pack_ids.duplicate()
	for alias in aliases: manifest.aliases.append(alias.deep_clone())
	for tombstone in tombstones: manifest.tombstones.append(tombstone.deep_clone())
	manifest.entry_indexes = indexes
	var manifest_result := _codec.encode_manifest(manifest)
	if not manifest_result.ok:
		return CatalogGenerationBuildResult.failure(&"CONTENT_CODEC_INVALID", manifest_result.error.field_path)
	var digest_bytes := _codec.sha256_bytes(manifest_result.canonical_bytes)
	var digest := digest_bytes.hex_encode()
	var catalog_result := _codec.encode_catalog(digest_bytes, manifest_result.canonical_bytes, entry_bytes)
	if not catalog_result.ok:
		return CatalogGenerationBuildResult.failure(&"CONTENT_CODEC_INVALID", catalog_result.error.field_path)
	var snapshot := ContentCatalogSnapshot.new()
	snapshot.manifest = manifest.deep_clone()
	snapshot.manifest_bytes = manifest_result.canonical_bytes.duplicate()
	snapshot.manifest_digest = digest
	for entry in entries: snapshot.entries.append(entry.deep_clone())
	for bytes in entry_bytes: snapshot.entry_bytes.append(bytes.duplicate())
	snapshot.diagnostic_catalog_bytes = catalog_result.canonical_bytes.duplicate()
	var handle := CatalogHandle.new(digest, content_version, is_latest)
	var receipt: PinnedCatalogBuildReceipt = null
	if selection != null:
		receipt = PinnedCatalogBuildReceipt.new(
			CATALOG_SCHEMA_VERSION,
			ContentCanonicalCodecV3.CONTENT_CODEC_VERSION_V3,
			content_version,
			selection_digest,
			active_ids,
			selection.economy_config_id,
			selection.combat_config_id,
			selection.reward_table_ids,
			selection.map_node_def_ids,
			selection.challenge_unlock_def_ids,
			selection.meta_reward_table_id,
			digest
		)
	return CatalogGenerationBuildResult.success(CatalogGenerationDraft.new(snapshot, handle, receipt))

func _publish_generation(draft: CatalogGenerationDraft) -> void:
	_catalogs_by_digest[draft.handle.manifest_digest] = draft.snapshot.deep_clone()
	if draft.receipt != null:
		_receipts_by_digest[draft.handle.manifest_digest] = draft.receipt.deep_clone()

func _publish_migrated_generation(
	draft: CatalogGenerationDraft
) -> CatalogCompileResult:
	if draft == null or draft.snapshot == null or draft.handle == null \
		or draft.receipt == null:
		return CatalogCompileResult.failure(
			&"CONTENT_MIGRATED_GENERATION_INVALID", &"draft"
		)
	var digest := draft.handle.manifest_digest
	if draft.handle.is_latest or digest != draft.snapshot.manifest_digest \
		or digest != draft.receipt.manifest_digest \
		or draft.receipt.content_codec_version != 2 \
		or draft.receipt.catalog_schema_version != 1:
		return CatalogCompileResult.failure(
			&"CONTENT_MIGRATED_GENERATION_INVALID", &"draft.manifest_digest"
		)
	var decoded := ContentCanonicalCodecV2.new().decode_catalog(
		draft.snapshot.diagnostic_catalog_bytes
	)
	if not decoded.ok or decoded.catalog == null \
		or decoded.catalog.manifest == null \
		or decoded.catalog.manifest_digest != digest \
		or decoded.catalog.manifest_bytes != draft.snapshot.manifest_bytes \
		or decoded.catalog.manifest.content_version != draft.handle.content_version \
		or decoded.catalog.manifest.content_version != draft.receipt.content_version \
		or not _migrated_receipt_matches_catalog(draft.receipt, decoded.catalog):
		return CatalogCompileResult.failure(
			&"CONTENT_MIGRATED_GENERATION_INVALID", &"draft.catalog_bytes"
		)
	if _catalogs_by_digest.has(digest):
		var existing: ContentCatalogSnapshot = _catalogs_by_digest[digest]
		var existing_receipt := _receipt_for_digest(digest)
		if existing.diagnostic_catalog_bytes != draft.snapshot.diagnostic_catalog_bytes \
			or existing_receipt == null \
			or not _pinned_receipts_equal(existing_receipt, draft.receipt):
			return CatalogCompileResult.failure(
				&"CONTENT_MIGRATED_GENERATION_CONFLICT", &"draft.manifest_digest"
			)
		return CatalogCompileResult.success(draft.handle, existing_receipt)
	var sanitized := CatalogGenerationDraft.new(
		decoded.catalog,
		draft.handle,
		draft.receipt
	)
	_publish_generation(sanitized)
	return CatalogCompileResult.success(draft.handle, draft.receipt)

func _migrated_receipt_matches_catalog(
	receipt: PinnedCatalogBuildReceipt,
	snapshot: ContentCatalogSnapshot
) -> bool:
	if receipt == null or snapshot == null or snapshot.manifest == null \
		or receipt.combat_config_id != &"config.combat_default" \
		or not _digest_is_lower_hex(receipt.selection_digest):
		return false
	var active_ids: Array[StringName] = []
	var categories_by_id: Dictionary = {}
	for entry: ContentEntryValue in snapshot.entries:
		active_ids.append(entry.content_id)
		categories_by_id[entry.content_id] = entry.category
	active_ids.sort_custom(_string_name_less)
	if active_ids != receipt.active_entry_ids \
		or not _names_are_sorted_unique(receipt.active_entry_ids):
		return false
	if not _receipt_reference_matches(
		categories_by_id, receipt.economy_config_id, &"economy_config"
	) or not _receipt_reference_matches(
		categories_by_id, receipt.combat_config_id, &"combat_config"
	) or not _receipt_reference_matches(
		categories_by_id, receipt.meta_reward_table_id, &"meta_reward_table"
	):
		return false
	for content_id: StringName in receipt.reward_table_ids:
		if not _receipt_reference_matches(
			categories_by_id, content_id, &"reward_table"
		): return false
	for content_id: StringName in receipt.map_node_def_ids:
		if not _receipt_reference_matches(
			categories_by_id, content_id, &"map_node"
		): return false
	for content_id: StringName in receipt.challenge_unlock_def_ids:
		if not _receipt_reference_matches(
			categories_by_id, content_id, &"unlock"
		): return false
	return _names_are_sorted_unique(receipt.reward_table_ids) \
		and _names_are_sorted_unique(receipt.map_node_def_ids) \
		and _names_are_sorted_unique(receipt.challenge_unlock_def_ids)

func _receipt_reference_matches(
	categories_by_id: Dictionary,
	content_id: StringName,
	expected_category: StringName
) -> bool:
	return categories_by_id.has(content_id) \
		and categories_by_id[content_id] == expected_category

func _names_are_sorted_unique(values: Array[StringName]) -> bool:
	for index: int in range(1, values.size()):
		if String(values[index - 1]) >= String(values[index]):
			return false
	return true

func _digest_is_lower_hex(value: String) -> bool:
	if value.length() != 64: return false
	for character: String in value:
		if character not in "0123456789abcdef": return false
	return true

func _pinned_receipts_equal(
	left: PinnedCatalogBuildReceipt,
	right: PinnedCatalogBuildReceipt
) -> bool:
	return left.catalog_schema_version == right.catalog_schema_version \
		and left.content_codec_version == right.content_codec_version \
		and left.content_version == right.content_version \
		and left.selection_digest == right.selection_digest \
		and left.active_entry_ids == right.active_entry_ids \
		and left.economy_config_id == right.economy_config_id \
		and left.combat_config_id == right.combat_config_id \
		and left.reward_table_ids == right.reward_table_ids \
		and left.map_node_def_ids == right.map_node_def_ids \
		and left.challenge_unlock_def_ids == right.challenge_unlock_def_ids \
		and left.meta_reward_table_id == right.meta_reward_table_id \
		and left.manifest_digest == right.manifest_digest

func _compile_failure(error: CatalogCompileError) -> CatalogCompileResult:
	if error == null:
		return CatalogCompileResult.failure(&"PINNED_CATALOG_COMPILE_FAILED", &"generation")
	return CatalogCompileResult.failure(error.code, error.field_path, _optional_source_value(error.source_id))

func _optional_source_value(source_id: OptionalStringNameValue) -> StringName:
	return source_id.value if source_id != null else &""

func _generation_count() -> int:
	return _catalogs_by_digest.size()

func _receipt_count() -> int:
	return _receipts_by_digest.size()

func _legacy_generation_count() -> int:
	return _legacy_v1_catalogs_by_digest.size()

func _state_fingerprint() -> String:
	var values: Array[String] = [
		_content_version,
		_latest_digest,
		str(_validation_input != null),
		str(_validation_input.base_population_cap if _validation_input != null else 0),
	]
	for pack_id in _pack_ids: values.append("pack:%s" % String(pack_id))
	for alias in _aliases: values.append("alias:%s>%s" % [String(alias.source_id), String(alias.target_id)])
	for tombstone in _tombstones:
		values.append("tombstone:%s:%s:%s:%s:%s:%s" % [
			String(tombstone.original_id),
			String(tombstone.category),
			String(tombstone.policy),
			String(tombstone.replacement_id),
			str(tombstone.has_replacement),
			String(tombstone.reason_code),
		])
	var authoring_ids: Array[StringName] = []
	for key in _authoring_by_id.keys(): authoring_ids.append(key as StringName)
	authoring_ids.sort_custom(_string_name_less)
	var compiler := ContentDefinitionCompilerV3.new()
	for content_id in authoring_ids:
		var definition: ContentDefinition = _authoring_by_id[content_id]
		var compiled := compiler.compile(definition)
		var digest := "invalid"
		if compiled.ok:
			var encoded := _codec.encode_entry(compiled.entry)
			if encoded.ok: digest = _codec.sha256_bytes(encoded.canonical_bytes).hex_encode()
		values.append("authoring:%s:%s" % [String(content_id), digest])
	var catalog_keys: Array[String] = []
	for key in _catalogs_by_digest.keys(): catalog_keys.append(String(key))
	catalog_keys.sort()
	for key in catalog_keys: values.append("catalog:%s" % key)
	var legacy_keys: Array[String] = []
	for key in _legacy_v1_catalogs_by_digest.keys(): legacy_keys.append(String(key))
	legacy_keys.sort()
	for key in legacy_keys: values.append("legacy_v1:%s" % key)
	var receipt_keys: Array[String] = []
	for key in _receipts_by_digest.keys(): receipt_keys.append(String(key))
	receipt_keys.sort()
	for key in receipt_keys:
		var receipt: PinnedCatalogBuildReceipt = _receipts_by_digest[key]
		values.append("receipt:%s:%s" % [key, receipt.selection_digest])
	var lease_keys: Array[String] = []
	for key in _lease_counts.keys(): lease_keys.append(String(key))
	lease_keys.sort()
	for key in lease_keys: values.append("lease:%s:%d" % [key, int(_lease_counts[key])])
	var bytes := PackedByteArray()
	for value in values:
		var raw := value.to_utf8_buffer()
		bytes.append((raw.size() >> 24) & 0xff)
		bytes.append((raw.size() >> 16) & 0xff)
		bytes.append((raw.size() >> 8) & 0xff)
		bytes.append(raw.size() & 0xff)
		bytes.append_array(raw)
	return _codec.sha256_bytes(bytes).hex_encode()

func _prepare_authoring(definitions: Array[ContentDefinition], aliases: Array[ContentAliasValue], tombstones: Array[ContentTombstoneValue]) -> CatalogCompileResult:
	var id_namespace: Dictionary = {}
	for definition in definitions:
		if definition == null or not _stable_id_validator.is_valid(definition.id):
			return CatalogCompileResult.failure(&"CONTENT_VALIDATION_FAILED", &"id", definition.id if definition != null else &"")
		if id_namespace.has(definition.id): return CatalogCompileResult.failure(&"CONTENT_VALIDATION_FAILED", &"id.duplicate", definition.id)
		id_namespace[definition.id] = &"active"
	for alias in aliases:
		if id_namespace.has(alias.source_id): return CatalogCompileResult.failure(&"CONTENT_VALIDATION_FAILED", &"alias.source", alias.source_id)
		id_namespace[alias.source_id] = &"alias"
	for tombstone in tombstones:
		if id_namespace.has(tombstone.original_id): return CatalogCompileResult.failure(&"CONTENT_VALIDATION_FAILED", &"tombstone.original", tombstone.original_id)
		id_namespace[tombstone.original_id] = &"tombstone"
	var alias_targets: Dictionary = {}
	for alias in aliases: alias_targets[alias.source_id] = alias.target_id
	for alias in aliases:
		var visited: Dictionary = {}
		var cursor := alias.source_id
		while alias_targets.has(cursor):
			if visited.has(cursor): return CatalogCompileResult.failure(&"CONTENT_VALIDATION_FAILED", &"alias.cycle", alias.source_id)
			visited[cursor] = true
			cursor = alias_targets[cursor]
		if not id_namespace.has(cursor): return CatalogCompileResult.failure(&"CONTENT_VALIDATION_FAILED", &"alias.target", alias.source_id)
	return CatalogCompileResult.success(CatalogHandle.new("prepared", "", false))

func _selection_digest(selection: CatalogSelection) -> String:
	var values: Array[String] = [selection.content_version]
	for value in selection.root_enabled_content_ids: values.append(String(value))
	values.append(String(selection.economy_config_id))
	values.append(String(selection.combat_config_id))
	for value in selection.reward_table_ids: values.append(String(value))
	for value in selection.map_node_def_ids: values.append(String(value))
	for value in selection.challenge_unlock_def_ids: values.append(String(value))
	values.append(String(selection.meta_reward_table_id))
	var bytes := PackedByteArray()
	bytes.append_array("SEL2".to_ascii_buffer())
	for value in values:
		var raw := value.to_utf8_buffer()
		bytes.append((raw.size() >> 24) & 0xff)
		bytes.append((raw.size() >> 16) & 0xff)
		bytes.append((raw.size() >> 8) & 0xff)
		bytes.append(raw.size() & 0xff)
		bytes.append_array(raw)
	return _codec.sha256_bytes(bytes).hex_encode()

func _flatten_aliases(values: Array[ContentAliasValue]) -> Array[ContentAliasValue]:
	var targets: Dictionary = {}
	for value in values: targets[value.source_id] = value.target_id
	var result: Array[ContentAliasValue] = []
	for value in values:
		var terminal: StringName = value.target_id
		while targets.has(terminal): terminal = targets[terminal] as StringName
		result.append(ContentAliasValue.new(value.source_id, terminal))
	return result

func _entry_less(left: ContentEntryValue, right: ContentEntryValue) -> bool:
	var left_code := ContentCategory.code_for_name(left.category)
	var right_code := ContentCategory.code_for_name(right.category)
	return String(left.content_id) < String(right.content_id) if left_code == right_code else left_code < right_code

## manifest 的 alias／tombstone／pack_id 都寫進 codec 的 `canonical_set`,而
## `_is_canonical_set()` 要求「編碼後 bytes 嚴格遞增」。字串在 canonical 編碼裡是
## length-prefixed(tag + u32-be length + UTF-8),所以正確的順序是「先比 byte 長度、
## 再比 bytes」,不是字串字典序——兩者只在所有 id 等長時才一致。先前這裡用字典序,
## 正式 catalog 因為 alias／tombstone 皆為空而從未觸發;一旦宣告長度不同的 id
## (例:`meta.fixture` 12 bytes vs `commander.fixture` 17 bytes),manifest 編碼就會以
## `codec.value` 失敗。此處改用 canonical 順序,對既有(能通過編碼的)資料等價。
func _canonical_id_less(left: StringName, right: StringName) -> bool:
	var left_bytes := String(left).to_utf8_buffer()
	var right_bytes := String(right).to_utf8_buffer()
	if left_bytes.size() != right_bytes.size():
		return left_bytes.size() < right_bytes.size()
	for index in left_bytes.size():
		if left_bytes[index] != right_bytes[index]:
			return left_bytes[index] < right_bytes[index]
	return false

func _alias_less(left: ContentAliasValue, right: ContentAliasValue) -> bool:
	return _canonical_id_less(left.source_id, right.source_id)

func _tombstone_less(left: ContentTombstoneValue, right: ContentTombstoneValue) -> bool:
	return _canonical_id_less(left.original_id, right.original_id)

func _string_name_less(left: StringName, right: StringName) -> bool:
	return String(left) < String(right)
