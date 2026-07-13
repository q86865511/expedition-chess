class_name U64Bits
extends RefCounted

const MASK_32: int = 0xffffffff
const MASK_16: int = 0xffff

var _hi: int = 0
var _lo: int = 0

static func from_hex(value: String) -> U64ParseResult:
	if value.length() != 16:
		return U64ParseResult.failure(&"value")
	for index: int in range(value.length()):
		var code := value.unicode_at(index)
		var is_digit := code >= 48 and code <= 57
		var is_lower_hex := code >= 97 and code <= 102
		if not is_digit and not is_lower_hex:
			return U64ParseResult.failure(&"value")
	var high := value.substr(0, 8).hex_to_int()
	var low := value.substr(8, 8).hex_to_int()
	return U64ParseResult.success(_make(high, low))

static func from_u32(high: int, low: int) -> U64CreateResult:
	if high < 0 or high > MASK_32:
		return U64CreateResult.failure(&"high")
	if low < 0 or low > MASK_32:
		return U64CreateResult.failure(&"low")
	return U64CreateResult.success(_make(high, low))

static func zero() -> U64Bits:
	return _make(0, 0)

static func one() -> U64Bits:
	return _make(0, 1)

static func max_value() -> U64Bits:
	return _make(MASK_32, MASK_32)

static func _make(high: int, low: int) -> U64Bits:
	var value := U64Bits.new()
	value._hi = high
	value._lo = low
	return value

func to_hex() -> String:
	return "%08x%08x" % [_hi, _lo]

func high_u32() -> int:
	return _hi

func low_u32() -> int:
	return _lo

func deep_clone() -> U64Bits:
	return _make(_hi, _lo)

func add(other: U64Bits) -> U64Bits:
	var low_sum := _lo + other._lo
	var carry := 1 if low_sum > MASK_32 else 0
	var next_low := low_sum & MASK_32
	var next_high := (_hi + other._hi + carry) & MASK_32
	return _make(next_high, next_low)

func multiply(other: U64Bits) -> U64Bits:
	var left: Array[int] = [
		_lo & MASK_16,
		(_lo >> 16) & MASK_16,
		_hi & MASK_16,
		(_hi >> 16) & MASK_16,
	]
	var right: Array[int] = [
		other._lo & MASK_16,
		(other._lo >> 16) & MASK_16,
		other._hi & MASK_16,
		(other._hi >> 16) & MASK_16,
	]
	var product: Array[int] = [0, 0, 0, 0]
	var carry := 0
	for output_limb: int in range(4):
		var total := carry
		for left_index: int in range(output_limb + 1):
			var right_index := output_limb - left_index
			total += left[left_index] * right[right_index]
		product[output_limb] = total & MASK_16
		carry = total >> 16
	var next_low := product[0] | (product[1] << 16)
	var next_high := product[2] | (product[3] << 16)
	return _make(next_high, next_low)

func bit_xor(other: U64Bits) -> U64Bits:
	return _make(_hi ^ other._hi, _lo ^ other._lo)

func bit_or(other: U64Bits) -> U64Bits:
	return _make(_hi | other._hi, _lo | other._lo)

func shift_left(count: int) -> U64ShiftResult:
	if count < 0 or count > 63:
		return U64ShiftResult.failure()
	if count == 0:
		return U64ShiftResult.success(deep_clone())
	if count < 32:
		var next_high := ((_hi << count) & MASK_32) | (_lo >> (32 - count))
		var next_low := (_lo << count) & MASK_32
		return U64ShiftResult.success(_make(next_high, next_low))
	if count == 32:
		return U64ShiftResult.success(_make(_lo, 0))
	return U64ShiftResult.success(_make((_lo << (count - 32)) & MASK_32, 0))

func logical_shift_right(count: int) -> U64ShiftResult:
	if count < 0 or count > 63:
		return U64ShiftResult.failure()
	if count == 0:
		return U64ShiftResult.success(deep_clone())
	if count < 32:
		var low_from_high_mask := (1 << count) - 1
		var next_low := (_lo >> count) | ((_hi & low_from_high_mask) << (32 - count))
		var next_high := _hi >> count
		return U64ShiftResult.success(_make(next_high, next_low))
	if count == 32:
		return U64ShiftResult.success(_make(0, _hi))
	return U64ShiftResult.success(_make(0, _hi >> (count - 32)))

func equals(other: U64Bits) -> bool:
	return other != null and _hi == other._hi and _lo == other._lo

func is_zero() -> bool:
	return _hi == 0 and _lo == 0

func is_odd() -> bool:
	return (_lo & 1) == 1

func compare(other: U64Bits) -> int:
	if _hi < other._hi:
		return -1
	if _hi > other._hi:
		return 1
	if _lo < other._lo:
		return -1
	if _lo > other._lo:
		return 1
	return 0
