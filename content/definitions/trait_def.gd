class_name TraitDef
extends ContentDefinition

@export var trait_kind: StringName
@export var member_rule: StringName
@export var thresholds: Array[TraitThresholdDef] = []
@export var description_key: StringName

func category_name() -> StringName:
	return &"trait"
