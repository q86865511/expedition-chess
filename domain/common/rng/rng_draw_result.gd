class_name RngDrawResult
extends RefCounted

var ok: bool = false
var value_u32: U64Bits = null
var next_snapshot: RngSnapshot = null
var error: RngDrawError = null

static func success(value: int, snapshot: RngSnapshot) -> RngDrawResult:
	var created := U64Bits.from_u32(0, value)
	assert(created.ok)
	return RngDrawResult.new(true, created.value, snapshot, null)

static func failure(code: StringName, path: StringName = &"") -> RngDrawResult:
	return RngDrawResult.new(false, null, null, RngDrawError.create(code, path))

func _init(
	p_ok: bool,
	p_value_u32: U64Bits,
	p_next_snapshot: RngSnapshot,
	p_error: RngDrawError
) -> void:
	ResultInvariant.require(
		p_ok,
		p_error,
		p_value_u32 != null and p_next_snapshot != null,
		p_value_u32 == null and p_next_snapshot == null
	)
	ok = p_ok
	value_u32 = p_value_u32
	next_snapshot = p_next_snapshot.deep_clone() if p_next_snapshot != null else null
	error = p_error
