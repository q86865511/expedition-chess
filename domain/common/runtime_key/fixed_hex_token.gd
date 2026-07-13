class_name FixedHexToken
extends RuntimeKeyToken

static func _from_value(raw: String) -> FixedHexToken:
	var token := FixedHexToken.new()
	token.tag = &"h"
	token.value = raw
	return token

func deep_clone() -> RuntimeKeyToken:
	return _from_value(value)
