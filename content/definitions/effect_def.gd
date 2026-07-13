class_name EffectDef
extends ContentDefinition

@export var content_role: StringName = &"general"
@export var trigger: StringName
@export var conditions: Array[ConditionDef] = []
@export var battle_operations: Array[BattleOperationDef] = []
@export var run_operations: Array[RunOperationDef] = []
@export var stacking: StringName
@export var max_stacks: int = 1
@export var duration_ticks: int = 1

func category_name() -> StringName:
	return &"effect"
