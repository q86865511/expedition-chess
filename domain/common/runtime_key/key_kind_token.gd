class_name KeyKindToken
extends RuntimeKeyToken

static func _from_value(raw: String) -> KeyKindToken:
	var token := KeyKindToken.new()
	token.tag = &"k"
	token.value = raw
	return token

func deep_clone() -> RuntimeKeyToken:
	return _from_value(value)
