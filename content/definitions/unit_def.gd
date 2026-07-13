class_name UnitDef
extends ContentDefinition

@export_range(1, 5) var cost_tier: int = 1
@export var trait_refs: Array[StringName] = []
@export var base_stats: UnitStatsDef
@export var star_scalings: Array[StarScalingDef] = []
@export var ability_ref: StringName
@export var has_ability_ref: bool
@export var ai_profile: StringName
@export var basic_attack_profile: StringName
@export var availability: StringName
@export var shop_condition: StringName

func category_name() -> StringName:
	return &"unit"
