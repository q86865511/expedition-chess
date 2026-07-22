class_name MapGenerationError
extends RefCounted

const INPUT_INVALID: StringName = &"MAP_GENERATION_INPUT_INVALID"
const RNG_FAILED: StringName = &"MAP_GENERATION_RNG_FAILED"
const RULE_MISSING: StringName = &"MAP_GENERATION_RULE_MISSING"
const KEY_FAILED: StringName = &"MAP_GENERATION_KEY_FAILED"
const DIGEST_FAILED: StringName = &"MAP_GENERATION_DIGEST_FAILED"

var code: StringName
var field_path: StringName

func _init(p_code: StringName, p_field_path: StringName) -> void:
	code = p_code
	field_path = p_field_path

func deep_clone() -> MapGenerationError:
	return MapGenerationError.new(code, field_path)
