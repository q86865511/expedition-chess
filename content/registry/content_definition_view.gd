class_name ContentDefinitionView
extends RefCounted

var manifest_digest: String
var category: StringName
var content_id: StringName
var resource_schema_version: int
var payload: ContentValue

func _init(p_digest: String = "", p_entry: ContentEntryValue = null) -> void:
	manifest_digest = p_digest
	if p_entry != null:
		category = p_entry.category
		content_id = p_entry.content_id
		resource_schema_version = p_entry.resource_schema_version
		payload = p_entry.payload.deep_clone()

func deep_clone() -> ContentDefinitionView:
	var entry := ContentEntryValue.new(category, content_id, resource_schema_version, payload)
	return ContentDefinitionView.new(manifest_digest, entry)
