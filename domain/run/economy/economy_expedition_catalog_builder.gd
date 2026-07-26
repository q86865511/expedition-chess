class_name EconomyExpeditionCatalogBuilder
extends RefCounted

func build(
	registry: ContentRegistryService,
	manifest_digest: String,
	economy_config_id: StringName,
	unit_ids: Array[StringName],
	map_node_ids: Array[StringName],
	reward_table_ids: Array[StringName] = []
) -> EconomyCatalogBuildResult:
	if registry == null or not ContentRef.new(manifest_digest, economy_config_id).is_valid():
		return EconomyCatalogBuildResult.failure(EconomyCatalogError.INPUT_INVALID, &"manifest_digest")
	var config_view_result := registry.resolve(ContentRef.new(manifest_digest, economy_config_id))
	if not config_view_result.ok:
		return EconomyCatalogBuildResult.failure(EconomyCatalogError.RESOLVE_FAILED, config_view_result.error.field_path, economy_config_id)
	var config := _decode_config(config_view_result.value)
	if config == null or not _valid_config(config):
		return EconomyCatalogBuildResult.failure(EconomyCatalogError.CONFIG_INVALID, &"economy_config", economy_config_id)
	var shop_units: Array[ShopUnitRule] = []
	var sorted_units: Array[StringName] = unit_ids.duplicate()
	sorted_units.sort()
	for unit_id: StringName in sorted_units:
		var resolved := registry.resolve(ContentRef.new(manifest_digest, unit_id))
		if not resolved.ok:
			return EconomyCatalogBuildResult.failure(EconomyCatalogError.RESOLVE_FAILED, resolved.error.field_path, unit_id)
		var unit := _decode_unit(resolved.value, config)
		if unit != null:
			shop_units.append(unit)
	if shop_units.is_empty():
		return EconomyCatalogBuildResult.failure(EconomyCatalogError.CONFIG_INVALID, &"shop_units")
	var map_nodes: Array[MapNodeRule] = []
	var sorted_nodes: Array[StringName] = map_node_ids.duplicate()
	sorted_nodes.sort()
	for node_id: StringName in sorted_nodes:
		var resolved := registry.resolve(ContentRef.new(manifest_digest, node_id))
		if not resolved.ok:
			return EconomyCatalogBuildResult.failure(EconomyCatalogError.RESOLVE_FAILED, resolved.error.field_path, node_id)
		var node := _decode_map_node(resolved.value)
		if node == null:
			return EconomyCatalogBuildResult.failure(EconomyCatalogError.PAYLOAD_INVALID, &"map_node", node_id)
		map_nodes.append(node)
	for kind: int in range(7):
		var found := false
		for node: MapNodeRule in map_nodes:
			if node.node_kind == kind:
				found = true
				break
		if not found:
			return EconomyCatalogBuildResult.failure(EconomyCatalogError.MAP_KIND_MISSING, &"map_nodes", StringName(MapNodeState.node_kind_to_token(kind)))
	var reward_tables: Array[RewardTableRule] = []
	var sorted_reward_ids: Array[StringName] = reward_table_ids.duplicate()
	sorted_reward_ids.sort()
	for reward_id: StringName in sorted_reward_ids:
		var resolved_reward := registry.resolve(ContentRef.new(manifest_digest, reward_id))
		if not resolved_reward.ok:
			return EconomyCatalogBuildResult.failure(
				EconomyCatalogError.RESOLVE_FAILED,
				resolved_reward.error.field_path,
				reward_id
			)
		var reward_table := _decode_reward_table(resolved_reward.value)
		if reward_table == null:
			return EconomyCatalogBuildResult.failure(
				EconomyCatalogError.PAYLOAD_INVALID, &"reward_table", reward_id
			)
		reward_tables.append(reward_table)
	return EconomyCatalogBuildResult.success(EconomyExpeditionCatalog.new(
		manifest_digest, config, shop_units, map_nodes, reward_tables
	))

func _decode_config(view: ContentDefinitionView) -> EconomyConfigRule:
	if view == null or view.category != &"economy_config" or view.payload == null \
		or view.payload.record_type != ContentCategory.ECONOMY_CONFIG \
		or view.payload.children.size() != 17:
		return null
	var c := view.payload.children
	var result := EconomyConfigRule.new()
	result.config_id = view.content_id
	result.layer_income = _pairs(c[3])
	result.interest_step_gold = c[4].int_value
	result.interest_per_step = c[5].int_value
	result.max_interest = c[6].int_value
	result.gold_cap = c[7].int_value
	result.reroll_cost = c[8].int_value
	result.xp_buy_cost = c[9].int_value
	result.xp_buy_amount = c[10].int_value
	result.streak_rewards = _pairs(c[11])
	result.loss_subsidy = _pairs(c[12])
	for value: ContentValue in c[13].children:
		if value.record_type != 0x200a or value.children.size() != 2:
			return null
		var odds: Array[int] = []
		for item: ContentValue in value.children[1].children: odds.append(item.int_value)
		result.shop_odds_by_level.append(ShopOddsRule.new(value.children[0].int_value, odds))
	result.pool_copies_by_tier = _pairs(c[14])
	result.unit_costs_by_tier = _pairs(c[15])
	result.xp_thresholds = _pairs(c[16])
	return result

func _decode_unit(view: ContentDefinitionView, config: EconomyConfigRule) -> ShopUnitRule:
	if view == null or view.category != &"unit" or view.payload == null \
		or view.payload.record_type != ContentCategory.UNIT or view.payload.children.size() != 13:
		return null
	var c := view.payload.children
	var availability := StringName(c[10].string_value)
	var condition := StringName(c[11].string_value)
	if not availability in [&"player", &"shared"] or condition != &"always":
		return null
	var tier := c[3].int_value
	var cost := config.value_for(config.unit_costs_by_tier, tier, -1)
	if tier < 1 or tier > 5 or cost < 1:
		return null
	return ShopUnitRule.new(view.content_id, tier, cost)

func _decode_map_node(view: ContentDefinitionView) -> MapNodeRule:
	if view == null or view.category != &"map_node" or view.payload == null \
		or view.payload.record_type != ContentCategory.MAP_NODE or view.payload.children.size() != 7:
		return null
	var token := StringName(view.payload.children[3].string_value)
	var tokens: Array[StringName] = [&"normal", &"elite", &"merchant", &"event", &"rest", &"treasure", &"boss"]
	var kind := tokens.find(token)
	if kind < 0:
		return null
	return MapNodeRule.new(
		view.content_id,
		kind,
		StringName(view.payload.children[4].string_value)
	)

func _decode_reward_table(view: ContentDefinitionView) -> RewardTableRule:
	if view == null or view.category != &"reward_table" or view.payload == null \
		or view.payload.record_type != ContentCategory.REWARD_TABLE \
		or view.payload.children.size() != 5:
		return null
	var candidates: Array[RewardCandidateRule] = []
	for value: ContentValue in view.payload.children[3].children:
		if value.record_type != 0x2008 or value.children.size() != 4:
			return null
		var kind := StringName(value.children[0].string_value)
		if not kind in [&"unit", &"item", &"relic", &"gold", &"heal"]:
			return null
		var optional := value.children[1]
		var content_id: OptionalStringNameValue = null
		if optional.optional_present:
			if optional.children.size() != 1:
				return null
			content_id = OptionalStringNameValue.of(StringName(optional.children[0].string_value))
		var weight := value.children[2].int_value
		if weight <= 0 or (kind in [&"unit", &"item", &"relic"] and content_id == null):
			continue
		var conditions: Array[RewardConditionRule] = []
		for condition_value: ContentValue in value.children[3].children:
			var condition := _decode_reward_condition(condition_value)
			if condition == null:
				return null
			conditions.append(condition)
		candidates.append(RewardCandidateRule.new(
			kind, content_id, weight, 1, conditions
		))
	var draw_count := view.payload.children[4].int_value
	if candidates.is_empty() or draw_count < 1:
		return null
	return RewardTableRule.new(view.content_id, candidates, draw_count)

func _decode_reward_condition(value: ContentValue) -> RewardConditionRule:
	if value == null or value.record_type != 0x2002 or value.children.size() != 6 \
		or not value.children[3].optional_present:
		return null
	var stable_id: OptionalStringNameValue = null
	if value.children[4].optional_present:
		stable_id = OptionalStringNameValue.of(
			StringName(value.children[4].children[0].string_value)
		)
	return RewardConditionRule.new(
		StringName(value.children[0].string_value),
		value.children[3].children[0].int_value,
		stable_id
	)

func _pairs(value: ContentValue) -> Array[EconomyValueRule]:
	var result: Array[EconomyValueRule] = []
	if value == null:
		return result
	for item: ContentValue in value.children:
		if item.record_type != 0x200e or item.children.size() != 2:
			return []
		result.append(EconomyValueRule.new(item.children[0].int_value, item.children[1].int_value))
	return result

func _valid_config(config: EconomyConfigRule) -> bool:
	if config.layer_income.is_empty() or config.interest_step_gold < 1 \
		or config.gold_cap < 1 or config.reroll_cost < 0 \
		or config.xp_buy_cost < 1 or config.xp_buy_amount < 1:
		return false
	for level: int in range(3, 10):
		var odds := config.try_odds_for_level(level)
		if odds == null or odds.tier_basis_points.size() != 5:
			return false
		var total := 0
		for value: int in odds.tier_basis_points: total += value
		if total != 10000:
			return false
	for tier: int in range(1, 6):
		if config.value_for(config.pool_copies_by_tier, tier, -1) < 0 \
			or config.value_for(config.unit_costs_by_tier, tier, -1) < 1:
			return false
	# W5 雙審 B5 裁定修正：與 ContentValidator._validate_economy() 同步——新遠征從
	# economy level 1 起步(RunBootstrapService.STARTING_ECONOMY_LEVEL)，門檻須覆蓋 1..8。
	for level: int in range(1, 9):
		if config.value_for(config.xp_thresholds, level, -1) < 1:
			return false
	return true
