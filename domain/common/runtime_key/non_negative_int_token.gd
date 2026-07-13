class_name NonNegativeIntToken
extends RuntimeKeyToken

static func _from_value(raw: int) -> NonNegativeIntToken:
	var token := NonNegativeIntToken.new()
	token.tag = &"i"
	token.value = str(raw)
	return token

static func _from_text_unchecked(raw: String) -> NonNegativeIntToken:
	var token := NonNegativeIntToken.new()
	token.tag = &"i"
	token.value = raw
	return token

func deep_clone() -> RuntimeKeyToken:
	return _from_text_unchecked(value)
