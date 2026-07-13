class_name UnitInstance
extends RefCounted

var instance_id: String
var def_id: StringName
var star: int
var equipment_instance_ids: Array[String] = []
var acquired_serial: U64Bits

func _init(
	p_instance_id: String,
	p_def_id: StringName,
	p_star: int,
	p_equipment_instance_ids: Array[String],
	p_acquired_serial: U64Bits
) -> void:
	instance_id = p_instance_id
	def_id = p_def_id
	star = p_star
	equipment_instance_ids.assign(p_equipment_instance_ids)
	acquired_serial = p_acquired_serial.deep_clone()

func deep_clone() -> UnitInstance:
	return UnitInstance.new(instance_id, def_id, star, equipment_instance_ids, acquired_serial)
