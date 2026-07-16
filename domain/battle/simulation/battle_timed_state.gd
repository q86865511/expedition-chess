class_name BattleTimedState
extends RefCounted

var kind: StringName = &""
var state_id: StringName = &""
var source_instance_id: OptionalStringNameValue = null
var operation_index: int = 0
var amount: int = 0
var stacks: int = 0
var stat: StringName = &""
var mode: StringName = &""
var expires_tick: int = 0
var applied_sequence: int = 0
var stacking: StringName = &"independent"

func deep_clone() -> BattleTimedState:
	var copied := BattleTimedState.new()
	copied.kind = kind
	copied.state_id = state_id
	copied.source_instance_id = source_instance_id.deep_clone() if source_instance_id != null else null
	copied.operation_index = operation_index
	copied.amount = amount
	copied.stacks = stacks
	copied.stat = stat
	copied.mode = mode
	copied.expires_tick = expires_tick
	copied.applied_sequence = applied_sequence
	copied.stacking = stacking
	return copied
