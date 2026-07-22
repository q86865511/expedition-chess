class_name EconomyExpeditionCatalog
extends RefCounted

var _manifest_digest: String
var _config: EconomyConfigRule
var _shop_units: Array[ShopUnitRule] = []
var _map_nodes: Array[MapNodeRule] = []
var _reward_tables: Array[RewardTableRule] = []

func _init(
	p_manifest_digest: String,
	p_config: EconomyConfigRule,
	p_shop_units: Array[ShopUnitRule],
	p_map_nodes: Array[MapNodeRule],
	p_reward_tables: Array[RewardTableRule] = []
) -> void:
	_manifest_digest = p_manifest_digest
	_config = p_config.deep_clone()
	for rule: ShopUnitRule in p_shop_units: _shop_units.append(rule.deep_clone())
	for rule: MapNodeRule in p_map_nodes: _map_nodes.append(rule.deep_clone())
	for rule: RewardTableRule in p_reward_tables: _reward_tables.append(rule.deep_clone())

func manifest_digest_value() -> String:
	return _manifest_digest

func config() -> EconomyConfigRule:
	return _config.deep_clone()

func shop_units() -> Array[ShopUnitRule]:
	var result: Array[ShopUnitRule] = []
	for rule: ShopUnitRule in _shop_units: result.append(rule.deep_clone())
	return result

func try_shop_unit(unit_id: StringName) -> ShopUnitRule:
	for rule: ShopUnitRule in _shop_units:
		if rule.unit_id == unit_id:
			return rule.deep_clone()
	return null

func map_nodes_for(kind: MapNodeState.NodeKind) -> Array[MapNodeRule]:
	var result: Array[MapNodeRule] = []
	for rule: MapNodeRule in _map_nodes:
		if rule.node_kind == kind:
			result.append(rule.deep_clone())
	return result

func try_map_node(definition_id: StringName) -> MapNodeRule:
	for rule: MapNodeRule in _map_nodes:
		if rule.definition_id == definition_id:
			return rule.deep_clone()
	return null

func reward_tables() -> Array[RewardTableRule]:
	var result: Array[RewardTableRule] = []
	for rule: RewardTableRule in _reward_tables:
		result.append(rule.deep_clone())
	return result

func try_reward_table(stage: PendingRewardState.StageId) -> RewardTableRule:
	for rule: RewardTableRule in _reward_tables:
		if rule.supports_stage(stage):
			return rule.deep_clone()
	return null

func create_initial_pool() -> UnitPoolState:
	var entries: Array[UnitPoolEntryState] = []
	for rule: ShopUnitRule in _shop_units:
		var copies := _config.value_for(_config.pool_copies_by_tier, rule.cost_tier, 0)
		entries.append(UnitPoolEntryState.new(rule.unit_id, copies, copies, 0, 0))
	return UnitPoolState.new(entries)

func deep_clone() -> EconomyExpeditionCatalog:
	return EconomyExpeditionCatalog.new(
		_manifest_digest, _config, _shop_units, _map_nodes, _reward_tables
	)
