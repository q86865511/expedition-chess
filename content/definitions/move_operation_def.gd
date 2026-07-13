class_name MoveOperationDef
extends BattleOperationDef

@export var direction_or_target: StringName
@export var cells: int

func operation_type() -> int:
	return 0x3007
