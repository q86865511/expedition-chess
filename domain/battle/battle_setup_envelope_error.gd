class_name BattleSetupEnvelopeError
extends RefCounted

const INPUT_INVALID: StringName = &"BATTLE_SETUP_ENVELOPE_INPUT_INVALID"
const HASH_MISMATCH: StringName = &"BATTLE_SETUP_ENVELOPE_HASH_MISMATCH"
const RNG_MISMATCH: StringName = &"BATTLE_SETUP_ENVELOPE_RNG_MISMATCH"
const DIGEST_MISMATCH: StringName = &"BATTLE_SETUP_ENVELOPE_DIGEST_MISMATCH"

var code: StringName
var field_path: StringName
var source_id: OptionalStringNameValue
var diagnostic_values: Array[DiagnosticValue] = []

func _init(p_code: StringName, p_path: StringName = &"") -> void:
	code = p_code
	field_path = p_path
	source_id = null

func deep_clone() -> BattleSetupEnvelopeError:
	return BattleSetupEnvelopeError.new(code, field_path)
