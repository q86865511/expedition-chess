class_name EconomyConfigDef
extends ContentDefinition

@export var layer_income: Array[U32PairDef] = []
@export var interest_step_gold: int = 10
@export var interest_per_step: int = 1
@export var max_interest: int = 5
@export var gold_cap: int = 99
@export var reroll_cost: int = 2
@export var xp_buy_cost: int = 4
@export var xp_buy_amount: int = 4
@export var streak_rewards: Array[U32PairDef] = []
@export var loss_subsidy: Array[U32PairDef] = []
@export var shop_odds_by_level: Array[ShopOddsRowDef] = []
@export var pool_copies_by_tier: Array[U32PairDef] = []
@export var unit_costs_by_tier: Array[U32PairDef] = []
@export var xp_thresholds: Array[U32PairDef] = []

func category_name() -> StringName:
	return &"economy_config"
