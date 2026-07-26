extends GutTest

## T11 (specs/meta-progression/design.md §4.4; tasks.md T11「已知前置缺口」第 1、2 點) —
## RunCompositionSupport 是本測試檔宣告的新型別，補上 design.md 未點名、但 T11 派工簡報
## 明確要求釘住的兩個composition-root wiring 缺口（皆屬「whoever constructs the command/
## catalog」的既有留白，見 commit_board_layout_command.gd:71-76 與
## battle_rule_catalog_builder.gd:407-413 的既有註解）：
##
## 缺口 1（軌 A 在正式流程不生效）：BattleRuleCatalogBuilder 已能正確解碼 unlock 類內容並
## 遞移 pin 其 battle_operations 非空的效果（battle_rule_catalog_builder.gd:414-441，
## _append_unlock_battle_effects），但沒有任何production 呼叫端把 challenge unlock 鏈
## （unlock.slice_challenge_1..N）納入餵給它的 required_ids——scripts/dev/build_lab/
## build_lab_content_bootstrap.gd:85-89（S4 既有、非本任務範圍）示範了這個缺口的具體樣子：
## battle_roots 只含 unit_ids/equipment_ids/battle_relic_ids，即使 _collect_ids() 已收集
## challenge_unlock_ids（build_lab_content_bootstrap.gd:164,193-196）也從未使用。T11 必須
## 在組裝 required_ids 時依 run 的 challenge_level 補上 unlock.slice_challenge_1..N。
##
## 缺口 2（指揮官 population source 未注入）：commit_board_layout_command.gd:71-76 的既有
## 註解明文「extra sources are INJECTED by whoever constructs the command...Default is
## empty」並指名 RunBootstrapService.try_commander_population_source(run.commander_id,
## bonus)（run_bootstrap_service.gd:228-239，已存在的靜態工具）為建構者應呼叫的來源。
##
## 假設聲明（design.md 未點名此型別，以下為 test-author 的binding decision）：
## 1. 新型別 RunCompositionSupport（RefCounted），路徑
##    domain/run/controller/run_composition_support.gd——與 RunCommandFactory
##    （domain/run/controller/run_command_factory.gd）同目錄，因為兩者都是「AppRoot 組裝
##    一個可玩 run 所需物件」的 composition-root 輔助方法，性質與 domain/run/controller/
##    現有的 RunSessionFactory／RunSaveRootFactory 一致（同目錄下的『production builder』）。
## 2. static func required_battle_ids(base_ids: Array[StringName], challenge_level: int)
##    -> Array[StringName]：回傳 base_ids 之後依序附加 "unlock.slice_challenge_%d"
##    （1..challenge_level，與 challenge_affix_resolver.gd:33／
##    run_modifier_table_builder.gd:90 完全相同的 unlock id 命名慣例），不修改/排序
##    base_ids 本身的相對順序、不去重 base_ids（呼叫端負責提供已去重的 base_ids）、
##    challenge_level<=0 時原樣回傳 base_ids 的淺層複本（不得回傳同一個 Array 物件，避免
##    呼叫端誤改動呼叫者資料）。
## 3. static func population_sources(commander_id: StringName, population_bonus: int)
##    -> Array[PopulationSourceSnapshot]：population_bonus<=0 時回傳空陣列；否則回傳恰含
##    一筆 RunBootstrapService.try_commander_population_source(commander_id,
##    population_bonus) 的陣列（本方法只是把既有靜態工具的「可能為 null」結果正規化成
##    CommitBoardLayoutCommand 建構子期待的 Array 形狀，不重新定義來源語意）。
##
## GUT 陷阱：RunCompositionSupport 目前不存在，直接以 class_name 頂層引用會讓整檔 parse
## error 被 GUT 靜默排除（不計入失敗數）。比照 tests/unit/meta_progression/
## test_collection_view_model.gd 的 load() 動態載入寫法。

const SCRIPT_PATH := "res://domain/run/controller/run_composition_support.gd"


func test_required_battle_ids_appends_challenge_chain_in_ascending_level_order() -> void:
	var script := _load_script()
	if script == null:
		return
	var base_ids: Array[StringName] = [&"unit.alpha", &"equipment.beta"]
	var result: Array[StringName] = script.call("required_battle_ids", base_ids, 3)
	assert_eq(result, [
		&"unit.alpha", &"equipment.beta",
		&"unlock.slice_challenge_1", &"unlock.slice_challenge_2", &"unlock.slice_challenge_3",
	])


func test_required_battle_ids_does_not_mutate_the_callers_base_array() -> void:
	var script := _load_script()
	if script == null:
		return
	var base_ids: Array[StringName] = [&"unit.alpha"]
	script.call("required_battle_ids", base_ids, 2)
	assert_eq(base_ids, [&"unit.alpha"], "the caller's base_ids array must not be appended to in place")


func test_required_battle_ids_at_challenge_zero_returns_base_ids_unchanged() -> void:
	var script := _load_script()
	if script == null:
		return
	var base_ids: Array[StringName] = [&"unit.alpha", &"unit.beta"]
	var result: Array[StringName] = script.call("required_battle_ids", base_ids, 0)
	assert_eq(result, base_ids)


func test_required_battle_ids_with_empty_base_and_challenge_one_yields_only_unlock_id() -> void:
	var script := _load_script()
	if script == null:
		return
	var empty: Array[StringName] = []
	var result: Array[StringName] = script.call("required_battle_ids", empty, 1)
	assert_eq(result, [&"unlock.slice_challenge_1"])


func test_population_sources_with_zero_bonus_is_empty() -> void:
	var script := _load_script()
	if script == null:
		return
	var result: Array[PopulationSourceSnapshot] = script.call(
		"population_sources", &"commander.alpha", 0
	)
	assert_eq(result.size(), 0)


func test_population_sources_with_negative_bonus_is_empty() -> void:
	var script := _load_script()
	if script == null:
		return
	var result: Array[PopulationSourceSnapshot] = script.call(
		"population_sources", &"commander.alpha", -1
	)
	assert_eq(result.size(), 0)


func test_population_sources_with_positive_bonus_yields_one_commander_source() -> void:
	var script := _load_script()
	if script == null:
		return
	var result: Array[PopulationSourceSnapshot] = script.call(
		"population_sources", &"commander.gamma", 2
	)
	assert_eq(result.size(), 1)
	if result.size() != 1:
		return
	var source: PopulationSourceSnapshot = result[0]
	assert_eq(source.source_kind, PopulationSourceSnapshot.SourceKind.COMMANDER)
	assert_eq(source.source_id, &"commander.gamma")
	assert_eq(source.amount, 2)


## design.md SS4.2／commit_board_layout_command.gd:71-76 的實際落地場景：一個
## population_bonus=2 的指揮官，若 CommitBoardLayoutCommand 未收到
## RunCompositionSupport.population_sources() 的產物（即沿用預設空陣列），board
## population cap 只有 base level；收到後 cap 應多 2。本測試直接證明「不注入 vs 注入」
## 這兩條路徑在既有 BoardPreparationValidator 之下確實產生不同結果，佐證缺口 2 是真實、
## 可觀察的行為差異，而非只是型別層面的 wiring。
func test_population_sources_output_actually_changes_board_capacity_via_commit_command() -> void:
	var script := _load_script()
	if script == null:
		return
	# Pinned to SaveRootFixture's own manifest digest (not EconomyTestFixture's default),
	# matching the digest carried by _prepare_draft_with_level()'s content_snapshot --
	# CommitBoardLayoutCommand rejects a catalog pinned to a different generation.
	var catalog := EconomyTestFixture.battle_catalog(SaveRootFixture.MANIFEST_DIGEST)
	# Three DISTINCT def_ids (not three copies of one def_id): UnitMergeService.merge_all()
	# (called inside CommitBoardLayoutCommand.apply_to(), before the population check runs)
	# merges 3+ same-def_id/same-star units into fewer higher-star ones, which would shrink
	# board.placements.size() out from under this test and make the "exceeds cap" scenario
	# never actually exercise the population check this test targets.
	var placements: Array[BoardPlacementState] = [
		BoardPlacementState.new(0, 0, "u_0000000000000000"),
		BoardPlacementState.new(0, 1, "u_0000000000000001"),
		BoardPlacementState.new(0, 2, "u_0000000000000002"),
	]
	var empty_bench: Array[String] = []
	var without_sources: Array[PopulationSourceSnapshot] = []
	var without_command := CommitBoardLayoutCommand.new(
		BoardState.new(placements), empty_bench, catalog, without_sources
	)
	var with_sources: Array[PopulationSourceSnapshot] = script.call(
		"population_sources", &"commander.gamma", 2
	)
	var with_command := CommitBoardLayoutCommand.new(
		BoardState.new(placements), empty_bench, catalog, with_sources
	)
	# base level 1 -> population cap 1 (PopulationCalculator.calculate(base_level, [])),
	# so placing 3 units exceeds cap unless the +2 commander source raises it to 3.
	var without_result := without_command.apply_to(_prepare_draft_with_level(1))
	var with_result := with_command.apply_to(_prepare_draft_with_level(1))
	assert_false(
		without_result.ok,
		"without an injected population source, 3 placements must exceed the level-1 base cap"
	)
	assert_true(
		with_result.ok,
		"with the +2 commander population source, 3 placements must fit the cap: %s" % (
			String(with_result.error.code) if not with_result.ok else "ok"
		)
	)


func _prepare_draft_with_level(level: int) -> RunState:
	var root := SaveRootFixture.create_valid_root()
	var run := root.run
	run.run_phase = RunState.RunPhase.PREPARE
	run.economy_state.level = level
	var units: Array[UnitInstance] = [
		UnitInstance.new("u_0000000000000000", &"unit.a", 1, [], U64Bits.zero()),
		UnitInstance.new("u_0000000000000001", &"unit.b", 1, [], U64Bits.zero()),
		UnitInstance.new("u_0000000000000002", &"unit.c", 1, [], U64Bits.zero()),
	]
	var bench: Array[String] = [
		"u_0000000000000000", "u_0000000000000001", "u_0000000000000002",
	]
	run.roster_state = RosterState.new(
		BoardState.new([]), bench, units, [], [], [], run.roster_state.active_relic_slots
	)
	# w5 仲裁（2026-07-25）：SaveRootFixture 的 unit_pool 是空的，而 CommitBoardLayoutCommand
	# 在人口檢查之前先跑 copy-ledger↔pool 守恆檢查——pool 缺這三個 def 會讓 with/without 兩路
	# 都在 UNIT_POOL_HELD_COPY_MISMATCH 同點被拒，人口斷言變成空頭。補上 held=1 的對應 entry
	# （total=held、remaining=0，依 def_id 升序），讓測試真正走到人口檢查。
	run.unit_pool_state = UnitPoolState.new([
		UnitPoolEntryState.new(&"unit.a", 1, 0, 0, 1),
		UnitPoolEntryState.new(&"unit.b", 1, 0, 0, 1),
		UnitPoolEntryState.new(&"unit.c", 1, 0, 0, 1),
	])
	return run


func _load_script() -> GDScript:
	var script := load(SCRIPT_PATH) as GDScript
	assert_not_null(
		script,
		"RunCompositionSupport (%s) must exist with static required_battle_ids()/population_sources()" % SCRIPT_PATH
	)
	return script
