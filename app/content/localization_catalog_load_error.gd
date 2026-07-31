class_name LocalizationCatalogLoadError
extends RefCounted

const IO := &"IO"
const DIGEST_MISMATCH := &"DIGEST_MISMATCH"
const MALFORMED_HEADER := &"MALFORMED_HEADER"
const MALFORMED_ROW := &"MALFORMED_ROW"
const DUPLICATE_KEY := &"DUPLICATE_KEY"
const BLANK_VALUE := &"BLANK_VALUE"
const KEY_PARITY := &"KEY_PARITY"
const UNSUPPORTED_LOCALE := &"UNSUPPORTED_LOCALE"
const HARDCODED_TEXT := &"HARDCODED_TEXT"

var code: StringName
var row: int
var key: StringName

func _init(
	p_code: StringName,
	p_row: int = 0,
	p_key: StringName = &""
) -> void:
	code = p_code
	row = p_row
	key = p_key
