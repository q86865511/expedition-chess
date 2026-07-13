class_name RelicDef
extends ContentDefinition

@export var category: StringName
@export var effect_refs: Array[StringName] = []
@export var activation_limit: int
@export var population_bonus: int

func category_name() -> StringName:
	return &"relic"
