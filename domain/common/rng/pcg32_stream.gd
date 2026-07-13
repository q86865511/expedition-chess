class_name Pcg32Stream
extends RefCounted

const PCG_MULT_HEX: String = "5851f42d4c957f2d"
const INVALID_BOUND: StringName = &"RNG_BOUND_INVALID"

var _state: U64Bits = U64Bits.zero()
var _inc: U64Bits = U64Bits.one()
var _counter: U64Bits = U64Bits.zero()

static func seed(init_state: U64Bits, init_seq: U64Bits) -> PcgSeedResult:
	if init_state == null or init_seq == null:
		return PcgSeedResult.failure(&"RNG_SNAPSHOT_INVALID", &"seed")
	var stream := Pcg32Stream.new()
	var shifted := init_seq.shift_left(1)
	assert(shifted.ok)
	stream._inc = shifted.value.bit_or(U64Bits.one())
	stream._state = U64Bits.zero()
	stream._counter = U64Bits.zero()
	stream._next_raw(false)
	stream._state = stream._state.add(init_state)
	stream._next_raw(false)
	stream._counter = U64Bits.zero()
	return PcgSeedResult.success(stream)

static func from_snapshot(saved: RngSnapshot) -> PcgSeedResult:
	if saved == null:
		return PcgSeedResult.failure(&"RNG_SNAPSHOT_INVALID", &"snapshot")
	var validated := RngSnapshot.create(saved.rng_version, saved.state, saved.inc, saved.counter)
	if not validated.ok:
		return PcgSeedResult.failure(validated.error.code, validated.error.field_path)
	var stream := Pcg32Stream.new()
	stream._state = saved.state.deep_clone()
	stream._inc = saved.inc.deep_clone()
	stream._counter = saved.counter.deep_clone()
	return PcgSeedResult.success(stream)

func next_u32() -> RngDrawResult:
	var value := _next_raw(true)
	return RngDrawResult.success(value, snapshot())

func next_bounded(bound: int) -> RngDrawResult:
	if bound < 1 or bound > 4294967296:
		return RngDrawResult.failure(INVALID_BOUND, &"bound")
	if bound == 4294967296:
		return next_u32()
	var threshold := (4294967296 - bound) % bound
	while true:
		var raw := _next_raw(true)
		if raw >= threshold:
			return RngDrawResult.success(raw % bound, snapshot())
	return RngDrawResult.failure(INVALID_BOUND, &"bound")

func next_basis_points() -> RngDrawResult:
	return next_bounded(10000)

func snapshot() -> RngSnapshot:
	return RngSnapshot._create_unchecked(1, _state, _inc, _counter)

func deep_clone() -> Pcg32Stream:
	var restored := from_snapshot(snapshot())
	assert(restored.ok)
	return restored.stream

func _next_raw(count_public: bool) -> int:
	var old := _state
	var multiplier_result := U64Bits.from_hex(PCG_MULT_HEX)
	assert(multiplier_result.ok)
	_state = old.multiply(multiplier_result.value).add(_inc)
	var shifted_18 := old.logical_shift_right(18)
	assert(shifted_18.ok)
	var mixed := shifted_18.value.bit_xor(old)
	var shifted_27 := mixed.logical_shift_right(27)
	assert(shifted_27.ok)
	var xorshifted := shifted_27.value.low_u32()
	var shifted_59 := old.logical_shift_right(59)
	assert(shifted_59.ok)
	var rotation := shifted_59.value.low_u32() & 31
	if count_public:
		_counter = _counter.add(U64Bits.one())
	return _rotate_right_u32(xorshifted, rotation)

func _rotate_right_u32(value: int, count: int) -> int:
	if count == 0:
		return value & U64Bits.MASK_32
	return ((value >> count) | ((value << (32 - count)) & U64Bits.MASK_32)) & U64Bits.MASK_32
