class_name ProductionContentGenerationMigrationPortBuilder
extends RefCounted

## 把 `ProductionContentGenerationMigrations` 的宣告表,對「已安裝並釘選的 target
## generation」封裝成正式的 `ContentGenerationMigrationPortV2`(B3:production boot
## 先前完全沒有接這個 port,歷史 schema 3／codec 2 save 一律 PORT_UNCONFIGURED)。
##
## 封裝時只做兩件事:(1) 從安裝中的 catalog manifest entry index 取每個 target 的
## canonical entry digest;(2) 從安裝中的 localization catalog 重算 L10N2 digest。
## 兩者都是「target generation 實際安裝的內容」,不是猜測值;port 之後會用同一份
## 資料再驗一次,因此宣告表被竄改或內容改名時會 fail-closed 而不是默默放行。
##
## 已知限制(需要 build-time 產生 pinned manifest digest 常數才能根除):
## expected_target_manifest_digest 取自本次 boot 安裝的 pinned receipt,
## allowlist 因此是由同一份 pack 推導出來的,無法擋「pack 宣告表本身被改」;
## 真正的獨立 allowlist 需要把 target manifest digest 也寫成常數。

## 全有全無:任何一筆宣告無法對上安裝中的 target 就不發任何 pack,
## 讓 port 以 PACK_MISSING fail-closed,而不是放行一份殘缺的 mapping 表。
func build(
	registry: ContentRegistryService,
	receipt: PinnedCatalogBuildReceipt,
	localization_catalog: LocalizationCatalog
) -> ContentGenerationMigrationPortV2:
	var empty_packs: Array[ContentGenerationMigrationPackV2] = []
	var empty_allowlist: Array[ContentGenerationMigrationAllowlistEntryV2] = []
	if registry == null or receipt == null or localization_catalog == null:
		return ContentGenerationMigrationPortV2.new(
			empty_packs, empty_allowlist, {}
		)
	var target_entries := _target_entries(registry, receipt.manifest_digest)
	if target_entries.is_empty():
		push_warning(
			"content generation migration: target generation has no entry index"
		)
		return ContentGenerationMigrationPortV2.new(
			empty_packs, empty_allowlist, {}
		)
	var codec := ContentGenerationMigrationCodecV2.new()
	# 空 rows 也會產出合法的 L10N2 digest,所以「解析失敗」必須先於 digest 判斷:
	# 正式 catalog 一定有 key,rows 為空即代表載入或解析出問題。
	var localization_rows := _localization_rows(localization_catalog)
	if localization_rows.is_empty():
		push_warning(
			"content generation migration: installed localization catalog empty"
		)
		return ContentGenerationMigrationPortV2.new(
			empty_packs, empty_allowlist, {}
		)
	var localization_digest := codec.localization_digest(localization_rows)
	if localization_digest.is_empty():
		push_warning(
			"content generation migration: localization catalog digest failed"
		)
		return ContentGenerationMigrationPortV2.new(
			empty_packs, empty_allowlist, {}
		)
	var mappings := _mappings(target_entries)
	if mappings.is_empty():
		push_warning(
			"content generation migration: declared mapping target missing"
		)
		return ContentGenerationMigrationPortV2.new(
			empty_packs, empty_allowlist, {}
		)
	var packs: Array[ContentGenerationMigrationPackV2] = []
	var allowlist: Array[ContentGenerationMigrationAllowlistEntryV2] = []
	var generations := ProductionContentGenerationMigrations.source_generations()
	for generation in generations:
		var pack := ContentGenerationMigrationPackV2.new()
		pack.source_content_version = generation.content_version
		pack.target_content_version = receipt.content_version
		pack.source_manifest_digest = generation.manifest_digest
		pack.expected_target_manifest_digest = receipt.manifest_digest
		pack.mappings = _clone_mappings(mappings)
		pack.mapping_digest = codec.mapping_digest(pack.mappings)
		pack.localization_catalog_digest = localization_digest
		pack.pack_digest = codec.pack_digest(pack)
		if pack.pack_digest.is_empty():
			push_warning(
				"content generation migration: pack digest failed for %s"
				% generation.commit
			)
			return ContentGenerationMigrationPortV2.new(
				empty_packs, empty_allowlist, {}
			)
		packs.append(pack)
		allowlist.append(ContentGenerationMigrationAllowlistEntryV2.new(
			pack.source_content_version,
			pack.source_manifest_digest,
			pack.pack_digest
		))
	return ContentGenerationMigrationPortV2.new(
		packs,
		allowlist,
		{receipt.manifest_digest: receipt},
		{receipt.manifest_digest: target_entries},
		{receipt.manifest_digest: localization_digest}
	)


func _target_entries(
	registry: ContentRegistryService,
	manifest_digest: String
) -> Array[ContentGenerationMigrationTargetEntry]:
	var result: Array[ContentGenerationMigrationTargetEntry] = []
	for index: ContentEntryIndexValue in registry._entry_indexes_for_digest(
		manifest_digest
	):
		result.append(ContentGenerationMigrationTargetEntry.new(
			index.category, index.content_id, index.entry_digest.hex_encode()
		))
	return result


## 宣告表 → CGM2 entry。IDENTITY／ALIAS 的 target_entry_digest 一律取安裝中
## target entry 的 digest;target 不存在即整批放棄(回空陣列)。
func _mappings(
	target_entries: Array[ContentGenerationMigrationTargetEntry]
) -> Array[ContentGenerationMigrationEntryV2]:
	var digests_by_id: Dictionary = {}
	for entry: ContentGenerationMigrationTargetEntry in target_entries:
		digests_by_id[entry.content_id] = entry
	var result: Array[ContentGenerationMigrationEntryV2] = []
	var abandoned: Array[ContentGenerationMigrationEntryV2] = []
	var declarations := ProductionContentGenerationMigrations.mapping_declarations()
	for declaration in declarations:
		if declaration.mapping_kind \
			== ContentGenerationMigrationEntryV2.MappingKind.TOMBSTONE:
			result.append(ContentGenerationMigrationEntryV2.new(
				String(declaration.source_category),
				String(declaration.source_id),
				declaration.requirement,
				declaration.mapping_kind,
				false,
				"",
				""
			))
			continue
		if not digests_by_id.has(declaration.target_id):
			return abandoned
		var target: ContentGenerationMigrationTargetEntry = digests_by_id[
			declaration.target_id
		]
		if target.category != declaration.source_category:
			return abandoned
		result.append(ContentGenerationMigrationEntryV2.new(
			String(declaration.source_category),
			String(declaration.source_id),
			declaration.requirement,
			declaration.mapping_kind,
			true,
			String(declaration.target_id),
			target.entry_digest
		))
	return result


func _clone_mappings(
	mappings: Array[ContentGenerationMigrationEntryV2]
) -> Array[ContentGenerationMigrationEntryV2]:
	var result: Array[ContentGenerationMigrationEntryV2] = []
	for mapping: ContentGenerationMigrationEntryV2 in mappings:
		result.append(mapping.deep_clone())
	return result


## L10N2 的 row 來源固定是安裝中的 catalog(由 LocalizationCatalogLoader 依 CSV
## 規則 parse／validate 過),不另外讀檔或重新猜測。
func _localization_rows(
	catalog: LocalizationCatalog
) -> Array[PackedStringArray]:
	var rows: Array[PackedStringArray] = []
	var abandoned: Array[PackedStringArray] = []
	for key: StringName in catalog.keys_for_locale(catalog.default_locale()):
		var zh := catalog.resolve(&"zh_TW", key)
		var en := catalog.resolve(&"en", key)
		if not zh.ok or not en.ok:
			return abandoned
		var row := PackedStringArray()
		row.append(String(key))
		row.append(zh.value)
		row.append(en.value)
		rows.append(row)
	return rows
