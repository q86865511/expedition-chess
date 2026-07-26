extends GutTest

## S5 wave5 修正 #8（sonnet 審查 #1）：RunCommandFactory 的**第五個**建構方法
## `commit_board_layout_command()` 與兩個尾參（commander_id／commander_population_bonus）的
## 契約測試。tests/unit/meta_progression/test_run_command_factory.gd（w5-T11 鎖定測試，
## 檔案雜湊記在 .pipeline/tdd/w5-T11-tests.manifest，本波不得修改）只鎖了四個命令的
## relic_table 注入；本檔補上第五個方法，並釘住它存在的理由：
##
##   PREPARE 期的 board population cap ＝ economy level ＋ 額外來源（population_calculator.gd:31-49），
##   而 RunState 不持久化 population source 台帳（commit_board_layout_command.gd:71-76）。
##   來源因此必須由「建構命令的人」依 (run.commander_id, pinned CommanderDef.population_bonus)
##   決定性重建——這正是 factory 這兩個尾參的用途（design.md §4.2、缺口 2）。
##   忘了注入不會報錯，只會讓玩家少一格人口上限、且無聲。
##
## 消費端證據（factory 的五個建構方法都在真的 run 驅動鏈上被呼叫）見
## tests/integration/meta_progression/test_run_lab_session_factory_chain.gd。

const UNIT_A_ID: String = "u_0000000000000001"
const UNIT_B_ID: String = "u_0000000000000002"
const UNIT_DEF_ID: StringName = &"unit.fixture"
const BASE_LEVEL: int = 1


func test_commit_board_command_injects_the_commander_population_source() -> void:
	var draft := _prepare_phase_run()
	var manifest := draft.content_snapshot.manifest_digest_value()
	# 人口加成 1：capacity == level(1) + 1 == 2，剛好放得下兩隻棋。
	var command := _factory(manifest, 1).commit_board_layout_command(_board(), _no_bench())
	assert_true(command.is_concrete())
	var applied := command.apply_to(draft)
	assert_true(
		applied.ok,
		"the commander population source must lift the cap above the base economy level"
	)
	if not applied.ok:
		return
	assert_eq(applied.draft.roster_state.board.placements.size(), 2)


func test_commit_board_command_without_a_commander_bonus_keeps_the_base_cap() -> void:
	var draft := _prepare_phase_run()
	var manifest := draft.content_snapshot.manifest_digest_value()
	# 無加成（S2~S4 的「只看 level」行為）：capacity == 1，第二隻棋超額，必須具名拒絕。
	var command := _factory(manifest, 0).commit_board_layout_command(_board(), _no_bench())
	var applied := command.apply_to(draft)
	assert_false(applied.ok, "two units must not fit a level-1 board without extra sources")
	if applied.ok:
		return
	assert_eq(applied.error.field_path, &"run.roster_state.board")
	assert_eq(
		_source_code(applied.error), String(BoardValidationIssue.OVER_CAPACITY),
		"the rejection must name the capacity rule, not a generic apply failure"
	)


func test_commit_board_command_is_not_concrete_without_a_battle_catalog() -> void:
	var draft := _prepare_phase_run()
	var manifest := draft.content_snapshot.manifest_digest_value()
	var empty_affixes: Array[StringName] = []
	var empty_rules: Array[RunRelicRule] = []
	# battle_catalog 是 commit_board_layout_command()／enter_node_event() 專屬的可選參數
	# （run_command_factory.gd:14-15）；沒帶時建出來的命令必須自陳不完整，而不是半殘可用。
	var factory := RunCommandFactory.new(
		EconomyTestFixture.settlement_catalog(manifest),
		RunRelicTable.new(manifest, empty_rules),
		null, empty_affixes, &"commander.fixture", 1
	)
	assert_false(factory.commit_board_layout_command(_board(), _no_bench()).is_concrete())


func test_commit_board_command_does_not_alias_the_caller_board() -> void:
	var draft := _prepare_phase_run()
	var manifest := draft.content_snapshot.manifest_digest_value()
	var board := _board()
	var command := _factory(manifest, 1).commit_board_layout_command(board, _no_bench())
	# 呼叫端事後改自己那份 BoardState，不得影響已建構的命令（factory／命令都 clone-in）。
	board.placements.clear()
	var applied := command.apply_to(draft)
	assert_true(applied.ok)
	if applied.ok:
		assert_eq(applied.draft.roster_state.board.placements.size(), 2)


func _factory(manifest: String, population_bonus: int) -> RunCommandFactory:
	var empty_affixes: Array[StringName] = []
	var empty_rules: Array[RunRelicRule] = []
	return RunCommandFactory.new(
		EconomyTestFixture.settlement_catalog(manifest),
		RunRelicTable.new(manifest, empty_rules),
		EconomyTestFixture.expedition_battle_catalog(manifest),
		empty_affixes,
		&"commander.fixture",
		population_bonus
	)


func _board() -> BoardState:
	var placements: Array[BoardPlacementState] = [
		BoardPlacementState.new(0, 0, UNIT_A_ID),
		BoardPlacementState.new(0, 1, UNIT_B_ID),
	]
	return BoardState.new(placements)


func _no_bench() -> Array[String]:
	var bench: Array[String] = []
	return bench


## PREPARE 階段、兩隻同型一星棋在板凳上的 run（兩隻不足三隻，不會觸發合成）。
func _prepare_phase_run() -> RunState:
	var run := SaveRootFixture.create_valid_root().run.deep_clone()
	run.run_phase = RunState.RunPhase.PREPARE
	run.resolution_state = IdleResolutionState.new()
	var empty_offers: Array[ShopOffer] = []
	run.economy_state = EconomyState.new(0, BASE_LEVEL, 0, 0, 0, 0, empty_offers)
	var pool_entries: Array[UnitPoolEntryState] = [
		UnitPoolEntryState.new(UNIT_DEF_ID, 9, 7, 0, 2),
	]
	run.unit_pool_state = UnitPoolState.new(pool_entries)
	var no_equipment: Array[String] = []
	var units: Array[UnitInstance] = [
		UnitInstance.new(UNIT_A_ID, UNIT_DEF_ID, 1, no_equipment, U64Bits.one()),
		UnitInstance.new(UNIT_B_ID, UNIT_DEF_ID, 1, no_equipment, U64Bits.one()),
	]
	var bench: Array[String] = [UNIT_A_ID, UNIT_B_ID]
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


func _source_code(error: CommandApplyError) -> String:
	for diagnostic: DiagnosticValue in error.diagnostic_values:
		if diagnostic.key == &"source_code" and diagnostic.string_value != null:
			return diagnostic.string_value.value
	return ""
