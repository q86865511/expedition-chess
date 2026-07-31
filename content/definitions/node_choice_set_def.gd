class_name NodeChoiceSetDef
extends ContentDefinition

@export var node_kind: StringName
@export var choices: Array[NodeChoiceDef] = []

func category_name() -> StringName:
	return &"node_choice_set"
