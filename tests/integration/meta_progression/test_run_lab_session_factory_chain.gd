extends GutTest

## S5 wave5 修正 A4（specs/meta-progression/design.md §4.4；requirements.md S5-AC-014）：
## 釘住「RunCommandFactory 的五個建構方法在 run 驅動鏈上真的被消費」。
##
## 修正前 RUN 狀態掛的是 S3 expedition_lab 純記憶體 demo，try_run_command_factory() 零呼叫端、
## commit_board_layout_command() 更沒有任何呼叫者——四命令＋board commit 全都是「建得出來但
## 沒人用」的死接線。本檔用真的 RunController 走一遍
## 生成地圖 → 進入節點 → 刷新商店 → 提交備戰 → 開戰 → 結算戰鬥，
## 每一步都經 RunLabSession（scripts/dev/run/run_lab_session.gd，即 RUN 灰盒的驅動端），
## 因此鏈上任何一個 factory 方法被拔掉、或命令被改成不經 factory 建構，本檔就紅。
##
## 已知邊界：灰盒 UI（run_screen.gd／run_scene.tscn）本身依既有慣例不做 UI 自動化測試
## （camp_screen／results_screen 同樣沒有），本檔測的是它按鈕背後的那條 domain 鏈。
##
## fixture 取用比照 tests/runners/expedition_runner.gd 的
## `_verify_production_node_entry_and_start`：SaveRootFixture 的合法 root ＋
## EconomyTestFixture 的 settlement/expedition 目錄，全部釘在同一個 manifest 世代。

const UNIT_INSTANCE_ID: String = "u_0000000000000001"
const UNIT_DEF_ID: StringName = &"unit.fixture"
const COMMANDER_POPULATION_BONUS: int = 2

var _repository: SaveRepository
var _controller: RunController
var _factory: RunCommandFactory
var _lab: RunLabSession
var _battle_catalog: BattleRuleCatalog


func before_each() -> void:
	var root := SaveRootFixture.create_valid_root()
	var manifest := root.run.content_snapshot.manifest_digest_value()
	var catalog := EconomyTestFixture.settlement_catalog(manifest)
	_battle_catalog = EconomyTestFixture.expedition_battle_catalog(manifest)
	var run := _fresh_map_phase_run(root.run, catalog)
	_repository = SaveRootFixture.create_repository(FakeSaveStorage.new())
	add_child_autofree(_repository)
	_controller = RunController.new(
		RunSession.new(root.profile, run, TestCatalogLease.new(manifest)),
		_repository,
		RunStateValidator.new(),
		RunSaveRootFactory.new("0.2.0", FixedRunCommitClock.new()),
		_battle_catalog
	)
	var empty_rules: Array[RunRelicRule] = []
	var empty_affixes: Array[StringName] = []
	_factory = RunCommandFactory.new(
		catalog, RunRelicTable.new(manifest, empty_rules), _battle_catalog,
		empty_affixes, run.commander_id, COMMANDER_POPULATION_BONUS
	)
	var empty_passives: Array[StringName] = []
	_lab = RunLabSession.new(_controller, _factory, catalog, _battle_catalog, empty_passives)


func test_run_driver_consumes_every_factory_construction_in_one_node_cycle() -> void:
	assert_true(_lab.is_concrete())

	# 1. GenerateExpeditionMapCommand
	assert_eq(_lab.generate_map(), &"", "map generation must commit through the factory command")
	assert_true(
		_lab.map().nodes.size() >= 21,
		"a committed expedition map carries all three acts"
	)

	# 2. EnterNodeEvent
	var reachable := _lab.reachable_node_ids()
	assert_false(reachable.is_empty(), "a fresh map always exposes the act 1 entry node")
	if reachable.is_empty():
		return
	assert_eq(_lab.enter_node(reachable[0]), &"")
	assert_eq(_lab.view().run_phase, RunState.RunPhase.PREPARE)
	var entered := _lab.current_node()
	assert_not_null(entered)
	assert_not_null(
		entered.encounter_preview,
		"entering a combat node must persist its compiled encounter preview"
	)

	# 3. RefreshShopCommand
	assert_eq(_lab.refresh_shop(), &"")
	assert_false(
		_lab.economy().shop_offers.is_empty(),
		"a refreshed shop must publish offers the run can buy from"
	)

	# 4. commit_board_layout_command()（含指揮官人口加成來源注入）
	assert_eq(_lab.commit_board(), &"")
	var committed := _controller.roster_snapshot()
	assert_eq(committed.board.placements.size(), 1, "the bench unit must be deployed")
	assert_eq(committed.board.placements[0].unit_instance_id, UNIT_INSTANCE_ID)
	assert_true(committed.bench_unit_instance_ids.is_empty())

	# 5. StartCombatEvent + BattleSimulation + RecordBattleResultCommand（S2 既有鏈）
	assert_eq(_lab.start_combat(), &"")
	assert_eq(_lab.view().run_phase, RunState.RunPhase.COMBAT)
	assert_eq(
		_lab.view().resolution_kind, ResolutionState.Kind.BATTLE_RESULT_PENDING,
		"a finished simulation must leave a committed battle result to settle"
	)

	# 6. SettleBattleResultCommand
	assert_eq(_lab.settle_battle(), &"")
	assert_ne(
		_lab.view().run_phase, RunState.RunPhase.COMBAT,
		"settling must move the run out of COMBAT (reward on a win, map/results on a loss)"
	)

	# 全鏈都落過存檔：最後一次提交讀得回來，且仍是同一局。
	var loaded := _repository.load()
	assert_true(loaded.ok)
	if loaded.ok:
		assert_eq(loaded.run.run_id, _lab.view().run_id)


func test_driver_rejects_out_of_phase_operations_by_name_without_committing() -> void:
	# MAP 階段沒有節點可刷新商店：命令必須被 domain 具名拒絕，而不是靜默成功。
	var before := _lab.view().publication_serial.to_hex()
	var error := _lab.refresh_shop()
	assert_false(error.is_empty(), "refreshing a shop outside PREPARE must be rejected")
	assert_true(
		String(error).contains("/"),
		"the rejection must carry the domain source_code, not just the generic apply code"
	)
	assert_eq(
		_lab.view().publication_serial.to_hex(), before,
		"a rejected command must not publish a new run state"
	)


func test_second_board_commit_reassigns_existing_board_and_new_bench_units_together() -> void:
	# W5 R2 #1：模擬「第一節點已上場，接著買到一隻新棋」的真實第二次備戰。
	# commit_board() 必須把既有 board placements 與新 bench 視為同一個 canonical
	# roster 聯集；若只讀 bench，舊棋會變成 UNIT_UNASSIGNED 而整筆交易被拒。
	assert_eq(_lab.generate_map(), &"")
	var reachable := _lab.reachable_node_ids()
	assert_false(reachable.is_empty())
	if reachable.is_empty():
		return
	assert_eq(_lab.enter_node(reachable[0]), &"")
	assert_eq(_lab.refresh_shop(), &"")
	assert_eq(_lab.commit_board(), &"", "first preparation commits the original unit")
	assert_eq(_controller.roster_snapshot().board.placements.size(), 1)

	assert_eq(_lab.buy_first_offer(), &"", "the second preparation has a newly benched unit")
	var before_second := _controller.roster_snapshot()
	assert_eq(before_second.unit_instances.size(), 2)
	assert_eq(before_second.board.placements.size(), 1)
	assert_eq(before_second.bench_unit_instance_ids.size(), 1)

	assert_eq(
		_lab.commit_board(), &"",
		"second commit must not reject the old board unit as UNIT_UNASSIGNED"
	)
	var committed := _controller.roster_snapshot()
	assert_eq(committed.unit_instances.size(), 2)
	assert_eq(committed.board.placements.size(), 2)
	assert_true(committed.bench_unit_instance_ids.is_empty())
	var assigned: Array[String] = []
	for placement: BoardPlacementState in committed.board.placements:
		assigned.append(placement.unit_instance_id)
	for unit: UnitInstance in committed.unit_instances:
		assert_true(
			assigned.has(unit.instance_id),
			"every roster unit must remain assigned after the second board commit"
		)


func test_start_combat_resumes_a_committed_combat_pending_setup_without_restarting_event() -> void:
	# W5 R2 #2：先只提交 StartCombatEvent，模擬 app 在 BattleSimulation 完成前中斷。
	# 再由灰盒 start_combat() 接手時必須直接 begin_or_resume；若重送事件，COMBAT
	# phase gate 會拒絕，這條測試就無法走到 BATTLE_RESULT_PENDING。
	assert_eq(_lab.generate_map(), &"")
	var reachable := _lab.reachable_node_ids()
	assert_false(reachable.is_empty())
	if reachable.is_empty():
		return
	assert_eq(_lab.enter_node(reachable[0]), &"")
	assert_eq(_lab.commit_board(), &"")
	var empty_passives: Array[StringName] = []
	var sources := BattleSetupSourceCompiler.new().compile(
		_controller.roster_snapshot(), _battle_catalog, empty_passives
	)
	var started := _controller.transition(
		StartCombatEvent.new(_battle_catalog, sources)
	)
	assert_true(started.ok, String(started.error.code) if not started.ok else "ok")
	if not started.ok:
		return
	assert_eq(_lab.view().run_phase, RunState.RunPhase.COMBAT)
	assert_eq(_lab.view().resolution_kind, ResolutionState.Kind.COMBAT_PENDING)

	assert_eq(
		_lab.start_combat(), &"",
		"a committed COMBAT_PENDING setup must resume instead of re-sending StartCombatEvent"
	)
	assert_eq(_lab.view().run_phase, RunState.RunPhase.COMBAT)
	assert_eq(_lab.view().resolution_kind, ResolutionState.Kind.BATTLE_RESULT_PENDING)


## MAP 階段、空地圖、板凳上一隻棋的起始 run（其餘沿用 SaveRootFixture 的合法 root）。
## 單位池的 held/remaining 與 roster 一致，才過得了 RunStateValidator 的守恆不變式。
func _fresh_map_phase_run(source: RunState, catalog: EconomyExpeditionCatalog) -> RunState:
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
		BoardState.new(empty_placements), bench, units, empty_items,
		empty_strings, empty_strings, relics
	)
	return run
