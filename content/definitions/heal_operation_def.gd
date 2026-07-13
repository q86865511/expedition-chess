class_name HealOperationDef
extends BattleOperationDef

@export var base: int
@export var scaling: StringName
@export var target: StringName

func operation_type() -> int:
	return 0x3002
