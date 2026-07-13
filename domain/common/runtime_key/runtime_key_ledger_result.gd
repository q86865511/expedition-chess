class_name RuntimeKeyLedgerResult
extends RefCounted

var ok: bool = false
var error: RuntimeKeyError = null

static func success() -> RuntimeKeyLedgerResult:
	return RuntimeKeyLedgerResult.new(true, null)

static func failure(code: StringName, path: StringName = &"") -> RuntimeKeyLedgerResult:
	return RuntimeKeyLedgerResult.new(false, RuntimeKeyError.create(code, path))

func _init(p_ok: bool, p_error: RuntimeKeyError) -> void:
	ResultInvariant.require(p_ok, p_error, true, true)
	ok = p_ok
	error = p_error
