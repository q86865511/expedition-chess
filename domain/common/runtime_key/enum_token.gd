class_name EnumToken
extends RuntimeKeyToken

static func _from_value(raw: String) -> EnumToken:
	var token := EnumToken.new()
	token.tag = &"e"
	token.value = raw
	return token

func deep_clone() -> RuntimeKeyToken:
	return _from_value(value)
