extends GutTest

## T02 (specs/meta-progression) — MetaSettlementCommand 驗收（wave2 TDD 紅燈）。
## Covers：REQ-META-004、REQ-DATA-007、REQ-TECH-004、S5-AC-007。對應
## design.md §5.1 point5（SaveRoot(profile', run=null)→save→
## transition_after_save(FINISH_RUN)——本檔只驗證到 save 這一步的原子性/
## exactly-once，AppStateMachine 轉場與 CAMP 灰盒回歸屬 T11／S5-AC-008，不在
## 本任務範圍）與 §5.2（三故障點×3 重載一致性）、§12 測試案例 007。
##
## 假設聲明（design.md 明示「本任務把 command 做成自包含交易單元（直接經
## SaveRepository.save）」，未給精確簽名，依既有慣例＋design.md 逐字引用釘定，
## 比照 tests/integration/build_items/test_sell_equipped_unit_crash_load.gd／
## tests/integration/run_controller/test_battle_settlement_commands.gd 的既有
## fault-injection 測試風格）：
## 1. `MetaSettlementCommand.new(repository: SaveRepository, meta_reward_table:
##    MetaRewardTableDef, app_version: String = "0.2.0", clock: RunCommitClock =
##    null)` — 自包含：不經 CampController／RunController（兩者分屬 T04／既有，
##    T02 明確不得依賴同波平行任務 T04 的產物）。app_version/clock 參數比照既有
##    `RunSaveRootFactory.new(app_version, clock)`（domain/run/controller/
##    run_save_root_factory.gd）同款簽名——因為 repository.load() 回傳的
##    LoadResult 不攜帶原始 SaveRoot 的 schema_version/content_version/
##    app_version/saved_at_utc（只回 profile/run 兩個已解碼的 domain 物件，見
##    services/save/load_result.gd），Command 必須自行決定這些欄位，而非試圖
##    保留前一次存檔的值——這正是 RunSaveRootFactory 本身的既有做法。
##    content_version 由 Command 內部取自 load() 到的 run.content_snapshot（清空
##    run 前），不需要 design.md §4.1 提到的 CampSaveRootFactory（那是 T04 為
##    "build 時 run 尚未存在" 的情境設計；本 Command 呼叫時 run 仍在，取得到）。
## 2. `.dispatch() -> MetaSettlementCommandResult`：自行呼叫 repository.load()
##    取得目前 profile/run；run==null 時回具名錯誤（無 run 可結算）；否則呼叫
##    MetaSettlementService.settle(...)，組 SaveRoot(profile', null) 呼叫
##    repository.save(...)；save 失敗回具名錯誤。
## 3. `MetaSettlementCommandResult{ok, error}`／`MetaSettlementCommandError
##    {code, field_path}`，比照 domain/run/economy/expedition_action_result.gd
##    ＋expedition_action_error.gd 這對既有 Result/Error 的最小殼寫法（成功案例
##    透過 repository.load() 讀回驗證，不在 Result 本身攜帶 profile——比照
##    tests/integration/run_controller/test_battle_settlement_commands.gd 一貫
##    「dispatch 後用 repository.load() 驗證」的既定測試風格，不對 Result 的
##    payload 形狀做多餘假設）。錯誤代碼比照 design.md §13「META_SETTLEMENT_*」
##    命名：`NO_ACTIVE_RUN = &"META_SETTLEMENT_NO_ACTIVE_RUN"`、
##    `SAVE_FAILED = &"META_SETTLEMENT_SAVE_FAILED"`。
##
## 故障點選擇（§5.2／S5-AC-007「存檔各故障點終止×3 重載恰加值一次」的翻譯）：
## 3 個彼此獨立、涵蓋不同 pipeline 階段、且在單一故障下保證「尚未有任何實際
## 檔案系統變動」的故障點（DIRECTORY 為最早前置檢查；OPEN_WRITE/TMP 為首次落
## 筆寫入；READ/MAIN 為既有 main 的存在性重讀，三者皆發生在 rename 系列的
## rotation/promote 之前）——比照 test_run_controller_transactions.gd 的
## `test_storage_and_final_readback_failures_never_publish_draft` 與
## test_sell_equipped_unit_crash_load.gd 的既定 for-fault-in-faults 迴圈寫法。
##
## w2 雙審後追加 2 個故障點（涵蓋 rotation/promote 之後的子步驟，原 3 點全落在
## promote 之前，這段先前未覆蓋）：RENAME/TMP 為 promote 本身
## （tmp→main）；READ/MAIN occurrence 2 為 promote 後的 final-readback
## 重讀（occurrence 0/1 分別是 load() 的既存 main 重讀／save() rotation 前的
## main 重讀）。兩點的 occurrence 皆以 FakeSaveStorage.journal_snapshot() 實測
## 確認，而非手推。

func test_dispatch_commits_currency_receipt_records_and_clears_run_in_one_atomic_save() -> void:
	var table := _reward_table()
	var run := _terminal_run(&"commander.fixture", 2, 3, 4, 2, 60)
	var storage := FakeSaveStorage.new()
	var repository := SaveRootFixture.create_repository(storage)
	add_child_autofree(repository)
	var seed_result := repository.save(_seed_root(run, 0, 0, []))
	assert_true(seed_result.ok, "fixture seed save must succeed")

	var command := MetaSettlementCommand.new(repository, table, "0.1.0", FixedRunCommitClock.new())
	var result := command.dispatch()
	assert_true(result.ok, String(result.error.code) if not result.ok else "ok")
	if not result.ok:
		return

	var loaded := repository.load()
	assert_true(loaded.ok)
	if not loaded.ok:
		return
	assert_eq(loaded.run_status, LoadResult.RunStatus.NONE, "active run must be cleared")
	assert_null(loaded.run)
	var expected_delta: int = MetaRewardComputeService.compute(
		4, 2, 3, 2, SettlementReceiptState.Outcome.COMPLETED, table
	)
	assert_eq(loaded.profile.meta_currency, expected_delta)
	assert_eq(loaded.profile.settlement_receipts.size(), 1)
	assert_eq(loaded.profile.settlement_receipts[0].outcome, SettlementReceiptState.Outcome.COMPLETED)
	assert_eq(loaded.profile.settlement_receipts[0].currency_delta, expected_delta)
	assert_eq(loaded.profile.highest_challenge_level, 2)
	assert_eq(loaded.profile.commander_challenge_records.size(), 1)
	assert_eq(loaded.profile.commander_challenge_records[0].commander_id, &"commander.fixture")
	assert_eq(loaded.profile.commander_challenge_records[0].highest_cleared_level, 2)


func test_dispatch_failed_outcome_still_commits_currency_and_clears_run() -> void:
	var table := _reward_table()
	var run := _terminal_run(&"commander.fixture", 1, 1, 2, 1, 0)
	var storage := FakeSaveStorage.new()
	var repository := SaveRootFixture.create_repository(storage)
	add_child_autofree(repository)
	assert_true(repository.save(_seed_root(run, 5, 0, [])).ok)

	var command := MetaSettlementCommand.new(repository, table, "0.1.0", FixedRunCommitClock.new())
	var result := command.dispatch()
	assert_true(result.ok, String(result.error.code) if not result.ok else "ok")
	if not result.ok:
		return

	var loaded := repository.load()
	assert_true(loaded.ok)
	if not loaded.ok:
		return
	assert_null(loaded.run)
	var expected_delta: int = MetaRewardComputeService.compute(
		2, 1, 1, 1, SettlementReceiptState.Outcome.FAILED, table
	)
	assert_eq(loaded.profile.meta_currency, 5 + expected_delta)
	assert_eq(loaded.profile.settlement_receipts[0].outcome, SettlementReceiptState.Outcome.FAILED)
	assert_eq(loaded.profile.highest_challenge_level, 0, "FAILED must never advance highest_challenge_level")
	assert_eq(loaded.profile.commander_challenge_records.size(), 0)


func test_dispatch_fails_named_error_when_no_active_run_to_settle() -> void:
	var table := _reward_table()
	var storage := FakeSaveStorage.new()
	var repository := SaveRootFixture.create_repository(storage)
	add_child_autofree(repository)
	assert_true(repository.save(_profile_only_root(5)).ok)

	var command := MetaSettlementCommand.new(repository, table, "0.1.0", FixedRunCommitClock.new())
	var result := command.dispatch()

	assert_false(result.ok)
	assert_eq(result.error.code, MetaSettlementCommandError.NO_ACTIVE_RUN)
	var loaded := repository.load()
	assert_true(loaded.ok)
	if not loaded.ok:
		return
	assert_eq(loaded.profile.meta_currency, 5, "a no-op failure must leave the profile untouched")
	assert_eq(loaded.profile.settlement_receipts.size(), 0)


func test_each_storage_fault_point_terminates_leaving_prior_state_intact_then_retry_succeeds_exactly_once() -> void:
	var faults: Array[StorageFaultKey] = [
		StorageFaultKey.new(StorageFaultKey.DIRECTORY, StorageFaultKey.MAIN, 0),
		StorageFaultKey.new(StorageFaultKey.OPEN_WRITE, StorageFaultKey.TMP, 0),
		StorageFaultKey.new(StorageFaultKey.READ, StorageFaultKey.MAIN, 0),
		# w2 review addition: RENAME/tmp/0 is save()'s promote sub-step
		# (SaveRepository._save_while_owned's `_storage.rename(TMP, MAIN)`),
		# confirmed via FakeSaveStorage.journal_snapshot() to be RENAME's first
		# (and, in this fixture's single-rotation scenario, only) occurrence on
		# the "tmp" logical path.
		StorageFaultKey.new(StorageFaultKey.RENAME, StorageFaultKey.TMP, 0),
		# w2 review addition: READ/main/2 is save()'s final-readback sub-step
		# (the `_read_candidate(MAIN)` immediately after promote). Occurrences
		# 0 and 1 of READ/main are consumed earlier in the same dispatch() by
		# load()'s pre-existing-main reread and save()'s pre-rotation main
		# reread respectively -- confirmed via journal_snapshot(), not guessed.
		StorageFaultKey.new(StorageFaultKey.READ, StorageFaultKey.MAIN, 2),
	]
	for fault: StorageFaultKey in faults:
		var table := _reward_table()
		var run := _terminal_run(&"commander.fixture", 3, 3, 5, 1, 42)
		var storage := FakeSaveStorage.new()
		var repository := SaveRootFixture.create_repository(storage)
		add_child_autofree(repository)
		assert_true(
			repository.save(_seed_root(run, 0, 0, [])).ok,
			"fixture seed save must succeed before fault injection: %s" % String(fault.operation_kind)
		)
		var expected_delta: int = MetaRewardComputeService.compute(
			5, 1, 3, 3, SettlementReceiptState.Outcome.COMPLETED, table
		)

		storage.reset_journal()
		storage.inject_fault(fault)
		var command := MetaSettlementCommand.new(repository, table, "0.1.0", FixedRunCommitClock.new())
		var failed_result := command.dispatch()
		assert_false(
			failed_result.ok,
			"dispatch must fail when %s/%s is faulted" % [
				String(fault.operation_kind), String(fault.logical_path)
			]
		)
		assert_eq(failed_result.error.code, MetaSettlementCommandError.SAVE_FAILED)

		var after_failure := repository.load()
		assert_true(after_failure.ok)
		if not after_failure.ok:
			continue
		assert_eq(
			after_failure.run_status, LoadResult.RunStatus.LOADED,
			"a terminated save must leave the prior active run intact: %s" % String(fault.operation_kind)
		)
		assert_not_null(after_failure.run)
		assert_eq(
			after_failure.profile.meta_currency, 0,
			"a terminated save must not have applied any currency: %s" % String(fault.operation_kind)
		)
		assert_eq(after_failure.profile.settlement_receipts.size(), 0)

		storage.clear_faults()
		var retried_command := MetaSettlementCommand.new(
			repository, table, "0.1.0", FixedRunCommitClock.new()
		)
		var retried_result := retried_command.dispatch()
		assert_true(
			retried_result.ok,
			"retry after clearing %s must succeed" % String(fault.operation_kind)
		)
		if not retried_result.ok:
			continue

		var after_retry := repository.load()
		assert_true(after_retry.ok)
		if not after_retry.ok:
			continue
		assert_eq(after_retry.run_status, LoadResult.RunStatus.NONE)
		assert_null(after_retry.run)
		assert_eq(
			after_retry.profile.meta_currency, expected_delta,
			"exactly one increment after fault-then-retry for %s" % String(fault.operation_kind)
		)
		assert_eq(after_retry.profile.settlement_receipts.size(), 1)


func _terminal_run(
	commander_id: StringName,
	challenge_level: int,
	defeated_boss_count: int,
	cleared_normal_count: int,
	cleared_elite_count: int,
	expedition_hp: int
) -> RunState:
	var run := SaveRootFixture.create_valid_root().run
	run.commander_id = commander_id
	run.challenge_level = challenge_level
	run.run_phase = RunState.RunPhase.RESULTS
	run.resolution_state = IdleResolutionState.new()
	run.expedition_hp = expedition_hp
	run.defeated_boss_count = defeated_boss_count
	run.cleared_normal_count = cleared_normal_count
	run.cleared_elite_count = cleared_elite_count
	if expedition_hp > 0:
		# RunStateValidator._validate_phase_resolution_pair requires either
		# expedition_hp==0 or the act-3 boss node completed for RunPhase.RESULTS
		# to validate -- mirrors tests/unit/economy_expediton/
		# test_battle_settlement_and_rewards.gd's _replace_node_kind() pattern.
		var node_key_result := RuntimeKeySchemaRegistry.new().build_node(
			StringName(run.run_id), 3,
			MapNodeState.node_kind_to_token(MapNodeState.NodeKind.BOSS), 0, 0
		)
		assert(node_key_result.ok, "fixture must be able to build a node key")
		var node_key := node_key_result.key_state as NodeKeyState
		var node := MapNodeState.new(
			String(node_key.digest), node_key, &"mapnode.fixture", 3, 0, 0,
			MapNodeState.NodeKind.BOSS,
			"a".repeat(64), null, true
		)
		var nodes: Array[MapNodeState] = [node]
		var edges: Array[MapEdgeState] = []
		var completed: Array[String] = [node.node_id]
		run.map_state = MapState.new(nodes, edges, null, completed)
		run.current_node_id = null
	return run


func _seed_root(
	run: RunState,
	currency: int,
	highest_challenge_level: int,
	records: Array[CommanderChallengeRecordState]
) -> SaveRoot:
	var base := SaveRootFixture.create_valid_root()
	var profile := ProfileState.new(
		base.profile.profile_id, base.profile.next_run_serial, currency,
		base.profile.unlocked_content_ids, base.profile.discovered_content_ids,
		highest_challenge_level, [], base.profile.settings_ref,
		base.profile.last_selection, records
	)
	return SaveRoot.new(
		base.schema_version, base.content_version, base.app_version,
		base.rng_version, base.hash_version, base.saved_at_utc,
		profile, run
	)


func _profile_only_root(currency: int) -> SaveRoot:
	var base := SaveRootFixture.create_valid_root()
	var empty_records: Array[CommanderChallengeRecordState] = []
	var profile := ProfileState.new(
		base.profile.profile_id, base.profile.next_run_serial, currency,
		base.profile.unlocked_content_ids, base.profile.discovered_content_ids,
		0, [], base.profile.settings_ref, base.profile.last_selection, empty_records
	)
	return SaveRoot.new(
		base.schema_version, base.content_version, base.app_version,
		base.rng_version, base.hash_version, base.saved_at_utc,
		profile, null
	)


## Aligned with §7.3 slice_default; duplicated locally per this suite's own
## convention (see tests/unit/meta_progression/test_meta_settlement_service.gd).
func _reward_table() -> MetaRewardTableDef:
	var table := MetaRewardTableDef.new()
	var scores: Array[EnumIntPairDef] = []
	scores.append(_score(&"normal", 1))
	scores.append(_score(&"elite", 3))
	scores.append(_score(&"merchant", 0))
	scores.append(_score(&"event", 0))
	scores.append(_score(&"rest", 0))
	scores.append(_score(&"treasure", 0))
	scores.append(_score(&"boss", 5))
	table.node_scores = scores
	table.completion_reward = 10
	table.failure_reward = 0
	var bps: Array[ChallengeMultiplierDef] = []
	bps.append(_bps(0, 10000))
	bps.append(_bps(1, 11000))
	bps.append(_bps(2, 12000))
	bps.append(_bps(3, 13000))
	bps.append(_bps(4, 14000))
	bps.append(_bps(5, 15000))
	table.challenge_multiplier_bps = bps
	table.id = &"meta_reward_table.test_fixture"
	table.display_name_key = &"loc.meta_reward_table_test_fixture"
	return table


func _score(key: StringName, value: int) -> EnumIntPairDef:
	var pair := EnumIntPairDef.new()
	pair.enum_key = key
	pair.value_i32 = value
	return pair


func _bps(level: int, basis_points: int) -> ChallengeMultiplierDef:
	var entry := ChallengeMultiplierDef.new()
	entry.challenge_level = level
	entry.basis_points = basis_points
	return entry
