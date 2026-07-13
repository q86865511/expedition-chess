class_name U64ParseResult
extends RefCounted

var ok: bool = false
var value: U64Bits = null
var error: U64ParseError = null

static func success(parsed: U64Bits) -> U64ParseResult:
	return U64ParseResult.new(true, parsed, null)

static func failure(path: StringName = &"") -> U64ParseResult:
	return U64ParseResult.new(false, null, U64ParseError.create(path))

func _init(p_ok: bool, p_value: U64Bits, p_error: U64ParseError) -> void:
	ResultInvariant.require(p_ok, p_error, p_value != null, p_value == null)
	ok = p_ok
	value = p_value
	error = p_error
