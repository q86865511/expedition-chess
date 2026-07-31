class_name ContentGenerationMigrationPlan
extends RefCounted

## 通過驗證的 CGM2 pack 所決定的「套用計畫」:migration 成功後,SaveMigrationRegistry
## 依此把 raw run 內的每個引用面改寫成 target id(ALIAS)或移除(OPTIONAL TOMBSTONE)。
## 內容就是 pack 的 mapping 表本身,查表語意與 port 驗證時完全相同(exact category
## 命中;category 未知時只接受唯一一筆同 id 的 mapping),避免驗證與套用兩套規則。

var mappings: Array[ContentGenerationMigrationEntryV2] = []


func _init(p_mappings: Array[ContentGenerationMigrationEntryV2]) -> void:
	for mapping: ContentGenerationMigrationEntryV2 in p_mappings:
		mappings.append(mapping.deep_clone())


func try_resolve(
	reference: ContentGenerationMigrationReference
) -> ContentGenerationMigrationEntryV2:
	if reference == null:
		return null
	var found: ContentGenerationMigrationEntryV2 = null
	for mapping: ContentGenerationMigrationEntryV2 in mappings:
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


func deep_clone() -> ContentGenerationMigrationPlan:
	return ContentGenerationMigrationPlan.new(mappings)
