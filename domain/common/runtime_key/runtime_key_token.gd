class_name RuntimeKeyToken
extends RefCounted

var tag: StringName = &""
var value: String = ""

func canonical_text() -> String:
	return "%s:%s" % [String(tag), value]

func canonical_bytes() -> PackedByteArray:
	return canonical_text().to_utf8_buffer()

func deep_clone() -> RuntimeKeyToken:
	var copied := RuntimeKeyToken.new()
	copied.tag = tag
	copied.value = value
	return copied
