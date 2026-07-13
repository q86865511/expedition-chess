class_name RuntimeKeyEncodeResult
extends RefCounted

var ok: bool = false
var key_state: RuntimeKeyState = null
var canonical_bytes: PackedByteArray = PackedByteArray()
var error: RuntimeKeyError = null

static func success(state: RuntimeKeyState, bytes: PackedByteArray) -> RuntimeKeyEncodeResult:
	return RuntimeKeyEncodeResult.new(true, state, bytes, null)

static func failure(error_code: StringName, path: StringName = &"") -> RuntimeKeyEncodeResult:
	return RuntimeKeyEncodeResult.new(
		false, null, PackedByteArray(), RuntimeKeyError.create(error_code, path)
	)

func _init(
	p_ok: bool,
	p_key_state: RuntimeKeyState,
	p_canonical_bytes: PackedByteArray,
	p_error: RuntimeKeyError
) -> void:
	ResultInvariant.require(
		p_ok,
		p_error,
		p_key_state != null and not p_canonical_bytes.is_empty(),
		p_key_state == null and p_canonical_bytes.is_empty()
	)
	ok = p_ok
	key_state = p_key_state
	canonical_bytes = p_canonical_bytes.duplicate()
	error = p_error
