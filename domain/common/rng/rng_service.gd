class_name RngService
extends RefCounted

const DERIVE_XOR_HEX: String = "da3e39cb94b95bdb"
const STREAM_UNKNOWN: StringName = &"RNG_STREAM_UNKNOWN"
const CONTEXT_EMPTY: StringName = &"RNG_CONTEXT_EMPTY"

const STREAMS: Array[StringName] = [&"map", &"shop", &"reward", &"combat"]

func derive_stream(run_seed: U64Bits, stream_name: StringName, context_id: StringName) -> RngDeriveResult:
	if run_seed == null:
		return RngDeriveResult.failure(&"RNG_SNAPSHOT_INVALID", &"run_seed")
	if not STREAMS.has(stream_name):
		return RngDeriveResult.failure(STREAM_UNKNOWN, &"stream_name")
	if String(context_id).is_empty():
		return RngDeriveResult.failure(CONTEXT_EMPTY, &"context_id")
	var tuple_bytes := RngAlgorithms.encode_named_tuple(stream_name, context_id)
	var name_hash := RngAlgorithms.fnv1a64(tuple_bytes)
	var init_state := RngAlgorithms.splitmix64(run_seed.bit_xor(name_hash))
	var derive_xor := U64Bits.from_hex(DERIVE_XOR_HEX)
	assert(derive_xor.ok)
	var init_seq := RngAlgorithms.splitmix64(init_state.bit_xor(derive_xor.value))
	var seeded := Pcg32Stream.seed(init_state, init_seq)
	if not seeded.ok:
		return RngDeriveResult.failure(seeded.error.code, seeded.error.field_path)
	return RngDeriveResult.success(seeded.stream)
