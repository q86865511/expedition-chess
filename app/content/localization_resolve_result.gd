class_name LocalizationResolveResult
extends RefCounted

var ok: bool
var value: String
var error_code: StringName
var error: LocalizationResolveError


static func success(p_value: String) -> LocalizationResolveResult:
	return LocalizationResolveResult.new(true, null, p_value, &"")


static func failure(p_error_code: StringName) -> LocalizationResolveResult:
	return LocalizationResolveResult.new(
		false,
		LocalizationResolveError.new(p_error_code),
		"",
		p_error_code
	)


func _init(
	p_ok: bool,
	p_error: LocalizationResolveError,
	p_value: String,
	p_error_code: StringName
) -> void:
	ResultInvariant.require(
		p_ok,
		p_error,
		not p_value.is_empty() and p_error_code.is_empty(),
		p_value.is_empty()
			and not p_error_code.is_empty()
			and p_error.code == p_error_code
	)
	ok = p_ok
	value = p_value
	error_code = p_error_code
	error = p_error
