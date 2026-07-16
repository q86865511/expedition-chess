class_name BattleRuleCatalogError
extends RefCounted

const INPUT_INVALID: StringName = &"BATTLE_CATALOG_INPUT_INVALID"
const RESOLVE_FAILED: StringName = &"BATTLE_CATALOG_RESOLVE_FAILED"
const CATEGORY_MISMATCH: StringName = &"BATTLE_CATALOG_CATEGORY_MISMATCH"
const PAYLOAD_INVALID: StringName = &"BATTLE_CATALOG_PAYLOAD_INVALID"
const REFERENCE_MISSING: StringName = &"BATTLE_CATALOG_REFERENCE_MISSING"
const CONFIG_MISSING: StringName = &"BATTLE_CATALOG_CONFIG_MISSING"

var code: StringName
var field_path: StringName
var source_id: OptionalStringNameValue
var diagnostic_values: Array[DiagnosticValue] = []

func _init(
	p_code: StringName,
	p_field_path: StringName = &"",
	p_source_id: StringName = &""
) -> void:
	code = p_code
	field_path = p_field_path
	source_id = OptionalStringNameValue.new(p_source_id) if not p_source_id.is_empty() else null

func deep_clone() -> BattleRuleCatalogError:
	return BattleRuleCatalogError.new(
		code,
		field_path,
		source_id.value if source_id != null else &""
	)
