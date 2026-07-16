class_name EffectResolverError
extends RefCounted

const INPUT_INVALID: StringName = &"EFFECT_INPUT_INVALID"
const TRIGGER_UNKNOWN: StringName = &"EFFECT_TRIGGER_UNKNOWN"
const TRIGGER_MISMATCH: StringName = &"EFFECT_TRIGGER_MISMATCH"
const CONDITION_UNKNOWN: StringName = &"EFFECT_CONDITION_UNKNOWN"
const CONDITION_INVALID: StringName = &"EFFECT_CONDITION_INVALID"
const OPERATION_UNKNOWN: StringName = &"EFFECT_OPERATION_UNKNOWN"
const OPERATION_INVALID: StringName = &"EFFECT_OPERATION_INVALID"
const STACKING_UNKNOWN: StringName = &"EFFECT_STACKING_UNKNOWN"
const SOURCE_INVALID: StringName = &"EFFECT_SOURCE_INVALID"
const TARGET_INVALID: StringName = &"EFFECT_TARGET_INVALID"
const STATUS_MARKER_MISSING: StringName = &"EFFECT_STATUS_MARKER_MISSING"
const SUMMON_TEMPLATE_MISSING: StringName = &"EFFECT_SUMMON_TEMPLATE_MISSING"
const BUDGET_EXCEEDED: StringName = &"EFFECT_BUDGET_EXCEEDED"
const INTEGER_OVERFLOW: StringName = &"EFFECT_INTEGER_OVERFLOW"
const RUN_PROPOSAL_SOURCE_INVALID: StringName = &"RUN_PROPOSAL_SOURCE_INVALID"

var code: StringName
var field_path: StringName

func _init(p_code: StringName, p_field_path: StringName = &"") -> void:
	code = p_code
	field_path = p_field_path

func deep_clone() -> EffectResolverError:
	return EffectResolverError.new(code, field_path)
