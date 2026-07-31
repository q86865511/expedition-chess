class_name EconomyTestFixture
extends RefCounted

const MANIFEST: String = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

# G2 content-production（specs/content-production/design.md §5）：event／rest／treasure
# 進入節點時必須解得出 node choice set，否則 EnterNodeEvent fail-closed
# （enter_node_event.gd:79-84）。fixture 的 map node 規則因此比照正式內容
# （content/packs/vertical_slice/map_nodes/*.tres）把 generator 指向 choice_set.*。
const EVENT_CHOICE_SET_ID: StringName = &"choice_set.event"
const REST_CHOICE_SET_ID: StringName = &"choice_set.rest"
const TREASURE_CHOICE_SET_ID: StringName = &"choice_set.treasure"

static func catalog(manifest_digest: String = MANIFEST) -> EconomyExpeditionCatalog:
	var config := EconomyConfigRule.new()
	config.config_id = &"economy.test"
	config.layer_income = [EconomyValueRule.new(0, 5)]
	config.interest_step_gold = 10
	config.interest_per_step = 1
	config.max_interest = 5
	config.gold_cap = 99
	config.reroll_cost = 2
	config.xp_buy_cost = 4
	config.xp_buy_amount = 4
	config.streak_rewards = [EconomyValueRule.new(3, 1), EconomyValueRule.new(5, 2)]
	config.loss_subsidy = [EconomyValueRule.new(2, 3)]
	for level: int in range(3, 10):
		config.shop_odds_by_level.append(ShopOddsRule.new(level, [10000, 0, 0, 0, 0]))
	var copies := [18, 15, 12, 10, 9]
	for tier: int in range(1, 6):
		config.pool_copies_by_tier.append(EconomyValueRule.new(tier, copies[tier - 1]))
		config.unit_costs_by_tier.append(EconomyValueRule.new(tier, tier))
	# W5 雙審 B5 裁定修正：門檻須覆蓋 level 1..8（新遠征從 economy level 1 起步），
	# 比照 slice_default.tres 的曲線在 3..8 之前補 1=2、2=3。
	var thresholds := [2, 3, 4, 8, 16, 28, 44, 64]
	for level: int in range(1, 9):
		config.xp_thresholds.append(EconomyValueRule.new(level, thresholds[level - 1]))
	var units: Array[ShopUnitRule] = [
		ShopUnitRule.new(&"unit.test_a", 1, 1),
		ShopUnitRule.new(&"unit.test_b", 1, 1),
	]
	var nodes: Array[MapNodeRule] = []
	var tokens: Array[StringName] = [&"normal", &"elite", &"merchant", &"event", &"rest", &"treasure", &"boss"]
	for kind: int in range(tokens.size()):
		nodes.append(MapNodeRule.new(
			StringName("map_node.%s" % String(tokens[kind])),
			kind,
			_generator_id_for_kind(kind)
		))
	var no_tables: Array[RewardTableRule] = []
	return EconomyExpeditionCatalog.new(
		manifest_digest, config, units, nodes, no_tables, node_choice_sets()
	)

static func empty_roster() -> RosterState:
	var placements: Array[BoardPlacementState] = []
	var strings: Array[String] = []
	var units: Array[UnitInstance] = []
	var items: Array[ItemInstanceState] = []
	var relics: Array[RelicSlotState] = []
	for index: int in range(5): relics.append(RelicSlotState.new(index, null))
	return RosterState.new(BoardState.new(placements), strings, units, items, strings, strings, relics)

static func battle_catalog(manifest_digest: String = MANIFEST) -> BattleRuleCatalog:
	var units: Array[BattleUnitRule] = []
	var traits: Array[BattleTraitRule] = []
	var abilities: Array[BattleAbilityRule] = []
	var effects: Array[BattleEffectRule] = []
	var encounters: Array[BattleEncounterRule] = []
	var equipment: Array[BattleEquipmentRule] = []
	var configs: Array[BattleCombatConfigRule] = []
	return BattleRuleCatalog.new(manifest_digest, units, traits, abilities, effects, encounters, equipment, configs)

static func save_fixture_catalog(manifest_digest: String) -> EconomyExpeditionCatalog:
	var source := catalog(manifest_digest)
	var units: Array[ShopUnitRule] = [ShopUnitRule.new(&"unit.fixture", 1, 1)]
	var nodes: Array[MapNodeRule] = []
	for kind: int in range(7):
		nodes.append(MapNodeRule.new(
			StringName("mapnode.fixture_%d" % kind),
			kind,
			_generator_id_for_kind(kind)
		))
	var no_tables: Array[RewardTableRule] = []
	return EconomyExpeditionCatalog.new(
		manifest_digest, source.config(), units, nodes, no_tables, node_choice_sets()
	)

static func settlement_catalog(manifest_digest: String) -> EconomyExpeditionCatalog:
	var source := catalog(manifest_digest)
	var units: Array[ShopUnitRule] = [ShopUnitRule.new(&"unit.fixture", 1, 1)]
	var nodes: Array[MapNodeRule] = []
	for kind: int in range(7):
		nodes.append(MapNodeRule.new(
			StringName("mapnode.fixture_%d" % kind), kind,
			_generator_id_for_kind(kind)
		))
	var standard_candidates: Array[RewardCandidateRule] = [
		RewardCandidateRule.new(&"gold", null, 1, 3),
	]
	var relic_candidates: Array[RewardCandidateRule] = [
		RewardCandidateRule.new(
			&"relic", OptionalStringNameValue.of(&"relic.fixture"), 1, 1
		),
	]
	var tables: Array[RewardTableRule] = [
		RewardTableRule.new(&"reward.standard", standard_candidates, 3),
		RewardTableRule.new(&"reward.relic", relic_candidates, 3),
	]
	return EconomyExpeditionCatalog.new(
		manifest_digest, source.config(), units, nodes, tables,
		node_choice_sets(&"reward.standard", &"reward.standard")
	)

static func mixed_reward_catalog(manifest_digest: String) -> EconomyExpeditionCatalog:
	var source := settlement_catalog(manifest_digest)
	var units: Array[ShopUnitRule] = [ShopUnitRule.new(&"unit.fixture", 1, 1)]
	var nodes: Array[MapNodeRule] = []
	for kind: int in range(7):
		nodes.append(MapNodeRule.new(
			StringName("mapnode.fixture_%d" % kind), kind,
			_generator_id_for_kind(kind)
		))
	var standard_candidates: Array[RewardCandidateRule] = [
		RewardCandidateRule.new(
			&"unit", OptionalStringNameValue.of(&"unit.fixture"), 1000000, 1
		),
		RewardCandidateRule.new(&"gold", null, 1, 3),
	]
	var relic_candidates: Array[RewardCandidateRule] = [
		RewardCandidateRule.new(
			&"relic", OptionalStringNameValue.of(&"relic.fixture"), 1, 1
		),
	]
	var tables: Array[RewardTableRule] = [
		RewardTableRule.new(&"reward.standard", standard_candidates, 3),
		RewardTableRule.new(&"reward.relic", relic_candidates, 3),
	]
	return EconomyExpeditionCatalog.new(
		manifest_digest, source.config(), units, nodes, tables,
		node_choice_sets(&"reward.standard", &"reward.standard")
	)

static func event_unit_reward_catalog(manifest_digest: String) -> EconomyExpeditionCatalog:
	var source := settlement_catalog(manifest_digest)
	var event_candidates: Array[RewardCandidateRule] = [
		RewardCandidateRule.new(
			&"unit", OptionalStringNameValue.of(&"unit.fixture"), 1, 1
		),
	]
	var event_table := RewardTableRule.new(
		&"reward.event_unit", event_candidates, 3
	)
	var tables: Array[RewardTableRule] = [event_table]
	tables.append_array(source.reward_tables())
	var nodes: Array[MapNodeRule] = []
	for kind: int in range(7):
		nodes.append_array(source.map_nodes_for(kind))
	# event 節點的 grant 選項指向本 catalog 專屬的 unit-only 表，commit 後才會落在
	# EVENT_GRANT stage（reward_service.gd 的單一 offer／保留副本路徑）。
	return EconomyExpeditionCatalog.new(
		manifest_digest, source.config(), source.shop_units(), nodes, tables,
		node_choice_sets(&"reward.event_unit", &"reward.standard")
	)

static func shop_rng() -> RngSnapshot:
	var seed := U64Bits.from_hex("0123456789abcdef")
	var derived := RngService.new().derive_stream(seed.value, &"shop", &"run_fixture:shop_v1")
	assert(derived.ok)
	return derived.snapshot

static func expedition_battle_catalog(
	manifest_digest: String = MANIFEST
) -> BattleRuleCatalog:
	var enemy := _battle_unit(&"unit.enemy")
	var player := _battle_unit(&"unit.fixture")
	var encounters: Array[BattleEncounterRule] = []
	for kind: StringName in [&"normal", &"elite", &"boss"]:
		var spawn := BattleEnemySpawnRule.new()
		spawn.side = &"enemy"
		spawn.logical_y = 6
		spawn.logical_x = 3
		spawn.spawn_key = "enemy_0"
		spawn.unit_id = enemy.unit_id
		spawn.star = 1
		var encounter := BattleEncounterRule.new()
		encounter.encounter_id = StringName("encounter.%s" % String(kind))
		encounter.encounter_kind = kind
		encounter.preview_schema_version = 1
		encounter.enemy_spawns = [spawn]
		if kind == &"boss":
			var phase := BattleBossPhaseRule.new()
			phase.phase_index = 0
			phase.hp_threshold_bps = 5000
			phase.source_spawn_key = spawn.spawn_key
			encounter.boss_phases = [phase]
		encounters.append(encounter)
	var config := BattleCombatConfigRule.new()
	config.config_id = &"config.combat_default"
	var defaults := BattleRulesSnapshot.new()
	for property: StringName in BattleCombatConfigRule._integer_properties():
		config.set(property, defaults.get(property))
	var units: Array[BattleUnitRule] = [enemy, player]
	var traits: Array[BattleTraitRule] = []
	var abilities: Array[BattleAbilityRule] = []
	var effects: Array[BattleEffectRule] = []
	var equipment: Array[BattleEquipmentRule] = []
	var configs: Array[BattleCombatConfigRule] = [config]
	return BattleRuleCatalog.new(
		manifest_digest, units, traits, abilities, effects,
		encounters, equipment, configs
	)

## 戰鬥節點的 generator 是 encounter id（NodeEntryService 用它 compile preview），
## event／rest／treasure 的 generator 是 choice set id（EnterNodeEvent 用它開
## NodeChoicePendingState）。merchant 兩者皆無，維持空字串。
static func _generator_id_for_kind(kind: int) -> StringName:
	match kind:
		MapNodeState.NodeKind.NORMAL:
			return &"encounter.normal"
		MapNodeState.NodeKind.ELITE:
			return &"encounter.elite"
		MapNodeState.NodeKind.BOSS:
			return &"encounter.boss"
		MapNodeState.NodeKind.EVENT:
			return EVENT_CHOICE_SET_ID
		MapNodeState.NodeKind.REST:
			return REST_CHOICE_SET_ID
		MapNodeState.NodeKind.TREASURE:
			return TREASURE_CHOICE_SET_ID
	return &""

## 比照 content/packs/vertical_slice/node_choices/*.tres 的形狀組出測試用 choice set。
## reward table ref 給空字串（base catalog 沒有 reward table）時只產生
## APPLY_AND_COMPLETE 選項，commit 才不會落到不存在的 table；每個 set 至少兩個選項，
## 符合 CommitNodeChoiceService.begin 的下限。
static func node_choice_sets(
	event_reward_table_ref: StringName = &"",
	treasure_reward_table_ref: StringName = &""
) -> Array[NodeChoiceSetRule]:
	var no_operations: Array[NodeChoiceOperationRule] = []
	var event_safe: Array[NodeChoiceOperationRule] = [_gold_operation(1, 0)]
	var event_risk: Array[NodeChoiceOperationRule] = [
		_gold_operation(3, 0), _drain_operation(5, 1)
	]
	var event_choices: Array[NodeChoiceRule] = [
		_choice(&"choice.event.safe", 0, event_safe, &""),
		_choice(&"choice.event.risk", 1, event_risk, &""),
	]
	if not event_reward_table_ref.is_empty():
		event_choices.append(_choice(
			&"choice.event.grant", 2, no_operations, event_reward_table_ref
		))
	var rest_long: Array[NodeChoiceOperationRule] = [_heal_operation(20, 0)]
	var rest_short: Array[NodeChoiceOperationRule] = [_heal_operation(5, 0)]
	var rest_choices: Array[NodeChoiceRule] = [
		_choice(&"choice.rest.heal_20", 0, rest_long, &""),
		_choice(&"choice.rest.heal_5", 1, rest_short, &""),
	]
	var treasure_cache: Array[NodeChoiceOperationRule] = [_gold_operation(3, 0)]
	var treasure_coin: Array[NodeChoiceOperationRule] = [_gold_operation(1, 0)]
	var treasure_choices: Array[NodeChoiceRule] = [
		_choice(&"choice.treasure.gold", 0, treasure_cache, &""),
		_choice(&"choice.treasure.coin", 1, treasure_coin, &""),
	]
	if not treasure_reward_table_ref.is_empty():
		treasure_choices.append(_choice(
			&"choice.treasure.standard", 2, no_operations,
			treasure_reward_table_ref
		))
	var result: Array[NodeChoiceSetRule] = [
		NodeChoiceSetRule.new(
			EVENT_CHOICE_SET_ID, &"loc.choice_set_event", &"event", event_choices
		),
		NodeChoiceSetRule.new(
			REST_CHOICE_SET_ID, &"loc.choice_set_rest", &"rest", rest_choices
		),
		NodeChoiceSetRule.new(
			TREASURE_CHOICE_SET_ID, &"loc.choice_set_treasure", &"treasure",
			treasure_choices
		),
	]
	return result

static func _choice(
	choice_id: StringName,
	sort_order: int,
	operations: Array[NodeChoiceOperationRule],
	reward_table_ref: StringName
) -> NodeChoiceRule:
	var token := String(choice_id).replace(".", "_")
	var opens_reward := not reward_table_ref.is_empty()
	var outcome_kind := NodeChoiceRule.OUTCOME_APPLY_AND_COMPLETE
	if opens_reward:
		outcome_kind = NodeChoiceRule.OUTCOME_OPEN_REWARD_STAGE
	return NodeChoiceRule.new(
		choice_id,
		sort_order,
		StringName("loc.%s_title" % token),
		StringName("loc.%s_description" % token),
		StringName("loc.%s_preview" % token),
		StringName("loc.%s_result" % token),
		operations,
		reward_table_ref,
		opens_reward,
		outcome_kind,
		true
	)

static func _gold_operation(amount: int, index: int) -> NodeChoiceOperationRule:
	return NodeChoiceOperationRule.new(
		NodeChoiceOperationRule.Kind.ADD_GOLD, amount, index, &"once_per_node"
	)

static func _heal_operation(amount: int, index: int) -> NodeChoiceOperationRule:
	return NodeChoiceOperationRule.new(
		NodeChoiceOperationRule.Kind.HEAL_EXPEDITION_HP, amount, index,
		&"once_per_node"
	)

static func _drain_operation(amount: int, index: int) -> NodeChoiceOperationRule:
	return NodeChoiceOperationRule.new(
		NodeChoiceOperationRule.Kind.DRAIN_EXPEDITION_HP, amount, index,
		&"once_per_node"
	)

static func _battle_unit(unit_id: StringName) -> BattleUnitRule:
	var unit := BattleUnitRule.new()
	unit.unit_id = unit_id
	unit.basic_attack_profile = &"melee"
	unit.base_stats = BattleUnitStatsRule.new()
	unit.base_stats.health = 100
	unit.base_stats.attack = 10
	unit.base_stats.armor = 5
	unit.base_stats.magic_resist = 5
	unit.base_stats.attack_speed_milli = 1000
	unit.base_stats.attack_range_cells = 1
	unit.base_stats.start_mana = 0
	unit.base_stats.max_mana = 100
	unit.base_stats.move_speed_milli = 1000
	for star: int in range(1, 4):
		var scaling := BattleStarScalingRule.new()
		scaling.star = star
		scaling.health_bps = [10000, 18000, 32000][star - 1]
		scaling.attack_bps = scaling.health_bps
		scaling.armor_bps = scaling.health_bps
		scaling.magic_resist_bps = scaling.health_bps
		scaling.attack_speed_bps = 10000
		scaling.attack_range_bps = 10000
		scaling.start_mana_bps = 10000
		scaling.max_mana_bps = 10000
		scaling.move_speed_bps = 10000
		unit.star_scalings.append(scaling)
	return unit

static func empty_owners() -> Array[ReservationOwnerState]:
	var result: Array[ReservationOwnerState] = []
	return result
