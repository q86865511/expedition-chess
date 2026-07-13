class_name StableAsciiToken
extends RuntimeKeyToken

static func _from_value(raw: String) -> StableAsciiToken:
	var token := StableAsciiToken.new()
	token.tag = &"s"
	token.value = raw
	return token

func deep_clone() -> RuntimeKeyToken:
	return _from_value(value)
