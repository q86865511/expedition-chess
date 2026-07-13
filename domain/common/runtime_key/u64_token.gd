class_name U64Token
extends RuntimeKeyToken

static func _from_value(raw: U64Bits) -> U64Token:
	var token := U64Token.new()
	token.tag = &"u"
	token.value = raw.to_hex()
	return token

static func _from_hex_unchecked(raw: String) -> U64Token:
	var token := U64Token.new()
	token.tag = &"u"
	token.value = raw
	return token

func deep_clone() -> RuntimeKeyToken:
	return _from_hex_unchecked(value)
