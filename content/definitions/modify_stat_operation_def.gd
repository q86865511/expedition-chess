class_name ModifyStatOperationDef
extends BattleOperationDef

@export var stat: StringName
@export var mode: StringName
@export var amount: int
@export var duration_ticks: int
@export var target: StringName

func operation_type() -> int:
	return 0x3004
