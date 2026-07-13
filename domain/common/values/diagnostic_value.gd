class_name DiagnosticValue
extends RefCounted

enum ValueKind { STRING, INT, U64 }

var key: StringName
var value_kind: ValueKind
var string_value: OptionalStringValue
var int_value: OptionalIntValue
var u64_value: U64Bits

static func from_string(p_key: StringName, p_value: String) -> DiagnosticValue:
	return DiagnosticValue.new(p_key, ValueKind.STRING, OptionalStringValue.new(p_value), null, null)

static func from_int(p_key: StringName, p_value: int) -> DiagnosticValue:
	return DiagnosticValue.new(p_key, ValueKind.INT, null, OptionalIntValue.new(p_value), null)

static func from_u64(p_key: StringName, p_value: U64Bits) -> DiagnosticValue:
	return DiagnosticValue.new(p_key, ValueKind.U64, null, null, p_value.deep_clone())

func _init(
	p_key: StringName,
	p_value_kind: ValueKind,
	p_string_value: OptionalStringValue,
	p_int_value: OptionalIntValue,
	p_u64_value: U64Bits
) -> void:
	key = p_key
	value_kind = p_value_kind
	string_value = p_string_value
	int_value = p_int_value
	u64_value = p_u64_value

func deep_clone() -> DiagnosticValue:
	return DiagnosticValue.new(
		key,
		value_kind,
		string_value.deep_clone() if string_value != null else null,
		int_value.deep_clone() if int_value != null else null,
		u64_value.deep_clone() if u64_value != null else null
	)
