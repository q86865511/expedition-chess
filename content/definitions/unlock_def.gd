class_name UnlockDef
extends ContentDefinition

@export var unlock_kind: StringName
@export var challenge_level: int
@export var prerequisite_refs: Array[StringName] = []
@export var currency_cost: int
@export var unlocked_content_refs: Array[StringName] = []
@export var modifier_refs: Array[StringName] = []

func category_name() -> StringName:
	return &"unlock"
