class_name RuntimeKeyCodecV1
extends RefCounted

const TOKEN_INVALID: StringName = &"KEY_TOKEN_INVALID"

func encode(tuple: RuntimeKeyTuple) -> RuntimeKeyEncodeResult:
	var schema_result := RuntimeKeySchemaRegistry.new().validate_tuple(tuple)
	if not schema_result.ok:
		return RuntimeKeyEncodeResult.failure(
			schema_result.error.code, schema_result.error.field_path
		)
	var bytes := PackedByteArray()
	for token: RuntimeKeyToken in tuple.tokens_copy():
		var token_bytes := token.canonical_bytes()
		_append_u32_be(bytes, token_bytes.size())
		bytes.append_array(token_bytes)
	var digest_result := _sha256(bytes)
	if digest_result.is_empty():
		return RuntimeKeyEncodeResult.failure(TOKEN_INVALID, &"sha256")
	var state := RuntimeKeyState.new()
	state.kind = tuple.kind()
	state.digest = StringName("%s_%s" % [String(tuple.kind()), digest_result])
	return RuntimeKeyEncodeResult.success(state, bytes)

func decode(bytes: PackedByteArray) -> RuntimeKeyDecodeResult:
	if bytes.is_empty():
		return RuntimeKeyDecodeResult.failure(TOKEN_INVALID, &"bytes")
	var offset := 0
	var tokens: Array[RuntimeKeyToken] = []
	while offset < bytes.size():
		if bytes.size() - offset < 4:
			return RuntimeKeyDecodeResult.failure(TOKEN_INVALID, &"length")
		var length := (bytes[offset] << 24) | (bytes[offset + 1] << 16) | (bytes[offset + 2] << 8) | bytes[offset + 3]
		offset += 4
		if length <= 2 or length > bytes.size() - offset:
			return RuntimeKeyDecodeResult.failure(TOKEN_INVALID, &"length")
		var token_bytes := bytes.slice(offset, offset + length)
		offset += length
		var text := token_bytes.get_string_from_utf8()
		if text.to_utf8_buffer() != token_bytes or text.length() < 3 or text.unicode_at(1) != 58:
			return RuntimeKeyDecodeResult.failure(TOKEN_INVALID, &"token")
		var token := _token_from_text(text.substr(0, 1), text.substr(2))
		if token == null:
			return RuntimeKeyDecodeResult.failure(TOKEN_INVALID, &"token")
		tokens.append(token)
	if tokens.is_empty() or tokens[0].tag != &"k":
		return RuntimeKeyDecodeResult.failure(TOKEN_INVALID, &"tokens.0")
	var tuple := RuntimeKeyTuple._create(StringName(tokens[0].value), tokens)
	var encoded := encode(tuple)
	if not encoded.ok or encoded.canonical_bytes != bytes:
		var code := encoded.error.code if not encoded.ok else TOKEN_INVALID
		var path := encoded.error.field_path if not encoded.ok else &"bytes"
		return RuntimeKeyDecodeResult.failure(code, path)
	return RuntimeKeyDecodeResult.success(tuple)

func _token_from_text(tag_text: String, value: String) -> RuntimeKeyToken:
	match tag_text:
		"k": return KeyKindToken._from_value(value)
		"e": return EnumToken._from_value(value)
		"s": return StableAsciiToken._from_value(value)
		"h": return FixedHexToken._from_value(value)
		"u": return U64Token._from_hex_unchecked(value)
		"i": return NonNegativeIntToken._from_text_unchecked(value)
	return null

func _append_u32_be(target: PackedByteArray, value: int) -> void:
	target.append((value >> 24) & 0xff)
	target.append((value >> 16) & 0xff)
	target.append((value >> 8) & 0xff)
	target.append(value & 0xff)

func _sha256(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	if context.update(bytes) != OK:
		return ""
	return context.finish().hex_encode()
