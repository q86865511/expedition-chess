class_name BattleSimulationError
extends RefCounted

const LIFECYCLE_INVALID: StringName = &"BATTLE_LIFECYCLE_INVALID"
const SETUP_INVALID: StringName = &"BATTLE_SETUP_INVALID"
const VERSION_TUPLE_UNSUPPORTED: StringName = &"BATTLE_VERSION_TUPLE_UNSUPPORTED"
const SETUP_HASH_MISMATCH: StringName = &"BATTLE_SETUP_HASH_MISMATCH"
const RNG_INVALID: StringName = &"BATTLE_RNG_INVALID"
const INVARIANT_FAILED: StringName = &"BATTLE_INVARIANT_FAILED"
const ENTITY_BUDGET_EXCEEDED: StringName = &"BATTLE_ENTITY_BUDGET_EXCEEDED"
const EFFECT_FAILED: StringName = &"BATTLE_EFFECT_FAILED"
const BUDGET_EXCEEDED: StringName = &"BATTLE_BUDGET_EXCEEDED"
const INTEGER_OVERFLOW: StringName = &"BATTLE_INTEGER_OVERFLOW"
const ENTITY_ID_COLLISION: StringName = &"BATTLE_ENTITY_ID_COLLISION"
const RESULT_FINALIZATION_FAILED: StringName = &"BATTLE_RESULT_FINALIZATION_FAILED"

var code: StringName
var field_path: StringName
var source_code: StringName

func _init(
	p_code: StringName,
	p_field_path: StringName = &"",
	p_source_code: StringName = &""
) -> void:
	code = p_code
	field_path = p_field_path
	source_code = p_source_code

func deep_clone() -> BattleSimulationError:
	return BattleSimulationError.new(code, field_path, source_code)
