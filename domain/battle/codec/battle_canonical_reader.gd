class_name BattleCanonicalReader
extends RefCounted

var _text: String = ""
var _position: int = 0
var _failed: bool = false
var _error_path: StringName = &""

func _init(text: String) -> void:
	_text = text

func failed() -> bool:
	return _failed

func error_path() -> StringName:
	return _error_path

func at_end() -> bool:
	return not _failed and _position == _text.length()

func begin_object(path: StringName) -> void:
	_expect_code(123, path)

func end_object(path: StringName) -> void:
	_expect_code(125, path)

func read_key(expected: String, first: bool, path: StringName) -> void:
	if not first:
		_expect_code(44, path)
	var actual := read_string(path)
	if not _failed and actual != expected:
		_fail(path)
	_expect_code(58, path)

func begin_array(path: StringName) -> void:
	_expect_code(91, path)

func array_next(first: bool, path: StringName) -> bool:
	if _failed:
		return false
	if first:
		if _peek_code() == 93:
			_position += 1
			return false
		return true
	if _peek_code() == 44:
		_position += 1
		return true
	if _peek_code() == 93:
		_position += 1
		return false
	_fail(path)
	return false

func next_is_null() -> bool:
	return not _failed and _text.substr(_position, 4) == "null"

func read_null(path: StringName) -> void:
	if _text.substr(_position, 4) != "null":
		_fail(path)
		return
	_position += 4

func read_int(path: StringName) -> int:
	if _failed or _position >= _text.length():
		_fail(path)
		return 0
	var start := _position
	if _peek_code() == 45:
		_position += 1
	if _position >= _text.length():
		_fail(path)
		return 0
	var first_digit := _peek_code()
	if first_digit < 48 or first_digit > 57:
		_fail(path)
		return 0
	if first_digit == 48:
		_position += 1
		if _position < _text.length():
			var next := _peek_code()
			if next >= 48 and next <= 57:
				_fail(path)
				return 0
	else:
		while _position < _text.length():
			var code := _peek_code()
			if code < 48 or code > 57:
				break
			_position += 1
	var encoded := _text.substr(start, _position - start)
	if encoded == "-0" or encoded.length() > 11:
		_fail(path)
		return 0
	var value := encoded.to_int()
	if str(value) != encoded or value < -2147483648 or value > 2147483647:
		_fail(path)
		return 0
	return value

func read_string(path: StringName) -> String:
	if _failed:
		return ""
	if _peek_code() != 34:
		_fail(path)
		return ""
	_position += 1
	var output := ""
	while _position < _text.length():
		var code := _peek_code()
		_position += 1
		if code == 34:
			return output
		if code < 32:
			_fail(path)
			return ""
		if code != 92:
			output += String.chr(code)
			continue
		if _position >= _text.length():
			_fail(path)
			return ""
		var escaped := _peek_code()
		_position += 1
		match escaped:
			34: output += "\""
			92: output += "\\"
			47: output += "/"
			98: output += String.chr(8)
			102: output += String.chr(12)
			110: output += "\n"
			114: output += "\r"
			116: output += "\t"
			117:
				var unicode_value := _read_hex4(path)
				if _failed:
					return ""
				if unicode_value >= 0xd800 and unicode_value <= 0xdbff:
					if _position + 6 > _text.length() or _text.unicode_at(_position) != 92 or _text.unicode_at(_position + 1) != 117:
						_fail(path)
						return ""
					_position += 2
					var low_surrogate := _read_hex4(path)
					if low_surrogate < 0xdc00 or low_surrogate > 0xdfff:
						_fail(path)
						return ""
					unicode_value = 0x10000 + ((unicode_value - 0xd800) << 10) + (low_surrogate - 0xdc00)
				elif unicode_value >= 0xdc00 and unicode_value <= 0xdfff:
					_fail(path)
					return ""
				output += String.chr(unicode_value)
			_:
				_fail(path)
				return ""
	_fail(path)
	return ""

func _read_hex4(path: StringName) -> int:
	if _position + 4 > _text.length():
		_fail(path)
		return 0
	var value := 0
	for _index: int in range(4):
		var code := _peek_code()
		_position += 1
		var digit := -1
		if code >= 48 and code <= 57:
			digit = code - 48
		elif code >= 97 and code <= 102:
			digit = code - 87
		elif code >= 65 and code <= 70:
			digit = code - 55
		if digit < 0:
			_fail(path)
			return 0
		value = (value << 4) | digit
	return value

func _expect_code(expected: int, path: StringName) -> void:
	if _failed:
		return
	if _position >= _text.length() or _text.unicode_at(_position) != expected:
		_fail(path)
		return
	_position += 1

func _peek_code() -> int:
	if _position >= _text.length():
		return -1
	return _text.unicode_at(_position)

func _fail(path: StringName) -> void:
	if not _failed:
		_failed = true
		_error_path = path
