class_name PopulationSourceOperationDef
extends RunOperationDef

@export var source_id: StringName
@export var amount: int

func operation_type() -> int:
	return 0x3107
