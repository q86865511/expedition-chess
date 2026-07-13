class_name RngAlgorithms
extends RefCounted

const FNV_OFFSET_HEX: String = "cbf29ce484222325"
const FNV_PRIME_HEX: String = "00000100000001b3"
const SPLITMIX_GAMMA_HEX: String = "9e3779b97f4a7c15"
const SPLITMIX_MUL1_HEX: String = "bf58476d1ce4e5b9"
const SPLITMIX_MUL2_HEX: String = "94d049bb133111eb"

static func encode_named_tuple(stream_name: StringName, context_id: StringName) -> PackedByteArray:
	var output := PackedByteArray()
	_append_length_prefixed(output, String(stream_name).to_utf8_buffer())
	_append_length_prefixed(output, String(context_id).to_utf8_buffer())
	return output

static func fnv1a64(bytes: PackedByteArray) -> U64Bits:
	var hash := _u64(FNV_OFFSET_HEX)
	var prime := _u64(FNV_PRIME_HEX)
	for byte: int in bytes:
		var byte_value_result := U64Bits.from_u32(0, byte)
		assert(byte_value_result.ok)
		hash = hash.bit_xor(byte_value_result.value).multiply(prime)
	return hash

static func splitmix64(input: U64Bits) -> U64Bits:
	var z := input.add(_u64(SPLITMIX_GAMMA_HEX))
	var shifted := z.logical_shift_right(30)
	assert(shifted.ok)
	z = z.bit_xor(shifted.value).multiply(_u64(SPLITMIX_MUL1_HEX))
	shifted = z.logical_shift_right(27)
	assert(shifted.ok)
	z = z.bit_xor(shifted.value).multiply(_u64(SPLITMIX_MUL2_HEX))
	shifted = z.logical_shift_right(31)
	assert(shifted.ok)
	return z.bit_xor(shifted.value)

static func _append_length_prefixed(output: PackedByteArray, value: PackedByteArray) -> void:
	var length := value.size()
	output.append((length >> 24) & 0xff)
	output.append((length >> 16) & 0xff)
	output.append((length >> 8) & 0xff)
	output.append(length & 0xff)
	output.append_array(value)

static func _u64(value: String) -> U64Bits:
	var parsed := U64Bits.from_hex(value)
	assert(parsed.ok)
	return parsed.value
