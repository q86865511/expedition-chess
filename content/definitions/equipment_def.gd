class_name EquipmentDef
extends ContentDefinition

@export var component_pair: Array[StringName] = []
@export var stat_modifiers: Array[StatModifierDef] = []
@export var effect_refs: Array[StringName] = []
@export var has_unique_group: bool
@export var unique_group: StringName

func category_name() -> StringName:
	return &"equipment"
