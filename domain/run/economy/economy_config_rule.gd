class_name EconomyConfigRule
extends RefCounted

var config_id: StringName
var layer_income: Array[EconomyValueRule] = []
var interest_step_gold: int
var interest_per_step: int
var max_interest: int
var gold_cap: int
var reroll_cost: int
var xp_buy_cost: int
var xp_buy_amount: int
var streak_rewards: Array[EconomyValueRule] = []
var loss_subsidy: Array[EconomyValueRule] = []
var shop_odds_by_level: Array[ShopOddsRule] = []
var pool_copies_by_tier: Array[EconomyValueRule] = []
var unit_costs_by_tier: Array[EconomyValueRule] = []
var xp_thresholds: Array[EconomyValueRule] = []

func value_for(rules: Array[EconomyValueRule], key: int, fallback: int = -1) -> int:
	for rule: EconomyValueRule in rules:
		if rule.key == key:
			return rule.value
	return fallback

func base_income_for_layer(layer_index: int) -> int:
	var exact := value_for(layer_income, layer_index)
	return exact if exact >= 0 else value_for(layer_income, 0, 0)

func streak_reward(streak: int) -> int:
	var result := 0
	for rule: EconomyValueRule in streak_rewards:
		if rule.key <= streak:
			result = rule.value
	return result

func loss_stipend(streak: int) -> int:
	var result := 0
	for rule: EconomyValueRule in loss_subsidy:
		if rule.key <= streak:
			result = rule.value
	return result

func try_odds_for_level(level: int) -> ShopOddsRule:
	for rule: ShopOddsRule in shop_odds_by_level:
		if rule.level == level:
			return rule.deep_clone()
	return null

func deep_clone() -> EconomyConfigRule:
	var copied := EconomyConfigRule.new()
	copied.config_id = config_id
	copied.interest_step_gold = interest_step_gold
	copied.interest_per_step = interest_per_step
	copied.max_interest = max_interest
	copied.gold_cap = gold_cap
	copied.reroll_cost = reroll_cost
	copied.xp_buy_cost = xp_buy_cost
	copied.xp_buy_amount = xp_buy_amount
	for rule: EconomyValueRule in layer_income: copied.layer_income.append(rule.deep_clone())
	for rule: EconomyValueRule in streak_rewards: copied.streak_rewards.append(rule.deep_clone())
	for rule: EconomyValueRule in loss_subsidy: copied.loss_subsidy.append(rule.deep_clone())
	for rule: ShopOddsRule in shop_odds_by_level: copied.shop_odds_by_level.append(rule.deep_clone())
	for rule: EconomyValueRule in pool_copies_by_tier: copied.pool_copies_by_tier.append(rule.deep_clone())
	for rule: EconomyValueRule in unit_costs_by_tier: copied.unit_costs_by_tier.append(rule.deep_clone())
	for rule: EconomyValueRule in xp_thresholds: copied.xp_thresholds.append(rule.deep_clone())
	return copied
