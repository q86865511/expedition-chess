class_name U64CreateResult
extends RefCounted

var ok: bool = false
var value: U64Bits = null
var error: U64CreateError = null

static func success(created: U64Bits) -> U64CreateResult:
	return U64CreateResult.new(true, created, null)

static func failure(path: StringName = &"") -> U64CreateResult:
	return U64CreateResult.new(false, null, U64CreateError.create(path))

func _init(p_ok: bool, p_value: U64Bits, p_error: U64CreateError) -> void:
	ResultInvariant.require(p_ok, p_error, p_value != null, p_value == null)
	ok = p_ok
	value = p_value
	error = p_error
