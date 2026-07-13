class_name U64ShiftResult
extends RefCounted

var ok: bool = false
var value: U64Bits = null
var error: U64ShiftError = null

static func success(shifted: U64Bits) -> U64ShiftResult:
	return U64ShiftResult.new(true, shifted, null)

static func failure() -> U64ShiftResult:
	return U64ShiftResult.new(false, null, U64ShiftError.create())

func _init(p_ok: bool, p_value: U64Bits, p_error: U64ShiftError) -> void:
	ResultInvariant.require(p_ok, p_error, p_value != null, p_value == null)
	ok = p_ok
	value = p_value
	error = p_error
