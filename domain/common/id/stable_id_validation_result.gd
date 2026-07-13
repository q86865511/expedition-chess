class_name StableIdValidationResult
extends RefCounted

var ok: bool = false
var value: StringName = &""
var error: StableIdError = null

static func success(stable_id: StringName) -> StableIdValidationResult:
	return StableIdValidationResult.new(true, stable_id, null)

static func failure(path: StringName = &"stable_id") -> StableIdValidationResult:
	return StableIdValidationResult.new(false, &"", StableIdError.create(path))

func _init(
	p_ok: bool,
	p_value: StringName,
	p_error: StableIdError
) -> void:
	ResultInvariant.require(
		p_ok, p_error, not p_value.is_empty(), p_value.is_empty()
	)
	ok = p_ok
	value = p_value
	error = p_error
