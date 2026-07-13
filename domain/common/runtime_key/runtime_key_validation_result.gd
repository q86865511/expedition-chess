class_name RuntimeKeyValidationResult
extends RefCounted

var ok: bool
var error: RuntimeKeyError

static func success() -> RuntimeKeyValidationResult:
	return RuntimeKeyValidationResult.new(true, null)

static func failure(p_error: RuntimeKeyError) -> RuntimeKeyValidationResult:
	return RuntimeKeyValidationResult.new(false, p_error)

func _init(p_ok: bool, p_error: RuntimeKeyError) -> void:
	ResultInvariant.require(p_ok, p_error, true, true)
	ok = p_ok
	error = p_error if p_error != null else null
