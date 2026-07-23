extends GutTest

## T05 / S4-AC-008 (specs/build-systems/design.md §5.4): pending_item_overflow
## non-empty is a hard gate -- it must reject both starting combat and leaving
## PREPARE (resolving a non-combat node), guaranteeing the tray can never be
## bypassed into a softlock. Mirrors the phase-gate precedent already enforced
## for reward resolution (run_state_validator.gd:565,584 -- READY_TO_ADVANCE
## requires an empty tray) by extending the same invariant to the two other
## PREPARE exits: StartCombatEvent and ResolveNonCombatNodeCommand.
##
## Contract under test (test-author decision, since design.md does not pin an
## exact named error code for these two gates): both events/commands must
## reject with a "source_code" diagnostic naming the overflow condition (read
## via EquipDismantleTestFixture.error_source_code()) and must leave
## run_phase/resolution_state untouched -- exactly like every other named
## rejection path in this codebase's command/event convention. Both are
## exercised directly through their own apply_to()/resolve() (the same
## unit-level style already used for ForgeEquipmentCommand/EquipItemCommand
## and for RewardService.resolve_item() in
## tests/unit/economy_expediton/test_battle_settlement_and_rewards.gd) rather
## than the full RunController pipeline, since the gate itself has no save/load
## concern -- that is covered separately by
## tests/integration/build_items/test_sell_equipped_unit_crash_load.gd.

func test_start_combat_event_rejects_when_overflow_tray_is_non_empty() -> void:
	var fixture := _combat_fixture()
	var run: RunState = fixture["run"]
	var overflow_id := "it_0000000000000099"
	run.roster_state.item_instances.append(ItemInstanceState.new(
		overflow_id, &"unit.hero", null, U64Bits.from_u32(0, 99).value
	))
	run.roster_state.pending_item_overflow = [overflow_id]
	var before_phase := run.run_phase

	var result := StartCombatEvent.new(fixture["catalog"], fixture["sources"]).apply_to(run)
	assert_false(result.ok)
	assert_eq(EquipDismantleTestFixture.error_source_code(result), "START_COMBAT_OVERFLOW_PENDING")
	assert_eq(run.run_phase, before_phase)
	assert_true(run.resolution_state is IdleResolutionState)
	assert_true(run.roster_state.pending_item_overflow.has(overflow_id))

func test_resolve_non_combat_node_rejects_when_overflow_tray_is_non_empty() -> void:
	var run := _rest_node_run()
	var catalog := EconomyTestFixture.settlement_catalog(
		run.content_snapshot.manifest_digest_value()
	)
	var overflow_id := "it_0000000000000099"
	run.roster_state.item_instances.append(ItemInstanceState.new(
		overflow_id, &"unit.fixture", null, U64Bits.from_u32(0, 99).value
	))
	run.roster_state.pending_item_overflow = [overflow_id]
	var before_phase := run.run_phase
	var before_completed := run.map_state.completed_node_ids.duplicate()

	var result := ResolveNonCombatNodeCommand.new(catalog).apply_to(run)
	assert_false(result.ok)
	assert_eq(
		EquipDismantleTestFixture.error_source_code(result),
		"NON_COMBAT_NODE_OVERFLOW_PENDING"
	)
	assert_eq(run.run_phase, before_phase)
	assert_eq(run.map_state.completed_node_ids, before_completed)
	assert_true(run.roster_state.pending_item_overflow.has(overflow_id))

## Minimal single-normal-node PREPARE-phase combat fixture mirroring
## tests/unit/combat_transactions/test_combat_transaction_commands.gd's
## _prepare_fixture(), trimmed to only what StartCombatEvent needs.
func _combat_fixture() -> Dictionary:
	var root := SaveRootFixture.create_valid_root()
	var run := root.run
	run.run_phase = RunState.RunPhase.PREPARE
	run.act_index = 1
	run.resolution_state = IdleResolutionState.new()
	var player := UnitBattleSnapshot.new()
	player.instance_id = &"u_0000000000000001"
	player.unit_id = &"unit.hero"
	player.side = &"player"
	player.logical_y = 3
	player.logical_x = 3
	player.health = 120
	player.attack = 20
	player.attack_speed_milli = 1000
	player.attack_range_cells = 1
	player.max_mana = 0
	player.move_speed_milli = 1000
	var enemy := UnitBattleSnapshot.new()
	enemy.instance_id = &"e_0000000000000001"
	enemy.unit_id = &"unit.foe"
	enemy.side = &"enemy"
	enemy.logical_y = 4
	enemy.logical_x = 3
	enemy.health = 30
	enemy.attack = 10
	enemy.attack_speed_milli = 1000
	enemy.attack_range_cells = 1
	enemy.max_mana = 0
	enemy.move_speed_milli = 1000
	var preview := EncounterPreviewSnapshot.new()
	preview.preview_schema_version = 1
	preview.encounter_id = &"encounter.test"
	preview.manifest_digest = StringName(SaveRootFixture.MANIFEST_DIGEST)
	preview.enemy_units.append(enemy)
	var node_key_result := RuntimeKeySchemaRegistry.new().build_node(
		StringName(run.run_id), 1, &"normal", 0, 0
	)
	assert_true(node_key_result.ok)
	var node_key := node_key_result.key_state as NodeKeyState
	var nodes: Array[MapNodeState] = [MapNodeState.new(
		String(node_key.digest), node_key, &"mapnode.fixture", 1, 0, 0,
		MapNodeState.NodeKind.NORMAL,
		"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
		preview, false
	)]
	var edges: Array[MapEdgeState] = []
	var completed: Array[String] = []
	run.map_state = MapState.new(
		nodes, edges, OptionalStringValue.new(String(node_key.digest)), completed
	)
	run.current_node_id = OptionalStringValue.new(String(node_key.digest))
	var placements: Array[BoardPlacementState] = [
		BoardPlacementState.new(3, 3, "u_0000000000000001")
	]
	var units: Array[UnitInstance] = [UnitInstance.new(
		"u_0000000000000001", &"unit.hero", 1, [], U64Bits.zero()
	)]
	var empty_strings: Array[String] = []
	var empty_items: Array[ItemInstanceState] = []
	var relics: Array[RelicSlotState] = []
	for index: int in range(5):
		relics.append(RelicSlotState.new(index, null))
	run.roster_state = RosterState.new(
		BoardState.new(placements), empty_strings, units, empty_items,
		empty_strings, empty_strings, relics
	)
	var battle_units: Array[BattleUnitRule] = []
	for id: StringName in [&"unit.foe", &"unit.hero"]:
		var unit_rule := BattleUnitRule.new()
		unit_rule.unit_id = id
		battle_units.append(unit_rule)
	var traits: Array[BattleTraitRule] = []
	var abilities: Array[BattleAbilityRule] = []
	var effects: Array[BattleEffectRule] = []
	var encounters: Array[BattleEncounterRule] = []
	var equipment: Array[BattleEquipmentRule] = []
	var config := BattleCombatConfigRule.new()
	config.config_id = &"config.combat_default"
	var defaults := BattleRulesSnapshot.new()
	for property: StringName in BattleCombatConfigRule._integer_properties():
		config.set(property, defaults.get(property))
	var configs: Array[BattleCombatConfigRule] = [config]
	var catalog := BattleRuleCatalog.new(
		SaveRootFixture.MANIFEST_DIGEST,
		battle_units, traits, abilities, effects, encounters, equipment, configs
	)
	var player_units: Array[UnitBattleSnapshot] = [player]
	var active_traits: Array[TraitBattleSnapshot] = []
	var empty_effects: Array[BattleEffectSnapshot] = []
	var sources := BattleSetupSourceBundle.new(
		SaveRootFixture.MANIFEST_DIGEST,
		player_units, active_traits, empty_effects, empty_effects,
		empty_effects, empty_effects,
		true, true, true, true, true, true
	)
	return {"run": run, "catalog": catalog, "sources": sources}

## Minimal PREPARE-phase RunState sitting on a single already-current REST
## node, pinned to SaveRootFixture's base receipt -- built directly (no map
## generation/reachability needed) since NonCombatNodeService.resolve() only
## inspects run_phase, resolution_state, and the current node's node_kind.
func _rest_node_run() -> RunState:
	var run := SaveRootFixture.create_valid_root().run
	run.run_phase = RunState.RunPhase.PREPARE
	run.resolution_state = IdleResolutionState.new()
	var node_key_result := RuntimeKeySchemaRegistry.new().build_node(
		StringName(run.run_id), 1, &"rest", 0, 0
	)
	assert_true(node_key_result.ok)
	var node_key := node_key_result.key_state as NodeKeyState
	var nodes: Array[MapNodeState] = [MapNodeState.new(
		String(node_key.digest), node_key, &"mapnode.fixture", 1, 0, 0,
		MapNodeState.NodeKind.REST,
		"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
		null, false
	)]
	var edges: Array[MapEdgeState] = []
	var completed: Array[String] = []
	run.map_state = MapState.new(
		nodes, edges, OptionalStringValue.new(String(node_key.digest)), completed
	)
	run.current_node_id = OptionalStringValue.new(String(node_key.digest))
	return run
