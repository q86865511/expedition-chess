class_name ContentTombstoneValue
extends RefCounted

var original_id: StringName
var category: StringName
var policy: StringName
var replacement_id: StringName
var has_replacement: bool
var reason_code: StringName

func _init(p_original_id: StringName = &"", p_category: StringName = &"", p_policy: StringName = &"safe_absent", p_replacement_id: StringName = &"", p_has_replacement: bool = false, p_reason: StringName = &"") -> void:
	original_id = p_original_id
	category = p_category
	policy = p_policy
	replacement_id = p_replacement_id
	has_replacement = p_has_replacement
	reason_code = p_reason

func deep_clone() -> ContentTombstoneValue:
	return ContentTombstoneValue.new(original_id, category, policy, replacement_id, has_replacement, reason_code)
