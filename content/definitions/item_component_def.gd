class_name ItemComponentDef
extends ContentDefinition

@export var recipe_key: String
@export var sort_order: int

func category_name() -> StringName:
	return &"item_component"
