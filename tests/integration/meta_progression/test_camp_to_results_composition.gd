extends GutTest

## T11 (specs/meta-progression/design.md §4.4, §5.1; requirements.md S5-AC-008; tasks.md
## T11; design.md §12 test case 008 "test_end_to_end_settlement_atomic_and_returns_to_camp")
## — proves the composition-root-level claim S5-AC-008 makes: starting an expedition and
## then settling it (win or loss) drives AppStateMachine CAMP -> RUN -> RESULTS -> CAMP, with
## the six settlement items (currency/receipt/highest_challenge_level/per-commander
## record/active-run-clear, all named in design.md §5.1 point 4-5) landing in the SAME atomic
## SaveRoot as the state transition's commit proof, and a second settlement attempt after
## RESULTS is reached is a genuine no-op (S5-AC-007's exactly-once guard, re-affirmed here at
## the app-flow level rather than the service level tests/integration/meta_progression/
## test_meta_settlement_command.gd already covers).
##
## 範圍聲明：本檔不模擬三幕真實戰鬥（S2/S3 已測、非本任務範圍）——terminal RunState 直接建構
## 成「已打完」的樣子，比照 tests/integration/meta_progression/test_meta_settlement_command.gd
## 自己的 _terminal_run() 手法（該檔 :223-261）與 design.md §12 測試策略表的「單元/整合」分層
## （本表把 007/008 都標「整合」，不要求連著實跑一次 combat）。StartExpeditionCommand 段沿用
## 既有 T05 fixture（tests/fixtures/camp/start_expedition_test_fixture.gd），只用於把
## AppStateMachine 帶進 RUN 狀態，不重測 T05 自己的驗收（那些已在
## tests/integration/meta_progression/test_camp_controller_start_expedition.gd 鎖定）。
##
## 假設聲明（design.md §4.4 的模組圖把 StartExpeditionCommand／MetaSettlementCommand 都畫在
## CampController 到 AppStateMachine.transition_after_save 的箭頭下，但兩個既有 result 型別
## 目前都不攜帶呼叫 AppStateMachine.transition_after_save()/transition_after_active_run_load()
## 所需的 SaveResult——CampController.dispatch_start_expedition()／MetaSettlementCommand.
## dispatch() 都是自己內部呼叫 SaveRepository.save() 後只留下 .ok/.error，SaveResult 物件本身
## 沒有被回傳。AppStateMachine._consume_save_commit() 要求的是「這個 repository 這次 save()
## 呼叫親自發出的那個 SaveResult 物件」（services/save/save_repository.gd:230-242 的 one-time
## capability token，偽造或重用都會被拒），composition root 不可能自己generic 造一個。這是
## test-author 的 binding decision：兩個既有 result 型別各自新增一個唯讀欄位
## `save_result: SaveResult`（成功時＝該次呼叫 SaveRepository.save() 實際回傳的物件；失敗時＝
## null），供 AppRoot／composition root 原樣轉呈給 AppStateMachine.transition_after_save()。
## 這是「新增欄位」而非「改動既有簽章」：StartExpeditionCampResult.success(profile, run) 與
## MetaSettlementCommandResult.success() 這兩個既有的 static 建構式，呼叫端傳入的參數不變，
## 既有呼叫點（tests/integration/meta_progression/test_camp_controller_start_expedition.gd、
## tests/integration/meta_progression/test_meta_settlement_command.gd）完全不受影響——本檔是
## 唯一讀取 .save_result 欄位的呼叫端。

func test_start_then_complete_settlement_transitions_camp_run_results_camp_atomically() -> void:
	var storage := FakeSaveStorage.new()
	var repository := StartExpeditionTestFixture.repository_for(storage)
	add_child_autofree(repository)
	var profile := StartExpeditionTestFixture.base_profile(5)
	var controller := StartExpeditionTestFixture.controller_for(profile, repository)
	var machine := AppStateMachine.new(repository)

	assert_true(machine.transition(AppEvent.new(AppEvent.Kind.BOOT_COMPLETED)).ok)
	assert_true(machine.transition(AppEvent.new(AppEvent.Kind.OPEN_CAMP)).ok)
	assert_eq(machine.state(), AppStateMachine.State.CAMP)

	var start_command := StartExpeditionCommand.new(
		StartExpeditionTestFixture.COMMANDER_ALPHA_ID,
		StartExpeditionTestFixture.commander_alpha(), 0,
		StartExpeditionTestFixture.receipt(), StartExpeditionTestFixture.catalog()
	)
	var start_result := controller.dispatch_start_expedition(start_command)
	assert_true(start_result.ok, String(start_result.error.code) if not start_result.ok else "ok")
	if not start_result.ok:
		return
	assert_not_null(
		start_result.save_result,
		"StartExpeditionCampResult must carry the SaveRepository.save() proof AppStateMachine" +
		" .transition_after_save(START_RUN, ...) requires"
	)
	var started := machine.transition_after_save(
		AppEvent.new(AppEvent.Kind.START_RUN), start_result.save_result
	)
	assert_true(started.ok, String(started.error.code) if not started.ok else "ok")
	assert_eq(machine.state(), AppStateMachine.State.RUN)

	# The run this fixture bootstraps is fresh (run_phase == MAP); S2/S3 combat is out of
	# scope here (see header). Overwrite the persisted run with a "already played to a boss
	# clear" terminal shape, exactly mirroring test_meta_settlement_command.gd's own
	# _terminal_run() technique, so MetaSettlementCommand has a COMPLETED-outcome run to
	# settle.
	var after_start := repository.load()
	assert_true(after_start.ok)
	if not after_start.ok:
		return
	var terminal_run := _completed_terminal_run(after_start.run)
	var reseed := repository.save(SaveRoot.new(
		SaveJsonCodec.SCHEMA_VERSION, StartExpeditionTestFixture.receipt().content_version,
		StartExpeditionTestFixture.APP_VERSION, 1, 1, "2026-07-25T00:00:00Z",
		after_start.profile, terminal_run
	))
	assert_true(reseed.ok, "test setup: seeding the terminal run must succeed")

	var table := _reward_table()
	var settle_command := MetaSettlementCommand.new(
		repository, table, StartExpeditionTestFixture.APP_VERSION, FixedRunCommitClock.new()
	)
	var settle_result := settle_command.dispatch()
	assert_true(settle_result.ok, String(settle_result.error.code) if not settle_result.ok else "ok")
	if not settle_result.ok:
		return
	assert_not_null(
		settle_result.save_result,
		"MetaSettlementCommandResult must carry the SaveRepository.save() proof" +
		" AppStateMachine.transition_after_save(FINISH_RUN, ...) requires"
	)
	var finished := machine.transition_after_save(
		AppEvent.new(AppEvent.Kind.FINISH_RUN), settle_result.save_result
	)
	assert_true(finished.ok, String(finished.error.code) if not finished.ok else "ok")
	assert_eq(machine.state(), AppStateMachine.State.RESULTS)

	# design.md §5.1 point 4-5: currency/receipt/highest_challenge_level/per-commander
	# record/run==null all land in the ONE save that just backed the FINISH_RUN transition.
	var after_settlement := repository.load()
	assert_true(after_settlement.ok)
	if not after_settlement.ok:
		return
	assert_eq(after_settlement.run_status, LoadResult.RunStatus.NONE, "active run must be cleared")
	assert_null(after_settlement.run)
	var expected_delta: int = MetaRewardComputeService.compute(
		4, 2, 3, 0, SettlementReceiptState.Outcome.COMPLETED, table
	)
	assert_eq(after_settlement.profile.meta_currency, expected_delta)
	assert_eq(after_settlement.profile.settlement_receipts.size(), 1)
	assert_eq(after_settlement.profile.settlement_receipts[0].outcome, SettlementReceiptState.Outcome.COMPLETED)
	assert_eq(after_settlement.profile.highest_challenge_level, 0)
	assert_eq(after_settlement.profile.commander_challenge_records.size(), 1)
	assert_eq(
		after_settlement.profile.commander_challenge_records[0].commander_id,
		StartExpeditionTestFixture.COMMANDER_ALPHA_ID
	)

	var acknowledged := machine.transition(AppEvent.new(AppEvent.Kind.ACKNOWLEDGE_RESULTS))
	assert_true(acknowledged.ok, String(acknowledged.error.code) if not acknowledged.ok else "ok")
	assert_eq(
		machine.state(), AppStateMachine.State.CAMP,
		"acknowledging RESULTS must return the app to a playable camp (S5-AC-008)"
	)

	# S5-AC-007/008 "重載 RESULTS 不重複發放": with the active run already cleared, a second
	# dispatch() against the SAME terminal run_id must be a genuine no-op at the command
	# level too (not just the service-level idempotent-receipt guard T02 already tests).
	var repeat_command := MetaSettlementCommand.new(
		repository, table, StartExpeditionTestFixture.APP_VERSION, FixedRunCommitClock.new()
	)
	var repeat_result := repeat_command.dispatch()
	assert_false(repeat_result.ok)
	assert_eq(repeat_result.error.code, MetaSettlementCommandError.NO_ACTIVE_RUN)
	var after_repeat := repository.load()
	assert_true(after_repeat.ok)
	if after_repeat.ok:
		assert_eq(
			after_repeat.profile.meta_currency, expected_delta,
			"a second settlement attempt after CAMP must not award currency again"
		)


func test_expedition_hp_zero_failure_settlement_is_also_atomic_and_returns_to_camp() -> void:
	var storage := FakeSaveStorage.new()
	var repository := StartExpeditionTestFixture.repository_for(storage)
	add_child_autofree(repository)
	var profile := StartExpeditionTestFixture.base_profile(5)
	var controller := StartExpeditionTestFixture.controller_for(profile, repository)
	var machine := AppStateMachine.new(repository)
	assert_true(machine.transition(AppEvent.new(AppEvent.Kind.BOOT_COMPLETED)).ok)
	assert_true(machine.transition(AppEvent.new(AppEvent.Kind.OPEN_CAMP)).ok)

	var start_result := controller.dispatch_start_expedition(StartExpeditionCommand.new(
		StartExpeditionTestFixture.COMMANDER_BETA_ID,
		StartExpeditionTestFixture.commander_beta(), 0,
		StartExpeditionTestFixture.receipt(), StartExpeditionTestFixture.catalog()
	))
	assert_true(start_result.ok)
	if not start_result.ok:
		return
	assert_true(machine.transition_after_save(
		AppEvent.new(AppEvent.Kind.START_RUN), start_result.save_result
	).ok)

	var after_start := repository.load()
	assert_true(after_start.ok)
	if not after_start.ok:
		return
	var terminal_run := _hp_zero_terminal_run(after_start.run)
	assert_true(repository.save(SaveRoot.new(
		SaveJsonCodec.SCHEMA_VERSION, StartExpeditionTestFixture.receipt().content_version,
		StartExpeditionTestFixture.APP_VERSION, 1, 1, "2026-07-25T00:00:00Z",
		after_start.profile, terminal_run
	)).ok)

	var table := _reward_table()
	var settle_result := MetaSettlementCommand.new(
		repository, table, StartExpeditionTestFixture.APP_VERSION, FixedRunCommitClock.new()
	).dispatch()
	assert_true(settle_result.ok, String(settle_result.error.code) if not settle_result.ok else "ok")
	if not settle_result.ok:
		return
	assert_true(machine.transition_after_save(
		AppEvent.new(AppEvent.Kind.FINISH_RUN), settle_result.save_result
	).ok)
	assert_eq(machine.state(), AppStateMachine.State.RESULTS)

	var after_settlement := repository.load()
	assert_true(after_settlement.ok)
	if not after_settlement.ok:
		return
	assert_null(after_settlement.run)
	assert_eq(after_settlement.profile.settlement_receipts[0].outcome, SettlementReceiptState.Outcome.FAILED)
	assert_eq(
		after_settlement.profile.highest_challenge_level, 0,
		"a failed (HP-zero) expedition must never advance highest_challenge_level"
	)
	assert_true(
		after_settlement.profile.commander_challenge_records.is_empty(),
		"FAILED outcome must not create/update a per-commander challenge record"
	)

	assert_true(machine.transition(AppEvent.new(AppEvent.Kind.ACKNOWLEDGE_RESULTS)).ok)
	assert_eq(machine.state(), AppStateMachine.State.CAMP)


## Boss node cleared, defeated_boss_count == 3 -> MetaSettlementService resolves COMPLETED.
func _completed_terminal_run(run: RunState) -> RunState:
	var terminal := run.deep_clone()
	terminal.run_phase = RunState.RunPhase.RESULTS
	terminal.resolution_state = IdleResolutionState.new()
	terminal.expedition_hp = 60
	terminal.defeated_boss_count = 3
	terminal.cleared_normal_count = 4
	terminal.cleared_elite_count = 2
	var node_key_result := RuntimeKeySchemaRegistry.new().build_node(
		StringName(terminal.run_id), 3, MapNodeState.node_kind_to_token(MapNodeState.NodeKind.BOSS), 0, 0
	)
	var node_key := node_key_result.key_state as NodeKeyState
	var node := MapNodeState.new(
		String(node_key.digest), node_key, &"mapnode.boss_fixture", 3, 0, 0,
		MapNodeState.NodeKind.BOSS, "a".repeat(64), null, true
	)
	var empty_edges: Array[MapEdgeState] = []
	terminal.map_state = MapState.new([node], empty_edges, null, [node.node_id])
	terminal.current_node_id = null
	return terminal


## expedition_hp == 0 and no boss clear -> MetaSettlementService resolves FAILED (S3's HP-zero
## and boss-retry-abandon paths both terminate here indistinguishably, per design.md §5.1
## point1's documented w2 decision).
func _hp_zero_terminal_run(run: RunState) -> RunState:
	var terminal := run.deep_clone()
	terminal.run_phase = RunState.RunPhase.RESULTS
	terminal.resolution_state = IdleResolutionState.new()
	terminal.expedition_hp = 0
	terminal.defeated_boss_count = 0
	terminal.cleared_normal_count = 1
	terminal.cleared_elite_count = 0
	terminal.current_node_id = null
	return terminal


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
	table.challenge_multiplier_bps = bps
	table.id = &"meta_reward_table.t11_e2e_fixture"
	table.display_name_key = &"loc.meta_reward_table_t11_e2e_fixture"
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
