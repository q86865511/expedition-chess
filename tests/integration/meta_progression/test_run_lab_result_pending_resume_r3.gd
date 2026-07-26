extends GutTest

## W5 R3 S5-AC-014 regression: a reloaded COMBAT state may already contain the
## committed BattleResult.  RunLabSession must pass that state to
## CombatCoordinator.begin_or_resume(), observe resumed_committed_result, and
## return success without re-sending StartCombatEvent or advancing simulation.

const UNIT_INSTANCE_ID: String = "u_0000000000000001"
const UNIT_DEF_ID: StringName = &"unit.fixture"
const COMMANDER_POPULATION_BONUS: int = 2

var _storage: FakeSaveStorage
var _repository: SaveRepository
var _controller: RunController
var _lab: RunLabSession


func before_each() -> void:
	var root := SaveRootFixture.create_valid_root()
	var manifest := root.run.content_snapshot.manifest_digest_value()
	var economy_catalog := EconomyTestFixture.settlement_catalog(manifest)
	var battle_catalog := EconomyTestFixture.expedition_battle_catalog(manifest)
	var run := _fresh_map_phase_run(root.run, economy_catalog)
	_storage = FakeSaveStorage.new()
	_repository = SaveRootFixture.create_repository(_storage)
	add_child_autofree(_repository)
	_controller = RunController.new(
		RunSession.new(root.profile, run, TestCatalogLease.new(manifest)),
		_repository,
		RunStateValidator.new(),
		RunSaveRootFactory.new("0.2.0", FixedRunCommitClock.new()),
		battle_catalog
	)
	var empty_rules: Array[RunRelicRule] = []
	var empty_affixes: Array[StringName] = []
	var factory := RunCommandFactory.new(
		economy_catalog,
		RunRelicTable.new(manifest, empty_rules),
		battle_catalog,
		empty_affixes,
		run.commander_id,
		COMMANDER_POPULATION_BONUS
	)
	var empty_passives: Array[StringName] = []
	_lab = RunLabSession.new(
		_controller, factory, economy_catalog, battle_catalog, empty_passives
	)


func test_start_combat_accepts_committed_result_without_restarting_or_recommitting() -> void:
	assert_eq(_lab.generate_map(), &"")
	var reachable := _lab.reachable_node_ids()
	assert_false(reachable.is_empty())
	if reachable.is_empty():
		return
	assert_eq(_lab.enter_node(reachable[0]), &"")
	assert_eq(_lab.commit_board(), &"")
	assert_eq(_lab.start_combat(), &"", "first call must simulate and commit the result")
	assert_eq(_lab.view().run_phase, RunState.RunPhase.COMBAT)
	assert_eq(_lab.view().resolution_kind, ResolutionState.Kind.BATTLE_RESULT_PENDING)
	var serial_before := _lab.view().publication_serial.to_hex()
	var bytes_before := _storage.file_bytes(StorageFaultKey.MAIN)
	assert_not_null(bytes_before)

	var resumed := _lab.start_combat()

	assert_eq(
		resumed, &"",
		"BATTLE_RESULT_PENDING is a successful coordinator resume, not a new start event"
	)
	assert_eq(_lab.view().run_phase, RunState.RunPhase.COMBAT)
	assert_eq(_lab.view().resolution_kind, ResolutionState.Kind.BATTLE_RESULT_PENDING)
	assert_eq(
		_lab.view().publication_serial.to_hex(), serial_before,
		"resuming a committed result must not publish or commit another run revision"
	)
	assert_eq(
		_storage.file_bytes(StorageFaultKey.MAIN).value, bytes_before.value,
		"resuming a committed result must be byte-for-byte persistence neutral"
	)


func _fresh_map_phase_run(
	source: RunState,
	catalog: EconomyExpeditionCatalog
) -> RunState:
	var run := source.deep_clone()
	run.run_phase = RunState.RunPhase.MAP
	run.resolution_state = IdleResolutionState.new()
	var empty_nodes: Array[MapNodeState] = []
	var empty_edges: Array[MapEdgeState] = []
	var empty_completed: Array[String] = []
	run.map_state = MapState.new(empty_nodes, empty_edges, null, empty_completed)
	run.current_node_id = null
	var empty_offers: Array[ShopOffer] = []
	run.economy_state = EconomyState.new(20, 3, 0, 0, 0, 0, empty_offers)
	run.unit_pool_state = catalog.create_initial_pool()
	run.unit_pool_state.entries[0].remaining_copies -= 1
	run.unit_pool_state.entries[0].held_copies = 1
	run.reservation_owners.clear()
	run.transaction_receipts.clear()
	run.income_claimed_node_ids.clear()
	run.next_transaction_serial = U64Bits.zero()
	run.next_unit_serial = U64Bits.from_u32(0, 2).value
	var no_equipment: Array[String] = []
	var units: Array[UnitInstance] = [UnitInstance.new(
		UNIT_INSTANCE_ID, UNIT_DEF_ID, 1, no_equipment, U64Bits.one()
	)]
	var bench: Array[String] = [UNIT_INSTANCE_ID]
	var empty_placements: Array[BoardPlacementState] = []
	var empty_items: Array[ItemInstanceState] = []
	var empty_strings: Array[String] = []
	var relics: Array[RelicSlotState] = []
	for index: int in range(5):
		relics.append(RelicSlotState.new(index, null))
	run.roster_state = RosterState.new(
		BoardState.new(empty_placements),
		bench,
		units,
		empty_items,
		empty_strings,
		empty_strings,
		relics
	)
	return run
