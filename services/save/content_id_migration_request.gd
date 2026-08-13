class_name ContentIdMigrationRequest
extends RefCounted

var content_id: StringName
var accepted_categories: Array[StringName] = []
var required_for_active_run: bool
var field_path: StringName

func _init(
	p_content_id: StringName,
	p_accepted_categories: Array[StringName],
	p_required_for_active_run: bool,
	p_field_path: StringName
) -> void:
	content_id = p_content_id
	accepted_categories.assign(p_accepted_categories)
	required_for_active_run = p_required_for_active_run
	field_path = p_field_path

## 空的 accepted_categories 代表這個欄位不限定類別(沿用單值時代空字串的語意);
## 非空時只要 active／alias 解析出的 category 落在聯集內就算相容。
func accepts_category(category: StringName) -> bool:
	return accepted_categories.is_empty() or accepted_categories.has(category)

func deep_clone() -> ContentIdMigrationRequest:
	return ContentIdMigrationRequest.new(
		content_id, accepted_categories, required_for_active_run, field_path
	)
