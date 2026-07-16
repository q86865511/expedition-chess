class_name BattleWorkItem
extends RefCounted

var work_sequence: int = 0
var kind: StringName = &""
var source_instance_id: OptionalStringNameValue = null
var target_instance_id: StringName = &""
var effect_id: StringName = &""
var operation_index: int = 0
var primitive_ordinal: int = 0
var amount: int = 0
var damage_type: StringName = &""
var duration_ticks: int = 0
var stat: StringName = &""
var mode: StringName = &""
var status_id: OptionalStringNameValue = null
var stacks: int = 0
var direction: StringName = &""
var unit_id: OptionalStringNameValue = null
var max_active_per_source: int = 0
var placement_rule: StringName = &""
var stacking: StringName = &""
var max_stacks: int = 0

func deep_clone() -> BattleWorkItem:
	var copied := BattleWorkItem.new()
	copied.work_sequence = work_sequence
	copied.kind = kind
	copied.source_instance_id = source_instance_id.deep_clone() if source_instance_id != null else null
	copied.target_instance_id = target_instance_id
	copied.effect_id = effect_id
	copied.operation_index = operation_index
	copied.primitive_ordinal = primitive_ordinal
	copied.amount = amount
	copied.damage_type = damage_type
	copied.duration_ticks = duration_ticks
	copied.stat = stat
	copied.mode = mode
	copied.status_id = status_id.deep_clone() if status_id != null else null
	copied.stacks = stacks
	copied.direction = direction
	copied.unit_id = unit_id.deep_clone() if unit_id != null else null
	copied.max_active_per_source = max_active_per_source
	copied.placement_rule = placement_rule
	copied.stacking = stacking
	copied.max_stacks = max_stacks
	return copied
