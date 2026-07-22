class_name ExpeditionActionError
extends RefCounted

const INPUT_INVALID: StringName = &"EXPEDITION_INPUT_INVALID"
const PHASE_INVALID: StringName = &"EXPEDITION_PHASE_INVALID"
const RESOLUTION_INVALID: StringName = &"EXPEDITION_RESOLUTION_INVALID"
const GENERATION_MISMATCH: StringName = &"EXPEDITION_GENERATION_MISMATCH"
const NODE_INVALID: StringName = &"EXPEDITION_NODE_INVALID"
const RESULT_INVALID: StringName = &"EXPEDITION_RESULT_INVALID"
const REWARD_CONFIG_INVALID: StringName = &"EXPEDITION_REWARD_CONFIG_INVALID"
const REWARD_CHOICE_INVALID: StringName = &"EXPEDITION_REWARD_CHOICE_INVALID"
const REWARD_PHASE_INVALID: StringName = &"EXPEDITION_REWARD_PHASE_INVALID"
const RESERVATION_INVALID: StringName = &"EXPEDITION_RESERVATION_INVALID"
const UNIT_POOL_INVALID: StringName = &"EXPEDITION_UNIT_POOL_INVALID"
const ROSTER_FULL: StringName = &"EXPEDITION_ROSTER_FULL"
const ITEM_INVALID: StringName = &"EXPEDITION_ITEM_INVALID"
const RELIC_INVALID: StringName = &"EXPEDITION_RELIC_INVALID"
const RNG_FAILED: StringName = &"EXPEDITION_RNG_FAILED"
const KEY_FAILED: StringName = &"EXPEDITION_KEY_FAILED"
const SERIAL_EXHAUSTED: StringName = &"EXPEDITION_SERIAL_EXHAUSTED"
const DIGEST_FAILED: StringName = &"EXPEDITION_DIGEST_FAILED"
const MERGE_FAILED: StringName = &"EXPEDITION_MERGE_FAILED"

var code: StringName
var field_path: StringName

func _init(p_code: StringName, p_field_path: StringName) -> void:
	code = p_code
	field_path = p_field_path

func deep_clone() -> ExpeditionActionError:
	return ExpeditionActionError.new(code, field_path)
