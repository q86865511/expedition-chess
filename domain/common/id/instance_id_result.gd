class_name InstanceIdResult
extends RefCounted

var ok: bool = false
var instance_id: StringName = &""
var next_serial: U64Bits = null
var error: InstanceIdError = null

static func success(id: StringName, following_serial: U64Bits) -> InstanceIdResult:
	return InstanceIdResult.new(true, id, following_serial, null)

static func failure(error_code: StringName, path: StringName = &"serial") -> InstanceIdResult:
	return InstanceIdResult.new(
		false, &"", null, InstanceIdError.create(error_code, path)
	)

func _init(
	p_ok: bool,
	p_instance_id: StringName,
	p_next_serial: U64Bits,
	p_error: InstanceIdError
) -> void:
	ResultInvariant.require(
		p_ok,
		p_error,
		not p_instance_id.is_empty() and p_next_serial != null,
		p_instance_id.is_empty() and p_next_serial == null
	)
	ok = p_ok
	instance_id = p_instance_id
	next_serial = p_next_serial
	error = p_error
