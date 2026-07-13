class_name RewardTableDef
extends ContentDefinition

@export var reward_candidates: Array[RewardCandidateDef] = []
@export var draw_count: int = 1

func category_name() -> StringName:
	return &"reward_table"
