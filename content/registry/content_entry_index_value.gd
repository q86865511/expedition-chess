class_name ContentEntryIndexValue
extends RefCounted

var category: StringName
var content_id: StringName
var resource_schema_version: int
var entry_digest: PackedByteArray

func _init(p_category: StringName = &"", p_id: StringName = &"", p_schema: int = 1, p_digest: PackedByteArray = PackedByteArray()) -> void:
	category = p_category
	content_id = p_id
	resource_schema_version = p_schema
	entry_digest = p_digest.duplicate()

func deep_clone() -> ContentEntryIndexValue:
	return ContentEntryIndexValue.new(category, content_id, resource_schema_version, entry_digest)
