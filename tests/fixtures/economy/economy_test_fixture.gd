class_name EconomyTestFixture
extends RefCounted

const MANIFEST: String = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

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
	var thresholds := [4, 8, 16, 28, 44, 64]
	for level: int in range(3, 9):
		config.xp_thresholds.append(EconomyValueRule.new(level, thresholds[level - 3]))
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
			_encounter_id_for_kind(kind)
		))
	return EconomyExpeditionCatalog.new(manifest_digest, config, units, nodes)

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
			_encounter_id_for_kind(kind)
		))
	return EconomyExpeditionCatalog.new(manifest_digest, source.config(), units, nodes)

static func settlement_catalog(manifest_digest: String) -> EconomyExpeditionCatalog:
	var source := catalog(manifest_digest)
	var units: Array[ShopUnitRule] = [ShopUnitRule.new(&"unit.fixture", 1, 1)]
	var nodes: Array[MapNodeRule] = []
	for kind: int in range(7):
		nodes.append(MapNodeRule.new(
			StringName("mapnode.fixture_%d" % kind), kind,
			_encounter_id_for_kind(kind)
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
		manifest_digest, source.config(), units, nodes, tables
	)

static func mixed_reward_catalog(manifest_digest: String) -> EconomyExpeditionCatalog:
	var source := settlement_catalog(manifest_digest)
	var units: Array[ShopUnitRule] = [ShopUnitRule.new(&"unit.fixture", 1, 1)]
	var nodes: Array[MapNodeRule] = []
	for kind: int in range(7):
		nodes.append(MapNodeRule.new(
			StringName("mapnode.fixture_%d" % kind), kind,
			_encounter_id_for_kind(kind)
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
		manifest_digest, source.config(), units, nodes, tables
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
	return EconomyExpeditionCatalog.new(
		manifest_digest, source.config(), source.shop_units(), nodes, tables
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

static func _encounter_id_for_kind(kind: int) -> StringName:
	match kind:
		MapNodeState.NodeKind.NORMAL:
			return &"encounter.normal"
		MapNodeState.NodeKind.ELITE:
			return &"encounter.elite"
		MapNodeState.NodeKind.BOSS:
			return &"encounter.boss"
	return &""

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
