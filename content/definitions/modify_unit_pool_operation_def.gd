class_name ModifyUnitPoolOperationDef
extends RunOperationDef

@export var unit_ref: StringName
@export var count: int

func operation_type() -> int:
	return 0x3104
