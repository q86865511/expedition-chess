class_name RuntimeKeyDecodeResult
extends RefCounted

var ok: bool = false
var tuple: RuntimeKeyTuple = null
var error: RuntimeKeyError = null

static func success(decoded: RuntimeKeyTuple) -> RuntimeKeyDecodeResult:
	return RuntimeKeyDecodeResult.new(true, decoded, null)

static func failure(error_code: StringName, path: StringName = &"") -> RuntimeKeyDecodeResult:
	return RuntimeKeyDecodeResult.new(
		false, null, RuntimeKeyError.create(error_code, path)
	)

func _init(
	p_ok: bool,
	p_tuple: RuntimeKeyTuple,
	p_error: RuntimeKeyError
) -> void:
	ResultInvariant.require(p_ok, p_error, p_tuple != null, p_tuple == null)
	ok = p_ok
	tuple = p_tuple
	error = p_error
