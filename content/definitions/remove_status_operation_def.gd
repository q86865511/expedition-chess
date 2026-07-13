class_name RemoveStatusOperationDef
extends BattleOperationDef

@export var status_id: StringName
@export var target: StringName

func operation_type() -> int:
	return 0x3006
