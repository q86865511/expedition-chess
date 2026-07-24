extends GutTest

## T02 (specs/meta-progression) — MetaSettlementService.settle() 驗收（wave2 TDD 紅燈）。
## Covers：REQ-META-004、REQ-DATA-007、S5-AC-007（純計算/記錄更新段）、
## S5-AC-009（紀錄更新段）。對應 design.md §5.1（流程五步的第 1、2、3、4 步——
## 第 5 步的 SaveRoot(profile', run=null)/save/AppStateMachine 轉場屬命令層，見
## test_meta_settlement_command.gd）與 §12 測試案例 007／009。
##
## 假設聲明（design.md 未給精確簽名型別，依既有慣例＋design.md 逐字引用釘定，
## 比照本目錄 test_meta_reward_compute_service.gd 的既定作法）：
## 1. `MetaSettlementService.settle(profile, terminal_run, meta_reward_table)` 為
##    **static func**，回傳 `ProfileState`（profile' 本身，不包 Result）——design.md
##    兩處呼叫寫法（§1「MetaSettlementCommand→MetaSettlementService.settle(...)」、
##    §5.1 起始行）皆不帶 `.new()`，與同一流程內
##    `MetaRewardComputeService.compute(...)`（已證實為 static、直接回傳 int）並列
##    書寫風格一致；design.md 全篇把 settle() 的輸出直接稱為「profile'」，未提及
##    任何錯誤分支，比照 compute() 視為（給定合法輸入時）無需 Result 包裝的純推導。
##    是否有 active run／能否成功存檔屬命令層關切，見 MetaSettlementCommand。
## 2. outcome 判定依 design.md §5.1 point1 的優先序：
##    defeated_boss_count==3→COMPLETED（最優先）；否則 expedition_hp==0→FAILED；
##    ABANDONED（Boss 重戰放棄）因 RunState 現有欄位下與一般戰敗（_settle_loss）
##    終態完全重疊（皆 run_phase=RESULTS 且 expedition_hp=0，見
##    battle_settlement_service.gd 的 abandon_boss_retry/_settle_loss），任務簡報
##    明示「RunState 缺顯式訊號時回報測試爭議、不自創欄位」——本檔故不測 ABANDONED
##    的判定路徑，僅測 COMPLETED／FAILED 兩個可由既有欄位無歧義推導的分支。
## 3. currency_delta 一律呼叫 `MetaRewardComputeService.compute(cleared_normal_count,
##    cleared_elite_count, defeated_boss_count, challenge_level, outcome, table)`
##    （design.md §5.1 point2 明文），本檔測試一律以呼叫同一 compute() 的結果作為
##    oracle 比對，不手算算式（算式本身的正確性已由
##    test_meta_reward_compute_service.gd 鎖定，本檔只驗證 settle() 有沒有正確
##    委派並疊加 profile 副作用）。
## 4. 冪等守衛（design.md §5.1 point3）：「若 profile.settlement_receipts 已含此
##    key.digest→currency_delta 視為 0（不重發），仍授權清 run」。本檔採最保守、
##    與 RunStateValidator 強制的「settlement_receipts 嚴格遞增無重複 digest」
##    約束唯一相容的解讀：命中冪等分支時，整個 point4 更新區塊（currency／
##    receipts／highest_challenge_level／commander_challenge_records）原封不動
##    跳過——因為任何「附加第二筆同 digest receipt」的實作都會被驗證器拒絕，
##    此路徑不可能是設計意圖。「仍授權清 run」是呼叫端（Command）的職責，不在
##    settle() 回傳的 ProfileState 本身可觀察，見 test_meta_settlement_command.gd。

func test_settle_completed_creates_first_time_commander_record_and_updates_global_highest() -> void:
	var table := _reward_table()
	var profile := _profile(0, 0, [], [])
	var run := _terminal_run(
		"run.scenario.first_completion", &"commander.fixture", 2,
		3, 4, 2, 60
	)
	var expected_delta: int = MetaRewardComputeService.compute(
		4, 2, 3, 2, SettlementReceiptState.Outcome.COMPLETED, table
	)

	var settled: ProfileState = MetaSettlementService.settle(profile, run, table)

	assert_eq(settled.meta_currency, expected_delta)
	assert_eq(settled.settlement_receipts.size(), 1)
	var receipt: SettlementReceiptState = settled.settlement_receipts[0]
	assert_eq(receipt.outcome, SettlementReceiptState.Outcome.COMPLETED)
	assert_eq(receipt.currency_delta, expected_delta)
	assert_eq(settled.highest_challenge_level, 2)
	assert_eq(settled.commander_challenge_records.size(), 1)
	assert_eq(settled.commander_challenge_records[0].commander_id, &"commander.fixture")
	assert_eq(settled.commander_challenge_records[0].highest_cleared_level, 2)


func test_settle_completed_updates_commander_record_to_max_without_regressing() -> void:
	var table := _reward_table()
	var existing_records: Array[CommanderChallengeRecordState] = [
		CommanderChallengeRecordState.new(&"commander.alpha", 4),
	]
	var profile := _profile(50, 4, existing_records, [])
	# challenge_level=1 is LOWER than the commander's existing record of 4 --
	# a completion at a lower level must never regress the recorded max.
	var run := _terminal_run(
		"run.scenario.regression_attempt", &"commander.alpha", 1,
		3, 1, 0, 80
	)
	var expected_delta: int = MetaRewardComputeService.compute(
		1, 0, 3, 1, SettlementReceiptState.Outcome.COMPLETED, table
	)

	var settled: ProfileState = MetaSettlementService.settle(profile, run, table)

	assert_eq(settled.meta_currency, 50 + expected_delta)
	assert_eq(settled.highest_challenge_level, 4, "global highest must not regress")
	assert_eq(settled.commander_challenge_records.size(), 1)
	assert_eq(
		settled.commander_challenge_records[0].highest_cleared_level, 4,
		"commander's own record must not regress to the lower completed level"
	)


func test_settle_completed_leaves_other_commanders_records_untouched() -> void:
	var table := _reward_table()
	var existing_records: Array[CommanderChallengeRecordState] = [
		CommanderChallengeRecordState.new(&"commander.alpha", 2),
		CommanderChallengeRecordState.new(&"commander.beta", 5),
	]
	var profile := _profile(10, 5, existing_records, [])
	var run := _terminal_run(
		"run.scenario.new_high", &"commander.alpha", 6,
		3, 2, 1, 70
	)
	var expected_delta: int = MetaRewardComputeService.compute(
		2, 1, 3, 6, SettlementReceiptState.Outcome.COMPLETED, table
	)

	var settled: ProfileState = MetaSettlementService.settle(profile, run, table)

	assert_eq(settled.meta_currency, 10 + expected_delta)
	assert_eq(settled.highest_challenge_level, 6, "global highest tracks the new max across all commanders")
	assert_eq(settled.commander_challenge_records.size(), 2)
	var alpha := _find_record(settled.commander_challenge_records, &"commander.alpha")
	var beta := _find_record(settled.commander_challenge_records, &"commander.beta")
	assert_not_null(alpha)
	assert_not_null(beta)
	if alpha != null:
		assert_eq(alpha.highest_cleared_level, 6)
	if beta != null:
		assert_eq(beta.highest_cleared_level, 5, "a different commander's record must be untouched")
	assert_true(
		String(settled.commander_challenge_records[0].commander_id)
		< String(settled.commander_challenge_records[1].commander_id),
		"commander_challenge_records must remain sorted ascending by commander_id"
	)


func test_settle_completed_inserts_new_commander_record_in_sorted_position() -> void:
	var table := _reward_table()
	var existing_records: Array[CommanderChallengeRecordState] = [
		CommanderChallengeRecordState.new(&"commander.alpha", 1),
		CommanderChallengeRecordState.new(&"commander.zeta", 1),
	]
	var profile := _profile(0, 1, existing_records, [])
	var run := _terminal_run(
		"run.scenario.middle_commander_first_clear", &"commander.mid", 3,
		3, 0, 0, 90
	)

	var settled: ProfileState = MetaSettlementService.settle(profile, run, table)

	assert_eq(settled.commander_challenge_records.size(), 3)
	var ids: Array[String] = []
	for record: CommanderChallengeRecordState in settled.commander_challenge_records:
		ids.append(String(record.commander_id))
	assert_eq(ids, ["commander.alpha", "commander.mid", "commander.zeta"])
	var mid := _find_record(settled.commander_challenge_records, &"commander.mid")
	assert_not_null(mid)
	if mid != null:
		assert_eq(mid.highest_cleared_level, 3)


func test_settle_failed_outcome_does_not_touch_challenge_records_or_global_highest() -> void:
	var table := _reward_table()
	var existing_records: Array[CommanderChallengeRecordState] = [
		CommanderChallengeRecordState.new(&"commander.alpha", 2),
	]
	var profile := _profile(20, 2, existing_records, [])
	var run := _terminal_run(
		"run.scenario.failed_attempt", &"commander.alpha", 9,
		1, 2, 1, 0
	)
	var expected_delta: int = MetaRewardComputeService.compute(
		2, 1, 1, 9, SettlementReceiptState.Outcome.FAILED, table
	)

	var settled: ProfileState = MetaSettlementService.settle(profile, run, table)

	assert_eq(settled.meta_currency, 20 + expected_delta)
	assert_eq(settled.settlement_receipts.size(), 1)
	assert_eq(settled.settlement_receipts[0].outcome, SettlementReceiptState.Outcome.FAILED)
	assert_eq(settled.highest_challenge_level, 2, "FAILED must never advance the global highest")
	assert_eq(settled.commander_challenge_records.size(), 1)
	assert_eq(
		settled.commander_challenge_records[0].highest_cleared_level, 2,
		"FAILED must never advance a commander's own record"
	)


func test_settle_completed_outcome_precedes_zero_expedition_hp_check() -> void:
	# design.md §5.1 point1 lists "defeated_boss_count == 3 -> COMPLETED" first,
	# ahead of "expedition_hp == 0 -> FAILED". A run that satisfies both
	# simultaneously (final blow both defeats the boss and drains hp to 0) must
	# resolve as COMPLETED, not FAILED.
	var table := _reward_table()
	var profile := _profile(0, 0, [], [])
	var run := _terminal_run(
		"run.scenario.pyrrhic_victory", &"commander.fixture", 3,
		3, 1, 1, 0
	)
	var expected_completed_delta: int = MetaRewardComputeService.compute(
		1, 1, 3, 3, SettlementReceiptState.Outcome.COMPLETED, table
	)
	var expected_failed_delta: int = MetaRewardComputeService.compute(
		1, 1, 3, 3, SettlementReceiptState.Outcome.FAILED, table
	)
	# the two deltas must actually differ (completion_reward bonus only applies
	# to COMPLETED) or this test could pass for the wrong reason.
	assert_ne(expected_completed_delta, expected_failed_delta)

	var settled: ProfileState = MetaSettlementService.settle(profile, run, table)

	assert_eq(settled.meta_currency, expected_completed_delta)
	assert_eq(settled.settlement_receipts[0].outcome, SettlementReceiptState.Outcome.COMPLETED)
	assert_eq(settled.highest_challenge_level, 3, "only COMPLETED advances highest_challenge_level")


func test_settle_receipt_key_equals_build_settlement_receipt_for_run_id() -> void:
	var table := _reward_table()
	var profile := _profile(0, 0, [], [])
	var run := _terminal_run(
		"run.scenario.key_check", &"commander.fixture", 0,
		3, 0, 0, 50
	)
	var expected_key := RuntimeKeySchemaRegistry.new().build_settlement_receipt(
		&"run.scenario.key_check"
	)
	assert_true(expected_key.ok)

	var settled: ProfileState = MetaSettlementService.settle(profile, run, table)

	assert_eq(settled.settlement_receipts.size(), 1)
	assert_eq(settled.settlement_receipts[0].key.digest, expected_key.key_state.digest)
	assert_eq(settled.settlement_receipts[0].key.run_id, &"run.scenario.key_check")


func test_settle_is_idempotent_when_run_id_already_has_a_receipt() -> void:
	var table := _reward_table()
	var run_id := "run.scenario.already_settled"
	var existing_key := RuntimeKeySchemaRegistry.new().build_settlement_receipt(StringName(run_id))
	assert_true(existing_key.ok)
	var existing_receipt := SettlementReceiptState.new(
		existing_key.key_state as SettlementReceiptKeyState,
		SettlementReceiptState.Outcome.COMPLETED, 77, "c".repeat(64)
	)
	var existing_records: Array[CommanderChallengeRecordState] = [
		CommanderChallengeRecordState.new(&"commander.alpha", 2),
	]
	var profile := _profile(100, 2, existing_records, [existing_receipt])
	# a large, otherwise-lucrative COMPLETED run reusing the SAME run_id --
	# must be fully neutralized by the idempotent guard.
	var run := _terminal_run(
		run_id, &"commander.alpha", 9,
		3, 9, 9, 100
	)

	var settled: ProfileState = MetaSettlementService.settle(profile, run, table)

	assert_eq(settled.meta_currency, 100, "idempotent guard: currency_delta must be treated as 0")
	assert_eq(settled.settlement_receipts.size(), 1, "must not append a second receipt for the same run_id")
	assert_eq(settled.settlement_receipts[0].currency_delta, 77, "the original receipt must be left untouched")
	assert_eq(settled.highest_challenge_level, 2, "idempotent guard must not advance highest_challenge_level")
	assert_eq(settled.commander_challenge_records.size(), 1)
	assert_eq(
		settled.commander_challenge_records[0].highest_cleared_level, 2,
		"idempotent guard must not advance the commander's record"
	)


func test_settle_does_not_mutate_input_profile_or_terminal_run() -> void:
	var table := _reward_table()
	var existing_records: Array[CommanderChallengeRecordState] = [
		CommanderChallengeRecordState.new(&"commander.alpha", 2),
	]
	var profile := _profile(30, 2, existing_records, [])
	var run := _terminal_run(
		"run.scenario.purity_check", &"commander.alpha", 4,
		3, 1, 1, 55
	)
	var before_currency := profile.meta_currency
	var before_receipt_count := profile.settlement_receipts.size()
	var before_highest := profile.highest_challenge_level
	var before_record_count := profile.commander_challenge_records.size()
	var before_run_challenge_level := run.challenge_level
	var before_run_defeated_boss := run.defeated_boss_count

	var settled: ProfileState = MetaSettlementService.settle(profile, run, table)

	assert_eq(profile.meta_currency, before_currency, "input profile must not be mutated")
	assert_eq(profile.settlement_receipts.size(), before_receipt_count)
	assert_eq(profile.highest_challenge_level, before_highest)
	assert_eq(profile.commander_challenge_records.size(), before_record_count)
	assert_eq(run.challenge_level, before_run_challenge_level, "input terminal_run must not be mutated")
	assert_eq(run.defeated_boss_count, before_run_defeated_boss)
	# and the returned value must actually be a distinct instance carrying the
	# update, not merely the same reference handed back unchanged.
	assert_ne(settled.meta_currency, before_currency)


func _terminal_run(
	run_id: String,
	commander_id: StringName,
	challenge_level: int,
	defeated_boss_count: int,
	cleared_normal_count: int,
	cleared_elite_count: int,
	expedition_hp: int
) -> RunState:
	var run := SaveRootFixture.create_valid_root().run
	run.run_id = run_id
	run.commander_id = commander_id
	run.challenge_level = challenge_level
	run.run_phase = RunState.RunPhase.RESULTS
	run.resolution_state = IdleResolutionState.new()
	run.expedition_hp = expedition_hp
	run.defeated_boss_count = defeated_boss_count
	run.cleared_normal_count = cleared_normal_count
	run.cleared_elite_count = cleared_elite_count
	return run


func _profile(
	currency: int,
	highest_challenge_level: int,
	records: Array[CommanderChallengeRecordState],
	receipts: Array[SettlementReceiptState]
) -> ProfileState:
	var base := SaveRootFixture.create_valid_root().profile
	return ProfileState.new(
		base.profile_id, base.next_run_serial, currency, base.unlocked_content_ids,
		base.discovered_content_ids, highest_challenge_level, receipts,
		base.settings_ref, base.last_selection, records
	)


func _find_record(
	records: Array[CommanderChallengeRecordState],
	commander_id: StringName
) -> CommanderChallengeRecordState:
	for record: CommanderChallengeRecordState in records:
		if record.commander_id == commander_id:
			return record
	return null


## Aligned with §7.3 slice_default (see test_meta_reward_table_slice_default_alignment.gd);
## duplicated locally rather than shared, mirroring test_meta_reward_compute_service.gd's
## own `_aligned_table()` convention in this same directory.
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
	bps.append(_bps(6, 16000))
	bps.append(_bps(9, 19000))
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
