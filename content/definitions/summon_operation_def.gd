class_name SummonOperationDef
extends BattleOperationDef

@export var unit_ref: StringName
@export var count: int
@export var max_active_per_source: int
@export var placement_rule: StringName

func operation_type() -> int:
	return 0x3008
