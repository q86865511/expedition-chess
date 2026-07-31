class_name ContentGenerationMigrationTargetEntry
extends RefCounted

## Target generation 中「實際安裝」的單一 catalog entry:category 與其 canonical
## entry bytes 的 SHA-256。pack 的 `target_entry_digest` 必須逐筆對上本表,
## 否則 pack 可以宣稱任意 target(design.md:304-311)。

var category: StringName
var content_id: StringName
var entry_digest: String


func _init(
	p_category: StringName,
	p_content_id: StringName,
	p_entry_digest: String
) -> void:
	category = p_category
	content_id = p_content_id
	entry_digest = p_entry_digest


func deep_clone() -> ContentGenerationMigrationTargetEntry:
	return ContentGenerationMigrationTargetEntry.new(
		category, content_id, entry_digest
	)
