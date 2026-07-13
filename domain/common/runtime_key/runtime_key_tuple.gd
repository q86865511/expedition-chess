class_name RuntimeKeyTuple
extends RefCounted

var _kind: StringName = &""
var _tokens: Array[RuntimeKeyToken] = []

static func _create(kind: StringName, tokens: Array[RuntimeKeyToken]) -> RuntimeKeyTuple:
	var value := RuntimeKeyTuple.new()
	value._kind = kind
	for token: RuntimeKeyToken in tokens:
		value._tokens.append(token.deep_clone())
	return value

func kind() -> StringName:
	return _kind

func token_count() -> int:
	return _tokens.size()

func token_at(index: int) -> RuntimeKeyToken:
	return _tokens[index].deep_clone()

func tokens_copy() -> Array[RuntimeKeyToken]:
	var copied: Array[RuntimeKeyToken] = []
	for token: RuntimeKeyToken in _tokens:
		copied.append(token.deep_clone())
	return copied

func deep_clone() -> RuntimeKeyTuple:
	return _create(_kind, _tokens)
