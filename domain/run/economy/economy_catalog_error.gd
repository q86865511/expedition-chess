class_name EconomyCatalogError
extends RefCounted

const INPUT_INVALID: StringName = &"ECONOMY_CATALOG_INPUT_INVALID"
const RESOLVE_FAILED: StringName = &"ECONOMY_CATALOG_RESOLVE_FAILED"
const CATEGORY_MISMATCH: StringName = &"ECONOMY_CATALOG_CATEGORY_MISMATCH"
const PAYLOAD_INVALID: StringName = &"ECONOMY_CATALOG_PAYLOAD_INVALID"
const CONFIG_INVALID: StringName = &"ECONOMY_CATALOG_CONFIG_INVALID"
const MAP_KIND_MISSING: StringName = &"ECONOMY_CATALOG_MAP_KIND_MISSING"

var code: StringName
var field_path: StringName
var source_id: StringName

func _init(p_code: StringName, p_field_path: StringName, p_source_id: StringName = &"") -> void:
	code = p_code
	field_path = p_field_path
	source_id = p_source_id

func deep_clone() -> EconomyCatalogError:
	return EconomyCatalogError.new(code, field_path, source_id)
