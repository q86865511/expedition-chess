class_name ContentAliasValue
extends RefCounted

var source_id: StringName
var target_id: StringName

func _init(p_source_id: StringName = &"", p_target_id: StringName = &"") -> void:
	source_id = p_source_id
	target_id = p_target_id

func deep_clone() -> ContentAliasValue:
	return ContentAliasValue.new(source_id, target_id)
