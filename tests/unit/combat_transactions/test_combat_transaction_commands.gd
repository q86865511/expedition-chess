extends GutTest

func test_start_combat_builds_committed_v2_setup_from_preview_and_roster() -> void:
	var fixture := _prepare_fixture()
	var event := StartCombatEvent.new(fixture["catalog"], fixture["sources"])
	var applied := event.apply_to(fixture["run"])
	assert_true(applied.ok, _apply_error(applied))
	if not applied.ok:
		return
	assert_true(applied.draft.resolution_state is CombatPendingResolutionState)
	var pending := applied.draft.resolution_state as CombatPendingResolutionState
	assert_not_null(pending.battle_setup)
	assert_eq(pending.battle_setup.inputs.setup_schema_version, 2)
	assert_eq(
		pending.battle_setup.inputs.encounter_snapshot.enemy_units[0].instance_id,
		&"e_0000000000000001"
	)
	assert_true(
		BattleSetupEnvelopeVerifier.new().verify(
			pending.battle_setup, applied.draft.run_seed
		).ok
	)

func test_start_combat_rejects_unresolved_or_null_sources_without_mutation() -> void:
	var fixture := _prepare_fixture()
	var run := fixture["run"] as RunState
	var sources := fixture["sources"] as BattleSetupSourceBundle
	var before: RunState = run.deep_clone()
	var unresolved: BattleSetupSourceBundle = sources.deep_clone()
	unresolved.equipment_sources_resolved = false
	var rejected := StartCombatEvent.new(
		fixture["catalog"], unresolved
	).apply_to(run)
	assert_false(rejected.ok)
	assert_true(run.resolution_state is IdleResolutionState)
	assert_eq(run.run_phase, before.run_phase)
	var malformed: BattleSetupSourceBundle = sources.deep_clone()
	malformed.player_units[0] = null
	var malformed_result := StartCombatEvent.new(
		fixture["catalog"], malformed
	).apply_to(run)
	assert_false(malformed_result.ok)
	assert_true(run.resolution_state is IdleResolutionState)

func test_record_result_requires_exact_setup_result_and_receipt_hashes() -> void:
	var fixture := _prepare_fixture()
	var started := StartCombatEvent.new(
		fixture["catalog"], fixture["sources"]
	).apply_to(fixture["run"])
	assert_true(started.ok)
	if not started.ok:
		return
	started.draft.run_phase = RunState.RunPhase.COMBAT
	var setup := (started.draft.resolution_state as CombatPendingResolutionState).battle_setup
	var simulation := BattleSimulation.new()
	assert_true(simulation.initialize(setup).ok)
	for _index: int in range(1801):
		var step := simulation.step()
		assert_true(step.ok)
		if step.finished:
			break
	var queried := simulation.result()
	assert_true(queried.ok)
	var command := RecordBattleResultCommand.new(
		setup.battle_setup_hash,
		queried.result.result_hash,
		queried.result,
		simulation.validation_receipt()
	)
	var recorded := command.apply_to(started.draft.deep_clone())
	assert_true(recorded.ok, _apply_error(recorded))
	assert_true(recorded.draft.resolution_state is BattleResultPendingResolutionState)
	var wrong := RecordBattleResultCommand.new(
		&"0000000000000000000000000000000000000000000000000000000000000000",
		queried.result.result_hash,
		queried.result,
		simulation.validation_receipt()
	).apply_to(started.draft)
	assert_false(wrong.ok)
	assert_true(started.draft.resolution_state is CombatPendingResolutionState)

func _prepare_fixture() -> Dictionary:
	var root := SaveRootFixture.create_valid_root()
	var run := root.run
	run.run_phase = RunState.RunPhase.PREPARE
	run.act_index = 1
	run.resolution_state = IdleResolutionState.new()
	var player := _unit_snapshot(
		&"u_0000000000000001", &"unit.hero", &"player", 3, 3, 120, 20
	)
	var enemy := _unit_snapshot(
		&"e_0000000000000001", &"unit.foe", &"enemy", 4, 3, 30, 10
	)
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
	var configs: Array[BattleCombatConfigRule] = [_combat_config()]
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

func _unit_snapshot(
	instance_id: StringName,
	unit_id: StringName,
	side: StringName,
	y: int,
	x: int,
	health: int,
	attack: int
) -> UnitBattleSnapshot:
	var unit := UnitBattleSnapshot.new()
	unit.instance_id = instance_id
	unit.unit_id = unit_id
	unit.side = side
	unit.logical_y = y
	unit.logical_x = x
	unit.health = health
	unit.attack = attack
	unit.attack_speed_milli = 1000
	unit.attack_range_cells = 1
	unit.max_mana = 0
	unit.move_speed_milli = 1000
	return unit

func _combat_config() -> BattleCombatConfigRule:
	var config := BattleCombatConfigRule.new()
	config.config_id = &"config.combat_default"
	var defaults := BattleRulesSnapshot.new()
	for property: StringName in BattleCombatConfigRule._integer_properties():
		config.set(property, defaults.get(property))
	return config

func _apply_error(result: CommandApplyResult) -> String:
	if result == null or result.error == null:
		return "unknown apply failure"
	return "%s at %s" % [String(result.error.code), String(result.error.field_path)]
