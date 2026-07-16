class_name BattleOperationRule
extends RefCounted

var operation_index: int
var kind: StringName
var base_amount: int
var amount: int
var scaling: StringName
var damage_type: StringName
var target: StringName
var duration_ticks: int
var stat: StringName
var mode: StringName
var status_id: OptionalStringNameValue
var stacks: int
var direction: StringName
var cells: int
var unit_id: OptionalStringNameValue
var count: int
var max_active_per_source: int
var placement_rule: StringName

func deep_clone() -> BattleOperationRule:
	var copied := BattleOperationRule.new()
	copied.operation_index = operation_index
	copied.kind = kind
	copied.base_amount = base_amount
	copied.amount = amount
	copied.scaling = scaling
	copied.damage_type = damage_type
	copied.target = target
	copied.duration_ticks = duration_ticks
	copied.stat = stat
	copied.mode = mode
	copied.status_id = status_id.deep_clone() if status_id != null else null
	copied.stacks = stacks
	copied.direction = direction
	copied.cells = cells
	copied.unit_id = unit_id.deep_clone() if unit_id != null else null
	copied.count = count
	copied.max_active_per_source = max_active_per_source
	copied.placement_rule = placement_rule
	return copied
