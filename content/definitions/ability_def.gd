class_name AbilityDef
extends ContentDefinition

@export var start_mana: int
@export var max_mana: int
@export var target_rule: StringName
@export var cast_ticks: int
@export var effect_refs: Array[StringName] = []
@export var description_key: StringName

func category_name() -> StringName:
	return &"ability"
