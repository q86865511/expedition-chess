class_name UnitMergeError
extends RefCounted

const INVALID_INPUT: StringName = &"UNIT_MERGE_INPUT_INVALID"
const COPY_CONSERVATION: StringName = &"UNIT_MERGE_COPY_CONSERVATION_FAILED"
const ITEM_CONSERVATION: StringName = &"UNIT_MERGE_ITEM_CONSERVATION_FAILED"
const EQUIPMENT_BINDING: StringName = &"UNIT_MERGE_EQUIPMENT_BINDING_INVALID"
const EQUIPMENT_RULE_MISSING: StringName = &"UNIT_MERGE_EQUIPMENT_RULE_MISSING"

var code: StringName
var field_path: StringName

func _init(p_code: StringName, p_field_path: StringName) -> void:
	code = p_code
	field_path = p_field_path

func deep_clone() -> UnitMergeError:
	return UnitMergeError.new(code, field_path)
