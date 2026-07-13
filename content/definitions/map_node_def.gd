class_name MapNodeDef
extends ContentDefinition

@export var node_type: StringName
@export var generator_ref: StringName
@export var enter_operations: Array[RunOperationDef] = []
@export var exit_operations: Array[RunOperationDef] = []

func category_name() -> StringName:
	return &"map_node"
