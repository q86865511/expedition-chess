class_name EconomyPayloadDigest
extends RefCounted

static func sha256(parts: Array[String]) -> String:
	var bytes := PackedByteArray()
	for part: String in parts:
		var raw := part.to_utf8_buffer()
		bytes.append((raw.size() >> 24) & 0xff)
		bytes.append((raw.size() >> 16) & 0xff)
		bytes.append((raw.size() >> 8) & 0xff)
		bytes.append(raw.size() & 0xff)
		bytes.append_array(raw)
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK or context.update(bytes) != OK:
		return ""
	return context.finish().hex_encode()
