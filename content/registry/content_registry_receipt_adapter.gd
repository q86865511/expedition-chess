class_name ContentRegistryReceiptAdapter
extends PinnedCatalogReceiptPort

var _registry: ContentRegistryService

func _init(registry: ContentRegistryService) -> void:
	_registry = registry

func compile_or_lookup(probe: ContentSnapshotProbe) -> PinnedCatalogReceiptResult:
	if _registry == null or probe == null:
		return _failure(PinnedCatalogReceiptError.SELECTION_INVALID, &"run.content_snapshot")
	var existing := _registry._receipt_for_digest(probe.manifest_digest)
	if existing != null:
		if _receipt_matches_probe(existing, probe):
			return PinnedCatalogReceiptResult.success(existing)
		return _failure(PinnedCatalogReceiptError.MANIFEST_MISMATCH, &"run.content_snapshot.manifest_digest")
	var result := _registry.rebuild_from_probe(probe)
	if result.ok and result.receipt != null:
		return PinnedCatalogReceiptResult.success(result.receipt)
	var migrated := _compile_migrated_probe(probe)
	if migrated.ok and migrated.receipt != null:
		return PinnedCatalogReceiptResult.success(migrated.receipt)
	if migrated.error != null:
		result = migrated
	var code := PinnedCatalogReceiptError.COMPILE_FAILED
	if result.error != null:
		match result.error.code:
			&"PINNED_CATALOG_PACK_MISSING": code = PinnedCatalogReceiptError.PACK_MISSING
			&"PINNED_CATALOG_SELECTION_INVALID": code = PinnedCatalogReceiptError.SELECTION_INVALID
			&"PINNED_CATALOG_REFERENCE_MISSING": code = PinnedCatalogReceiptError.REFERENCE_MISSING
			&"PINNED_CATALOG_MANIFEST_MISMATCH": code = PinnedCatalogReceiptError.MANIFEST_MISMATCH
	return _failure(code, &"run.content_snapshot")

func _compile_migrated_probe(probe: ContentSnapshotProbe) -> CatalogCompileResult:
	var latest := _registry.latest_catalog_handle()
	if not latest.ok:
		return CatalogCompileResult.failure(&"PINNED_CATALOG_COMPILE_FAILED", &"latest")
	var changed := false
	var enabled: Array[StringName] = []
	for content_id in probe.enabled_content_ids:
		var mapped := _map_required_id(content_id, &"")
		if mapped.kind == ContentMigrationLookup.Kind.MISSING or mapped.kind == ContentMigrationLookup.Kind.TOMBSTONE:
			return CatalogCompileResult.failure(&"PINNED_CATALOG_REFERENCE_MISSING", &"enabled_content_ids", content_id)
		enabled.append(mapped.resolved_id)
		changed = changed or mapped.resolved_id != content_id
	var economy := _map_required_id(probe.economy_config_id, &"economy_config")
	var meta := _map_required_id(probe.meta_reward_table_id, &"meta_reward_table")
	if economy.kind in [ContentMigrationLookup.Kind.MISSING, ContentMigrationLookup.Kind.TOMBSTONE]:
		return CatalogCompileResult.failure(&"PINNED_CATALOG_REFERENCE_MISSING", &"economy_config_id", probe.economy_config_id)
	if meta.kind in [ContentMigrationLookup.Kind.MISSING, ContentMigrationLookup.Kind.TOMBSTONE]:
		return CatalogCompileResult.failure(&"PINNED_CATALOG_REFERENCE_MISSING", &"meta_reward_table_id", probe.meta_reward_table_id)
	changed = changed or economy.resolved_id != probe.economy_config_id or meta.resolved_id != probe.meta_reward_table_id
	var rewards_result := _map_required_ids(probe.reward_table_ids, &"reward_table")
	var maps_result := _map_required_ids(probe.map_node_def_ids, &"map_node")
	var challenges_result := _map_required_ids(probe.challenge_unlock_def_ids, &"unlock")
	if rewards_result.is_empty() and not probe.reward_table_ids.is_empty(): return CatalogCompileResult.failure(&"PINNED_CATALOG_REFERENCE_MISSING", &"reward_table_ids")
	if maps_result.is_empty() and not probe.map_node_def_ids.is_empty(): return CatalogCompileResult.failure(&"PINNED_CATALOG_REFERENCE_MISSING", &"map_node_def_ids")
	if challenges_result.is_empty() and not probe.challenge_unlock_def_ids.is_empty(): return CatalogCompileResult.failure(&"PINNED_CATALOG_REFERENCE_MISSING", &"challenge_unlock_def_ids")
	changed = changed or rewards_result != probe.reward_table_ids or maps_result != probe.map_node_def_ids or challenges_result != probe.challenge_unlock_def_ids
	if not changed:
		return CatalogCompileResult.failure(&"PINNED_CATALOG_MANIFEST_MISMATCH", &"manifest_digest")
	_sort_unique(enabled)
	var selection := CatalogSelection.new(latest.value.content_version, enabled, economy.resolved_id,
		rewards_result, maps_result, challenges_result, meta.resolved_id)
	return _registry.compile_pinned_generation(selection)

func _map_required_ids(values: Array[StringName], expected_category: StringName) -> Array[StringName]:
	var result: Array[StringName] = []
	for content_id in values:
		var mapped := _map_required_id(content_id, expected_category)
		if mapped.kind in [ContentMigrationLookup.Kind.MISSING, ContentMigrationLookup.Kind.TOMBSTONE]: return []
		result.append(mapped.resolved_id)
	_sort_unique(result)
	return result

func _map_required_id(content_id: StringName, expected_category: StringName) -> ContentMigrationLookup:
	var lookup := _registry._migration_lookup(content_id)
	if lookup.kind in [ContentMigrationLookup.Kind.ACTIVE, ContentMigrationLookup.Kind.ALIAS]:
		if expected_category.is_empty() or lookup.category == expected_category: return lookup
	return ContentMigrationLookup.missing()

func _sort_unique(values: Array[StringName]) -> void:
	values.sort_custom(_string_name_less)
	var index := values.size() - 1
	while index > 0:
		if values[index] == values[index - 1]: values.remove_at(index)
		index -= 1

func _string_name_less(left: StringName, right: StringName) -> bool:
	return String(left) < String(right)

func _receipt_matches_probe(receipt: PinnedCatalogBuildReceipt, probe: ContentSnapshotProbe) -> bool:
	return receipt.content_version == probe.content_version \
		and receipt.active_entry_ids == probe.enabled_content_ids \
		and receipt.economy_config_id == probe.economy_config_id \
		and receipt.reward_table_ids == probe.reward_table_ids \
		and receipt.map_node_def_ids == probe.map_node_def_ids \
		and receipt.challenge_unlock_def_ids == probe.challenge_unlock_def_ids \
		and receipt.meta_reward_table_id == probe.meta_reward_table_id \
		and receipt.manifest_digest == probe.manifest_digest

func _failure(code: StringName, path: StringName) -> PinnedCatalogReceiptResult:
	return PinnedCatalogReceiptResult.failure(PinnedCatalogReceiptError.new(code, path))
