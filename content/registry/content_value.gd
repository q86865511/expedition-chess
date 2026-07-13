class_name ContentValue
extends RefCounted

enum Kind { BOOL, I32, U32, U64, STRING, STABLE_ID, ENUM, PATH, DIGEST, RECORD, LIST, SET, OPTIONAL, BYTES }

var kind: Kind
var bool_value: bool
var int_value: int
var string_value: String
var bytes_value: PackedByteArray
var record_type: int
var field_ids: PackedInt32Array
var children: Array[ContentValue]
var optional_present: bool

static func boolean(value: bool) -> ContentValue:
	var result := ContentValue.new()
	result.kind = Kind.BOOL
	result.bool_value = value
	return result

static func i32(value: int) -> ContentValue:
	var result := ContentValue.new()
	result.kind = Kind.I32
	result.int_value = value
	return result

static func u32(value: int) -> ContentValue:
	var result := ContentValue.new()
	result.kind = Kind.U32
	result.int_value = value
	return result

static func u64(value: int) -> ContentValue:
	var result := ContentValue.new()
	result.kind = Kind.U64
	result.int_value = value
	return result

static func text(value: String) -> ContentValue:
	return _string_kind(Kind.STRING, value)

static func stable_id(value: StringName) -> ContentValue:
	return _string_kind(Kind.STABLE_ID, String(value))

static func enum_value(value: StringName) -> ContentValue:
	return _string_kind(Kind.ENUM, String(value))

static func path(value: String) -> ContentValue:
	return _string_kind(Kind.PATH, value)

static func digest(value: PackedByteArray) -> ContentValue:
	var result := ContentValue.new()
	result.kind = Kind.DIGEST
	result.bytes_value = value.duplicate()
	return result

static func raw_bytes(value: PackedByteArray) -> ContentValue:
	var result := ContentValue.new()
	result.kind = Kind.BYTES
	result.bytes_value = value.duplicate()
	return result

static func record(type_id: int, ids: PackedInt32Array, values: Array[ContentValue]) -> ContentValue:
	var result := ContentValue.new()
	result.kind = Kind.RECORD
	result.record_type = type_id
	result.field_ids = ids.duplicate()
	result.children = _clone_values(values)
	return result

static func ordered_list(values: Array[ContentValue]) -> ContentValue:
	var result := ContentValue.new()
	result.kind = Kind.LIST
	result.children = _clone_values(values)
	return result

static func canonical_set(values: Array[ContentValue]) -> ContentValue:
	var result := ContentValue.new()
	result.kind = Kind.SET
	result.children = _clone_values(values)
	return result

static func optional(value: ContentValue) -> ContentValue:
	var result := ContentValue.new()
	result.kind = Kind.OPTIONAL
	result.optional_present = value != null
	if value != null:
		result.children = [value.deep_clone()]
	return result

static func _string_kind(value_kind: Kind, value: String) -> ContentValue:
	var result := ContentValue.new()
	result.kind = value_kind
	result.string_value = value
	return result

static func _clone_values(values: Array[ContentValue]) -> Array[ContentValue]:
	var result: Array[ContentValue] = []
	for value in values:
		result.append(value.deep_clone())
	return result

func deep_clone() -> ContentValue:
	var result := ContentValue.new()
	result.kind = kind
	result.bool_value = bool_value
	result.int_value = int_value
	result.string_value = string_value
	result.bytes_value = bytes_value.duplicate()
	result.record_type = record_type
	result.field_ids = field_ids.duplicate()
	result.children = _clone_values(children)
	result.optional_present = optional_present
	return result

func value_equals(other: ContentValue) -> bool:
	if other == null or kind != other.kind or bool_value != other.bool_value or int_value != other.int_value:
		return false
	if string_value != other.string_value or bytes_value != other.bytes_value or record_type != other.record_type:
		return false
	if field_ids != other.field_ids or optional_present != other.optional_present or children.size() != other.children.size():
		return false
	for index in children.size():
		if not children[index].value_equals(other.children[index]):
			return false
	return true
