class_name ApplyStatusOperationDef
extends BattleOperationDef

@export var status_id: StringName
@export var stacks: int
@export var duration_ticks: int
@export var target: StringName

func operation_type() -> int:
	return 0x3005
