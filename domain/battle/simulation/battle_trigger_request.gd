class_name BattleTriggerRequest
extends RefCounted

var trigger: StringName = &""
var source_instance_id: StringName = &""
var target_instance_id: OptionalStringNameValue = null

func deep_clone() -> BattleTriggerRequest:
	var copied := BattleTriggerRequest.new()
	copied.trigger = trigger
	copied.source_instance_id = source_instance_id
	copied.target_instance_id = target_instance_id.deep_clone() \
		if target_instance_id != null else null
	return copied
