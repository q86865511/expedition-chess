class_name ItemInstanceState
extends RefCounted

var instance_id: String
var def_id: StringName
var bound_unit_instance_id: OptionalStringValue
var acquired_serial: U64Bits

func _init(
	p_instance_id: String,
	p_def_id: StringName,
	p_bound_unit_instance_id: OptionalStringValue,
	p_acquired_serial: U64Bits
) -> void:
	instance_id = p_instance_id
	def_id = p_def_id
	bound_unit_instance_id = p_bound_unit_instance_id.deep_clone() if p_bound_unit_instance_id != null else null
	acquired_serial = p_acquired_serial.deep_clone()

func deep_clone() -> ItemInstanceState:
	return ItemInstanceState.new(instance_id, def_id, bound_unit_instance_id, acquired_serial)
