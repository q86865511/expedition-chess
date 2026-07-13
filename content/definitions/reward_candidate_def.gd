class_name RewardCandidateDef
extends Resource

@export var kind: StringName
@export var has_content_ref: bool
@export var content_ref: StringName
@export var weight_i32: int
@export var conditions: Array[ConditionDef] = []
