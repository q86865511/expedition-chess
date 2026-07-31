class_name StableIdValidator
extends RefCounted

const PATTERN: String = "^[a-z][a-z0-9_]*(\\.[a-z][a-z0-9_]*)+$"

var _regex: RegEx

func _init() -> void:
	_regex = RegEx.new()
	var compile_error := _regex.compile(PATTERN)
	assert(compile_error == OK, "Stable ID regex must compile")

func validate(value: StringName, field_path: StringName = &"stable_id") -> StableIdValidationResult:
	var text := String(value)
	var match := _regex.search(text)
	if match == null or match.get_string() != text:
		return StableIdValidationResult.failure(field_path)
	return StableIdValidationResult.success(value)

func is_valid(value: StringName) -> bool:
	return validate(value).ok
