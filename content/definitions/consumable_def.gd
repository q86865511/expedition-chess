class_name ConsumableDef
extends ContentDefinition

@export var use_timing: StringName
@export var run_operations: Array[RunOperationDef] = []
@export var stack_limit: int = 1

func category_name() -> StringName:
	return &"consumable"
