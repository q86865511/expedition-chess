class_name GrantItemOperationDef
extends RunOperationDef

@export var content_ref: StringName
@export var count: int

func operation_type() -> int:
	return 0x3105
