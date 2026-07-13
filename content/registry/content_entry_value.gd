class_name ContentEntryValue
extends RefCounted

var category: StringName
var content_id: StringName
var resource_schema_version: int
var payload: ContentValue

func _init(p_category: StringName = &"", p_id: StringName = &"", p_schema: int = 1, p_payload: ContentValue = null) -> void:
	category = p_category
	content_id = p_id
	resource_schema_version = p_schema
	payload = p_payload.deep_clone() if p_payload != null else null

func deep_clone() -> ContentEntryValue:
	return ContentEntryValue.new(category, content_id, resource_schema_version, payload)
