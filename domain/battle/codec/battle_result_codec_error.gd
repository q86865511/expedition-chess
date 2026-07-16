class_name BattleResultCodecError
extends RefCounted

const INVALID: StringName = &"BATTLE_RESULT_INVALID"
const VERSION_UNSUPPORTED: StringName = &"BATTLE_RESULT_VERSION_UNSUPPORTED"
const HASH_MISMATCH: StringName = &"BATTLE_RESULT_HASH_MISMATCH"
const CANONICAL_INVALID: StringName = &"BATTLE_RESULT_CANONICAL_INVALID"
const TRANSCRIPT_INVALID: StringName = &"BATTLE_RESULT_TRANSCRIPT_INVALID"
const TERMINAL_EVENT_INVALID: StringName = &"BATTLE_RESULT_TERMINAL_EVENT_INVALID"
const PROPOSAL_CONFLICT: StringName = &"BATTLE_RESULT_PROPOSAL_CONFLICT"

var code: StringName
var field_path: StringName

func _init(p_code: StringName, p_field_path: StringName = &"") -> void:
	code = p_code
	field_path = p_field_path

func deep_clone() -> BattleResultCodecError:
	return BattleResultCodecError.new(code, field_path)
