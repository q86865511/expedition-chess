class_name BattleEventCodecError
extends RefCounted

const INVALID: StringName = &"BATTLE_EVENT_INVALID"
const VERSION_UNSUPPORTED: StringName = &"BATTLE_EVENT_VERSION_UNSUPPORTED"
const TYPE_UNKNOWN: StringName = &"BATTLE_EVENT_TYPE_UNKNOWN"
const PAYLOAD_INVALID: StringName = &"BATTLE_EVENT_PAYLOAD_INVALID"
const CANONICAL_INVALID: StringName = &"BATTLE_EVENT_CANONICAL_INVALID"

var code: StringName
var field_path: StringName

func _init(p_code: StringName, p_field_path: StringName = &"") -> void:
	code = p_code
	field_path = p_field_path

func deep_clone() -> BattleEventCodecError:
	return BattleEventCodecError.new(code, field_path)
