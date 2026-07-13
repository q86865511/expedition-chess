class_name BattleCodecError
extends RefCounted

var code: StringName = &"BATTLE_CODEC_INVALID"
var field_path: StringName = &""
var source_id: StringName = &""

static func create(error_code: StringName = &"BATTLE_CODEC_INVALID", path: StringName = &"") -> BattleCodecError:
	var value := BattleCodecError.new()
	value.code = error_code
	value.field_path = path
	return value
