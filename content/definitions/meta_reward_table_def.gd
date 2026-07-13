class_name MetaRewardTableDef
extends ContentDefinition

@export var node_scores: Array[EnumIntPairDef] = []
@export var completion_reward: int
@export var failure_reward: int
@export var challenge_multiplier_bps: Array[ChallengeMultiplierDef] = []

func category_name() -> StringName:
	return &"meta_reward_table"
