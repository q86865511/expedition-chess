class_name BattleDamageRequest
extends RefCounted

var source_instance_id: OptionalStringNameValue = null
var target_instance_id: StringName = &""
var raw_amount: int = 0
var damage_type: StringName = &""
var reason: StringName = &""
var work_sequence: int = 0

func deep_clone() -> BattleDamageRequest:
	var copied := BattleDamageRequest.new()
	copied.source_instance_id = source_instance_id.deep_clone() \
		if source_instance_id != null else null
	copied.target_instance_id = target_instance_id
	copied.raw_amount = raw_amount
	copied.damage_type = damage_type
	copied.reason = reason
	copied.work_sequence = work_sequence
	return copied
