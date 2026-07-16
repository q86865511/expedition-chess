class_name BattleEventProposal
extends RefCounted

var operation_kind: StringName = &""
var effect_id: StringName = &""
var operation_index: int = 0
var source_instance_id: OptionalStringNameValue = null
var target_instance_id: OptionalStringNameValue = null
var primitive_ordinal: int = 0

func deep_clone() -> BattleEventProposal:
	var copied := BattleEventProposal.new()
	copied.operation_kind = operation_kind
	copied.effect_id = effect_id
	copied.operation_index = operation_index
	copied.source_instance_id = source_instance_id.deep_clone() if source_instance_id != null else null
	copied.target_instance_id = target_instance_id.deep_clone() if target_instance_id != null else null
	copied.primitive_ordinal = primitive_ordinal
	return copied
