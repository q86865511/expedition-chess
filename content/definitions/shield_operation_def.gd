class_name ShieldOperationDef
extends BattleOperationDef

@export var amount: int
@export var duration_ticks: int
@export var target: StringName

func operation_type() -> int:
	return 0x3003
