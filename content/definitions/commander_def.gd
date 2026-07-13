class_name CommanderDef
extends ContentDefinition

@export var starting_pack: Array[ContentAmountDef] = []
@export var passive_effect_refs: Array[StringName] = []
@export var route_preferences: Array[WeightedEnumDef] = []
@export var population_bonus: int

func category_name() -> StringName:
	return &"commander"
