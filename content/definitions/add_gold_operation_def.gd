class_name AddGoldOperationDef
extends RunOperationDef

@export var amount: int
@export var claim_scope: StringName

func operation_type() -> int:
	return 0x3101
