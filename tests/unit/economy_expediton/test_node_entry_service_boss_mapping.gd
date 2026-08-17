extends GutTest

## G2 difficulty-curve T02（specs/difficulty-curve/requirements.md DC-REQ-002、
## design.md「Boss 映射」段）：Boss 節點的 encounter 必須由 node.act_index 決定性映射至
## encounter.slice_boss_0/1/2（act1/2/3），非 boss 節點不受影響，且映射表外／pin 集合缺漏
## 必須以既有具名錯誤 fail-closed，不得 fallback 回 slice_boss_0。

const BOSS_ENCOUNTER_IDS: Array[StringName] = [
	&"encounter.slice_boss_0", &"encounter.slice_boss_1", &"encounter.slice_boss_2",
]

func test_boss_node_encounter_is_decided_by_act_index() -> void:
	var fixture := _fixture()
	var battle_catalog := _battle_catalog(fixture.manifest, BOSS_ENCOUNTER_IDS)
	for act_index: int in range(1, 4):
		var target := _boss_node(fixture.map, act_index)
		assert_not_null(target, "act%d should have a boss node" % act_index)
		if target == null: continue
		_make_reachable(fixture.root.run, target)
		var result := NodeEntryService.new().enter(
			fixture.root.run, target.node_id, fixture.catalog, battle_catalog
		)
		assert_true(result.ok, "act%d: %s:%s" % [
			act_index,
			String(result.error.code) if result.error != null else "none",
			String(result.error.field_path) if result.error != null else "none",
		])
		if not result.ok: continue
		var entered_node := _node_by_id(result.draft, target.node_id)
		assert_not_null(entered_node.encounter_preview)
		if entered_node.encounter_preview == null: continue
		assert_eq(
			entered_node.encounter_preview.encounter_id, BOSS_ENCOUNTER_IDS[act_index - 1],
			"act%d boss must compile to %s" % [act_index, String(BOSS_ENCOUNTER_IDS[act_index - 1])]
		)

func test_non_boss_node_encounter_id_is_unaffected_by_act_mapping() -> void:
	var fixture := _fixture()
	var ids: Array[StringName] = [&"encounter.normal"]
	ids.append_array(BOSS_ENCOUNTER_IDS)
	var battle_catalog := _battle_catalog(fixture.manifest, ids)
	var target := _first_node_of_kind(fixture.map, MapNodeState.NodeKind.NORMAL, 1)
	assert_not_null(target)
	if target == null: return
	# 還沒進過任何節點（current_node_id 為 null、completed_node_ids 為空）時，frontier
	# ＝ act1 layer0 的起始集合，這個 normal 節點因此可進入（MapFrontier）。
	var result := NodeEntryService.new().enter(
		fixture.root.run, target.node_id, fixture.catalog, battle_catalog
	)
	assert_true(result.ok, "%s:%s" % [
		String(result.error.code) if result.error != null else "none",
		String(result.error.field_path) if result.error != null else "none",
	])
	if not result.ok: return
	var entered_node := _node_by_id(result.draft, target.node_id)
	assert_not_null(entered_node.encounter_preview)
	if entered_node.encounter_preview == null: return
	assert_eq(entered_node.encounter_preview.encounter_id, &"encounter.normal")

## AC 2（DC-REQ-002）：把 slice_boss_1 自 pinned battle_catalog 移除，act2 Boss 節點必須以
## 既有具名錯誤 fail-closed，不得 fallback 回 slice_boss_0——藉此驗證覆寫邏輯不吃靜默降級。
func test_boss_node_fails_closed_when_pinned_encounter_missing_for_act() -> void:
	var fixture := _fixture()
	var partial_ids: Array[StringName] = [&"encounter.slice_boss_0", &"encounter.slice_boss_2"]
	var battle_catalog := _battle_catalog(fixture.manifest, partial_ids)
	var target := _boss_node(fixture.map, 2)
	assert_not_null(target)
	if target == null: return
	_make_reachable(fixture.root.run, target)
	var result := NodeEntryService.new().enter(
		fixture.root.run, target.node_id, fixture.catalog, battle_catalog
	)
	assert_false(result.ok)
	if result.ok: return
	assert_eq(result.error.code, NodeEntryError.ENCOUNTER_COMPILE_FAILED)
	assert_null(result.draft)

func test_boss_node_fails_closed_for_act_outside_fixed_table() -> void:
	var fixture := _fixture()
	var battle_catalog := _battle_catalog(fixture.manifest, BOSS_ENCOUNTER_IDS)
	var target := _boss_node(fixture.map, 1)
	assert_not_null(target)
	if target == null: return
	target.act_index = 4
	_make_reachable(fixture.root.run, target)
	var result := NodeEntryService.new().enter(
		fixture.root.run, target.node_id, fixture.catalog, battle_catalog
	)
	assert_false(result.ok)
	if result.ok: return
	assert_eq(result.error.code, NodeEntryError.ENCOUNTER_COMPILE_FAILED)
	assert_eq(result.error.field_path, &"map_node.act_index")

class _Fixture:
	var root: SaveRoot
	var catalog: EconomyExpeditionCatalog
	var map: MapState
	var manifest: String

func _fixture() -> _Fixture:
	var result := _Fixture.new()
	result.root = SaveRootFixture.create_valid_root()
	result.manifest = result.root.run.content_snapshot.manifest_digest_value()
	result.catalog = EconomyTestFixture.save_fixture_catalog(result.manifest)
	result.root.run.run_phase = RunState.RunPhase.MAP
	result.root.run.current_node_id = null
	result.root.run.resolution_state = IdleResolutionState.new()
	result.root.run.economy_state = EconomyState.new(47, 3, 0, 5, 0, 0, [])
	result.root.run.unit_pool_state = result.catalog.create_initial_pool()
	result.root.run.unit_pool_state.entries[0].remaining_copies -= 1
	result.root.run.unit_pool_state.entries[0].held_copies = 1
	var no_equipment: Array[String] = []
	var unit := UnitInstance.new(
		"u_0000000000000001", &"unit.fixture", 1, no_equipment, U64Bits.one()
	)
	var placements: Array[BoardPlacementState] = [BoardPlacementState.new(3, 3, unit.instance_id)]
	var bench: Array[String] = []
	var units: Array[UnitInstance] = [unit]
	var items: Array[ItemInstanceState] = []
	var item_ids: Array[String] = []
	var relics: Array[RelicSlotState] = []
	for index: int in range(5): relics.append(RelicSlotState.new(index, null))
	result.root.run.roster_state = RosterState.new(
		BoardState.new(placements), bench, units, items, item_ids, item_ids, relics
	)
	result.root.run.reservation_owners.clear()
	result.root.run.transaction_receipts.clear()
	result.root.run.income_claimed_node_ids.clear()
	result.root.run.next_transaction_serial = U64Bits.zero()
	result.root.run.next_unit_serial = U64Bits.from_u32(0, 2).value
	var generated := MapService.new().generate_map(MapGenerationRequest.new(
		StringName(result.root.run.run_id), result.root.run.run_seed, result.catalog
	))
	assert_true(generated.ok, "map generation fixture must succeed")
	result.map = generated.map_state
	result.root.run.map_state = generated.map_state
	return result

func _boss_node(map: MapState, act_index: int) -> MapNodeState:
	return _first_node_of_kind(map, MapNodeState.NodeKind.BOSS, act_index)

func _first_node_of_kind(map: MapState, kind: MapNodeState.NodeKind, act_index: int) -> MapNodeState:
	for node: MapNodeState in map.nodes:
		if node.node_kind == kind and node.act_index == act_index:
			return node
	return null

## 可進入的節點只有「目前所在節點的出邊」（MapFrontier），所以 fixture 要把前驅同時
## 標成已完成**並**設為所在節點——這正是走完該節點後的真實狀態。boss 節點所在層恆有
## 唯一前驅（layer 5，size 1），故一跳即可，不必重演整條 act 內的通關鏈。
func _make_reachable(run: RunState, target: MapNodeState) -> void:
	for edge: MapEdgeState in run.map_state.edges:
		if edge.to_node_id == target.node_id:
			run.map_state.completed_node_ids = [edge.from_node_id]
			run.current_node_id = OptionalStringValue.new(edge.from_node_id)
			run.map_state.current_node_id = OptionalStringValue.new(edge.from_node_id)
			return
	fail_test("no edge leads to target node %s" % target.node_id)

func _node_by_id(run: RunState, node_id: String) -> MapNodeState:
	for node: MapNodeState in run.map_state.nodes:
		if node.node_id == node_id:
			return node
	return null

## 比照 EconomyTestFixture.expedition_battle_catalog：每個 encounter_id 掛一隻敵方 spawn；
## slice_boss_* 額外附一段 boss phase（BossPhaseDef.source_spawn_key 沿用 spawn_key 慣例）。
func _battle_catalog(manifest: String, encounter_ids: Array[StringName]) -> BattleRuleCatalog:
	var enemy := _battle_unit(&"unit.enemy")
	var player := _battle_unit(&"unit.fixture")
	var encounters: Array[BattleEncounterRule] = []
	for encounter_id: StringName in encounter_ids:
		var spawn := BattleEnemySpawnRule.new()
		spawn.side = &"enemy"
		spawn.logical_y = 6
		spawn.logical_x = 3
		spawn.spawn_key = "enemy_0"
		spawn.unit_id = enemy.unit_id
		spawn.star = 1
		var encounter := BattleEncounterRule.new()
		encounter.encounter_id = encounter_id
		var is_boss := String(encounter_id).begins_with("encounter.slice_boss")
		encounter.encounter_kind = &"boss" if is_boss else &"normal"
		encounter.preview_schema_version = 1
		encounter.enemy_spawns = [spawn]
		if is_boss:
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
		manifest, units, traits, abilities, effects, encounters, equipment, configs
	)

func _battle_unit(unit_id: StringName) -> BattleUnitRule:
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
