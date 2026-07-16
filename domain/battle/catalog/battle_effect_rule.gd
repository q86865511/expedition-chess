class_name BattleEffectRule
extends RefCounted

var effect_id: StringName
var content_role: StringName
var trigger: StringName
var periodic_interval_ticks: int
var conditions: Array[BattleConditionRule] = []
var battle_operations: Array[BattleOperationRule] = []
var run_operations: Array[BattleRunOperationRule] = []
var stacking: StringName
var max_stacks: int
var duration_ticks: int

func deep_clone() -> BattleEffectRule:
	var copied := BattleEffectRule.new()
	copied.effect_id = effect_id
	copied.content_role = content_role
	copied.trigger = trigger
	copied.periodic_interval_ticks = periodic_interval_ticks
	for condition: BattleConditionRule in conditions:
		copied.conditions.append(condition.deep_clone())
	for operation: BattleOperationRule in battle_operations:
		copied.battle_operations.append(operation.deep_clone())
	for operation: BattleRunOperationRule in run_operations:
		copied.run_operations.append(operation.deep_clone())
	copied.stacking = stacking
	copied.max_stacks = max_stacks
	copied.duration_ticks = duration_ticks
	return copied
