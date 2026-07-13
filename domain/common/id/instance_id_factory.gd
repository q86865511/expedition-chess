class_name InstanceIdFactory
extends RefCounted

const INVALID_FORMAT: StringName = &"ID_INVALID_FORMAT"
const SERIAL_EXHAUSTED: StringName = &"ID_SERIAL_EXHAUSTED"

func create(prefix: StringName, serial: U64Bits) -> InstanceIdResult:
	if not _valid_prefix(String(prefix)):
		return InstanceIdResult.failure(INVALID_FORMAT, &"prefix")
	if serial == null:
		return InstanceIdResult.failure(INVALID_FORMAT, &"serial")
	if serial.equals(U64Bits.max_value()):
		return InstanceIdResult.failure(SERIAL_EXHAUSTED)
	var id := StringName("%s_%s" % [String(prefix), serial.to_hex()])
	return InstanceIdResult.success(id, serial.add(U64Bits.one()))

func _valid_prefix(prefix: String) -> bool:
	if prefix.is_empty():
		return false
	for index: int in range(prefix.length()):
		var code := prefix.unicode_at(index)
		if code < 97 or code > 122:
			return false
	return true
