class_name GrantManaOperationDef
extends BattleOperationDef

@export var amount: int
@export var target: StringName

func operation_type() -> int:
	return 0x3009
