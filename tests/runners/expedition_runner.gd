extends SceneTree

const Support = preload("res://tests/runners/runner_support.gd")
const ARTIFACT_PATH := "res://artifacts/test/expedition-runner.json"

var _started_at_utc := ""

func _init() -> void:
	_started_at_utc = Support.utc_now()
	call_deferred("_run")

func _run() -> void:
	var failures: Array[String] = []
	var assertions := 0
	var root := ResolutionFixtureFactory.create_root(
		ResolutionState.Kind.BATTLE_RESULT_PENDING
	)
	var manifest := root.run.content_snapshot.manifest_digest_value()
	var catalog := EconomyTestFixture.settlement_catalog(manifest)
	var map_first := MapService.new().generate_map(MapGenerationRequest.new(
		StringName(root.run.run_id), root.run.run_seed, catalog
	))
	var map_second := MapService.new().generate_map(MapGenerationRequest.new(
		StringName(root.run.run_id), root.run.run_seed, catalog
	))
	assertions += 3
	var map_ok := false
	if not map_first.ok or not map_second.ok:
		failures.append("deterministic expedition map generation failed")
	elif _map_digest(map_first.map_state) != _map_digest(map_second.map_state):
		failures.append("same expedition seed produced different maps")
	elif map_first.map_state.nodes.size() < 21:
		failures.append("expedition map omitted required acts/layers")
	else:
		map_ok = true
	var production_ok := _verify_production_node_entry_and_start(
		root, map_first.map_state if map_first.ok else null, catalog, failures
	)
	assertions += 4
	root.run.run_phase = RunState.RunPhase.COMBAT
	var node_id := root.run.map_state.nodes[0].node_id
	root.run.current_node_id = OptionalStringValue.new(node_id)
	root.run.map_state.current_node_id = OptionalStringValue.new(node_id)
	root.run.income_claimed_node_ids = [node_id]
	root.run.economy_state.level = 3
	var settled := BattleSettlementService.new().settle(root.run, catalog)
	assertions += 2
	var settlement_ok := false
	var reward_ok := false
	if not settled.ok or settled.run_state.run_phase != RunState.RunPhase.REWARD:
		failures.append("battle result did not commit reward_pending")
	else:
		settlement_ok = true
		var pending := (settled.run_state.resolution_state as RewardPendingResolutionState).pending_reward
		var chosen := RewardService.new().choose(
			settled.run_state, pending.offers[0].choice_id, catalog
		)
		if not chosen.ok:
			failures.append("persisted reward choice could not be committed")
		else:
			var advanced := RewardService.new().advance(chosen.run_state, catalog)
			if not advanced.ok or advanced.run_state.run_phase != RunState.RunPhase.MAP:
				failures.append("reward final exit did not return to map")
			else:
				reward_ok = true
	var completed: Array[String] = []
	if map_ok:
		completed.append("three_act_map_generation")
	if production_ok:
		completed.append("production_node_entry_preview_and_combat_start")
	if settlement_ok:
		completed.append("battle_settlement_and_claims")
	if reward_ok:
		completed.append("reward_persistence_and_final_exit")
	var deferred: Array[String] = []
	var report := Support.base_report(
		"economy-expedition", _started_at_utc, completed, deferred
	)
	report["case_count"] = 3
	report["assertion_count"] = assertions
	report["failures"] = failures
	report["passed"] = failures.is_empty()
	var written := Support.write_json_artifact(ARTIFACT_PATH, report)
	quit(3 if written != OK else (0 if failures.is_empty() else 2))

func _verify_production_node_entry_and_start(
	fixture_root: SaveRoot,
	map: MapState,
	catalog: EconomyExpeditionCatalog,
	failures: Array[String]
) -> bool:
	if map == null:
		return false
	var run := fixture_root.run.deep_clone()
	run.run_phase = RunState.RunPhase.MAP
	run.resolution_state = IdleResolutionState.new()
	run.map_state = map.deep_clone()
	run.current_node_id = null
	run.map_state.current_node_id = null
	run.economy_state = EconomyState.new(20, 3, 0, 0, 0, 0, [])
	run.unit_pool_state = catalog.create_initial_pool()
	run.reservation_owners.clear()
	run.transaction_receipts.clear()
	run.income_claimed_node_ids.clear()
	run.next_transaction_serial = U64Bits.zero()
	run.next_unit_serial = U64Bits.from_u32(0, 2).value
	run.unit_pool_state.entries[0].remaining_copies -= 1
	run.unit_pool_state.entries[0].held_copies = 1
	var no_equipment: Array[String] = []
	var unit := UnitInstance.new(
		"u_0000000000000001", &"unit.fixture", 1,
		no_equipment, U64Bits.one()
	)
	var placements: Array[BoardPlacementState] = [
		BoardPlacementState.new(3, 3, unit.instance_id),
	]
	var bench: Array[String] = []
	var units: Array[UnitInstance] = [unit]
	var items: Array[ItemInstanceState] = []
	var inventory: Array[String] = []
	var relics: Array[RelicSlotState] = []
	for index: int in range(5):
		relics.append(RelicSlotState.new(index, null))
	run.roster_state = RosterState.new(
		BoardState.new(placements), bench, units, items,
		inventory, inventory, relics
	)
	var battle_catalog := EconomyTestFixture.expedition_battle_catalog(
		run.content_snapshot.manifest_digest_value()
	)
	var storage := FakeSaveStorage.new()
	var repository := SaveRootFixture.create_repository(storage)
	get_root().add_child(repository)
	var session := RunSession.new(
		fixture_root.profile, run,
		TestCatalogLease.new(run.content_snapshot.manifest_digest_value())
	)
	var controller := RunController.new(
		session, repository, RunStateValidator.new(),
		RunSaveRootFactory.new("0.2.0", FixedRunCommitClock.new())
	)
	var entered := controller.transition(EnterNodeEvent.new(
		map.nodes[0].node_id, catalog, battle_catalog
	))
	if not entered.ok:
		failures.append("production node entry transition failed")
		repository.queue_free()
		return false
	var after_enter := repository.load()
	if not after_enter.ok or after_enter.run.run_phase != RunState.RunPhase.PREPARE \
		or after_enter.run.map_state.nodes[0].encounter_preview == null:
		failures.append("production node entry did not persist encounter preview")
		repository.queue_free()
		return false
	var started := controller.transition(StartCombatEvent.new(
		battle_catalog,
		_player_sources(run.content_snapshot.manifest_digest_value())
	))
	if not started.ok:
		failures.append("production node entry could not start committed combat")
		repository.queue_free()
		return false
	var after_start := repository.load()
	if not after_start.ok or after_start.run.run_phase != RunState.RunPhase.COMBAT \
		or not after_start.run.resolution_state is CombatPendingResolutionState:
		failures.append("production combat state was not persisted")
		repository.queue_free()
		return false
	repository.queue_free()
	return true

func _player_sources(manifest: String) -> BattleSetupSourceBundle:
	var player := UnitBattleSnapshot.new()
	player.instance_id = &"u_0000000000000001"
	player.unit_id = &"unit.fixture"
	player.side = &"player"
	player.logical_y = 3
	player.logical_x = 3
	player.health = 100
	player.attack = 10
	player.armor = 5
	player.magic_resist = 5
	player.attack_speed_milli = 1000
	player.attack_range_cells = 1
	player.max_mana = 100
	player.move_speed_milli = 1000
	var players: Array[UnitBattleSnapshot] = [player]
	var traits: Array[TraitBattleSnapshot] = []
	var effects: Array[BattleEffectSnapshot] = []
	return BattleSetupSourceBundle.new(
		manifest, players, traits, effects, effects, effects, effects,
		true, true, true, true, true, true
	)

func _map_digest(map: MapState) -> String:
	var parts: Array[String] = ["MAP-LAB-1"]
	for node: MapNodeState in map.nodes:
		parts.append("%s:%d:%d:%d" % [
			node.node_id, node.act_index, node.layer_index, node.node_kind
		])
	for edge: MapEdgeState in map.edges:
		parts.append(edge.from_node_id + ">" + edge.to_node_id)
	return EconomyPayloadDigest.sha256(parts)
