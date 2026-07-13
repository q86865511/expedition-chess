class_name SaveEncodeResult
extends RefCounted

var ok: bool
var json_text: OptionalStringValue
var bytes: OptionalBytesValue
var digest: OptionalStringValue
var error: SaveCodecError

static func success(p_text: String, p_bytes: PackedByteArray, p_digest: String) -> SaveEncodeResult:
	return SaveEncodeResult.new(
		true, OptionalStringValue.new(p_text), OptionalBytesValue.new(p_bytes),
		OptionalStringValue.new(p_digest), null
	)

static func failure(p_error: SaveCodecError) -> SaveEncodeResult:
	return SaveEncodeResult.new(false, null, null, null, p_error)

func _init(
	p_ok: bool,
	p_json_text: OptionalStringValue,
	p_bytes: OptionalBytesValue,
	p_digest: OptionalStringValue,
	p_error: SaveCodecError
) -> void:
	ResultInvariant.require(
		p_ok,
		p_error,
		p_json_text != null and p_bytes != null and p_digest != null,
		p_json_text == null and p_bytes == null and p_digest == null
	)
	ok = p_ok
	json_text = p_json_text.deep_clone() if p_json_text != null else null
	bytes = p_bytes.deep_clone() if p_bytes != null else null
	digest = p_digest.deep_clone() if p_digest != null else null
	error = p_error.deep_clone() if p_error != null else null
