class_name NodeEntryError
extends RefCounted

const INPUT_INVALID: StringName = &"NODE_ENTRY_INPUT_INVALID"
const GENERATION_MISMATCH: StringName = &"NODE_ENTRY_CATALOG_GENERATION_MISMATCH"
const PHASE_INVALID: StringName = &"NODE_ENTRY_PHASE_INVALID"
const RESOLUTION_INVALID: StringName = &"NODE_ENTRY_RESOLUTION_INVALID"
const NODE_MISSING: StringName = &"NODE_ENTRY_NODE_MISSING"
const NODE_UNREACHABLE: StringName = &"NODE_ENTRY_NODE_UNREACHABLE"
const NODE_COMPLETED: StringName = &"NODE_ENTRY_NODE_COMPLETED"
const SHOP_LEAK: StringName = &"NODE_ENTRY_SHOP_LEAK"
const ENCOUNTER_CATALOG_MISSING: StringName = &"NODE_ENTRY_ENCOUNTER_CATALOG_MISSING"
const ENCOUNTER_COMPILE_FAILED: StringName = &"NODE_ENTRY_ENCOUNTER_COMPILE_FAILED"

var code: StringName
var field_path: StringName

func _init(p_code: StringName, p_field_path: StringName) -> void:
	code = p_code
	field_path = p_field_path

func deep_clone() -> NodeEntryError:
	return NodeEntryError.new(code, field_path)
