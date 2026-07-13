class_name PcgSeedResult
extends RefCounted

var ok: bool = false
var stream: Pcg32Stream = null
var error: PcgSeedError = null

static func success(value: Pcg32Stream) -> PcgSeedResult:
	return PcgSeedResult.new(true, value, null)

static func failure(code: StringName, path: StringName = &"") -> PcgSeedResult:
	return PcgSeedResult.new(false, null, PcgSeedError.create(code, path))

func _init(p_ok: bool, p_stream: Pcg32Stream, p_error: PcgSeedError) -> void:
	ResultInvariant.require(p_ok, p_error, p_stream != null, p_stream == null)
	ok = p_ok
	stream = p_stream
	error = p_error
