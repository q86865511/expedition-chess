class_name RngDeriveResult
extends RefCounted

var ok: bool = false
var stream: Pcg32Stream = null
var snapshot: RngSnapshot = null
var error: RngDeriveError = null

static func success(value: Pcg32Stream) -> RngDeriveResult:
	return RngDeriveResult.new(true, value, value.snapshot(), null)

static func failure(code: StringName, path: StringName = &"") -> RngDeriveResult:
	return RngDeriveResult.new(
		false, null, null, RngDeriveError.create(code, path)
	)

func _init(
	p_ok: bool,
	p_stream: Pcg32Stream,
	p_snapshot: RngSnapshot,
	p_error: RngDeriveError
) -> void:
	ResultInvariant.require(
		p_ok,
		p_error,
		p_stream != null and p_snapshot != null,
		p_stream == null and p_snapshot == null
	)
	ok = p_ok
	stream = p_stream
	snapshot = p_snapshot.deep_clone() if p_snapshot != null else null
	error = p_error.deep_clone() if p_error != null else null
