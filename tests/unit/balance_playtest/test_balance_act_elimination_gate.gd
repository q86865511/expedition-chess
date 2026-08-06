extends GutTest

## DC-REQ-008（difficulty-curve T08）per-act 淘汰 gate：
## (a) `BALANCE_ACT_ELIMINATION_FLAT` 只在 cohort seed_count ≥ 1000、淘汰數 > 0 且
##     全部淘汰集中於單一幕時輸出；
## (b) `to_json()` 發布 `act_curve` 聚合區塊（各幕進入／淘汰／勝敗）供人工判讀；
## (c) 本檔與 `tools/balance/tests/test-act-elimination-gate.ps1` 消費同一份 golden
##     （`GOLDEN_PATH`），兩份實作必須對每個 scenario 產出逐字相同的 token 與 gate reason。

const GOLDEN_PATH := "res://tests/fixtures/balance_playtest/act_elimination_golden.json"


func test_golden_scenarios_match_pinned_act_curve_token_and_gate_reasons() -> void:
	var scenarios := _golden_scenarios()
	assert_eq(scenarios.size(), 5, "golden 必須涵蓋門檻上下、單幕集中與跨幕分布")
	for scenario_value: Variant in scenarios:
		var scenario := scenario_value as Dictionary
		var name := String(scenario["name"])
		var report := _report_for(scenario)
		assert_eq(
			report.cases.size(), (scenario["case_proofs"] as Array).size(),
			"%s：golden case 必須全部通過 is_valid()" % name
		)
		assert_false(
			report.gate_reasons(false).has(&"BALANCE_CASE_INVALID"),
			"%s：golden case 不得被判為無效" % name
		)
		assert_eq(
			report.act_curve_token(), String(scenario["expected_act_curve_token"]),
			"%s：act_curve token 必須與 golden 逐字相同" % name
		)
		assert_eq(
			_act_gate_reasons(report), _expected_reasons(scenario),
			"%s：act gate reason 必須與 golden 逐字相同" % name
		)


func test_report_json_publishes_act_curve_aggregate_block() -> void:
	var scenario := _scenario(&"spread_act1_and_act2")
	var report := _report_for(scenario)
	var parsed := JSON.parse_string(report.to_json(false)) as Dictionary
	var curve := parsed["act_curve"] as Dictionary
	assert_eq(int(curve["min_seed_count"]), 1000)
	assert_true(curve["enforced"], "seed_count 1000 必須啟用 per-act 淘汰 gate")
	assert_eq(curve["token"], String(scenario["expected_act_curve_token"]))
	assert_eq(int(curve["elimination_total"]), 2)
	assert_eq(curve["elimination_acts"], [1.0, 2.0])
	var acts := curve["acts"] as Array
	assert_eq(acts.size(), 3, "act_curve 必須固定輸出三幕，未進入的幕以 0 呈現")
	var act2 := acts[1] as Dictionary
	assert_eq(int(act2["act_index"]), 2)
	assert_eq(int(act2["entered"]), 2, "act2 只有兩個 case 留下快照")
	assert_eq(int(act2["eliminated"]), 1)
	assert_eq(int(act2["battle_wins"]), 3)
	assert_eq(int(act2["battle_losses"]), 1)


func test_gate_is_disabled_below_tune_threshold_and_enabled_at_it() -> void:
	assert_eq(
		BalanceBotReport.ACT_ELIMINATION_MIN_SEED_COUNT, 1000,
		"門檻是 TUNE 值，改動必須連同 golden 與 PowerShell 鏡射一起改"
	)
	var below := _report_for(_scenario(&"flat_act1_below_threshold"))
	assert_false(
		below.gate_reasons(false).has(&"BALANCE_ACT_ELIMINATION_FLAT"),
		"seed_count 999 的單幕集中是統計噪音，不得評估"
	)
	var at_threshold := _report_for(_scenario(&"flat_act1_at_threshold"))
	assert_true(
		at_threshold.gate_reasons(false).has(&"BALANCE_ACT_ELIMINATION_FLAT"),
		"seed_count 1000 且敗局全落在 act1 必須 FAIL"
	)
	assert_false(
		at_threshold.passed(false),
		"觸發 per-act 淘汰 gate 的 cohort 不得算 PASS"
	)


func test_gate_ignores_cohorts_without_any_elimination() -> void:
	var report := _report_for(_scenario(&"no_elimination_at_threshold"))
	assert_false(
		report.gate_reasons(false).has(&"BALANCE_ACT_ELIMINATION_FLAT"),
		"零淘汰不是單幕集中，另有 perfect win rate gate 負責"
	)


func _golden_scenarios() -> Array:
	assert_true(FileAccess.file_exists(GOLDEN_PATH), "missing golden: %s" % GOLDEN_PATH)
	var file := FileAccess.open(GOLDEN_PATH, FileAccess.READ)
	if file == null:
		return []
	var parsed := JSON.parse_string(file.get_as_text()) as Dictionary
	file.close()
	return parsed["scenarios"] as Array


func _scenario(name: StringName) -> Dictionary:
	for scenario_value: Variant in _golden_scenarios():
		var scenario := scenario_value as Dictionary
		if String(scenario["name"]) == String(name):
			return scenario
	assert_true(false, "golden 缺少 scenario：%s" % String(name))
	return {}


func _report_for(scenario: Dictionary) -> BalanceBotReport:
	var candidate := BalanceCandidateDescriptor.new(
		&"", "test", "a".repeat(64), 1,
		[BalanceTuneEntry.new(&"economy.reroll_cost", "2")] as Array[BalanceTuneEntry]
	)
	var report := BalanceBotReport.new(candidate, int(scenario["cohort_seed_count"]))
	for proof_value: Variant in scenario["case_proofs"] as Array:
		report.append(_case_from(proof_value as Dictionary))
	return report


func _case_from(proof: Dictionary) -> BalanceBotCaseResult:
	var value := BalanceBotCaseResult.new()
	value.strategy_id = StringName(proof["strategy_id"])
	value.seed_index = int(proof["seed_index"])
	value.run_id = &"golden_run"
	value.world_digest = "b".repeat(64)
	value.terminal = bool(proof["terminal"])
	value.won = bool(proof["won"])
	value.act_reached = int(proof["act_reached"])
	value.build_id = &"build.trait.golden"
	value.ending_gold = BalanceBotStrategy.IDS.find(value.strategy_id) + 1
	value.final_phase = &"RESULTS"
	value.settlement_receipt_digests = ["settlement"]
	value.reward_receipt_digests = ["reward"]
	value.replay_digest = "digest-%s" % String(value.strategy_id)
	var snapshots: Array[BalanceBotActSnapshot] = []
	for snapshot_value: Variant in proof["act_snapshots"] as Array:
		var snapshot := snapshot_value as Dictionary
		var unit_ids: Array[StringName] = []
		for unit_id: Variant in snapshot["stable_unit_ids"] as Array:
			unit_ids.append(StringName(unit_id))
		snapshots.append(BalanceBotActSnapshot.new(
			int(snapshot["act_index"]),
			int(snapshot["gold"]),
			int(snapshot["expedition_hp"]),
			int(snapshot["roster_unit_count"]),
			int(snapshot["board_unit_count"]),
			unit_ids,
			int(snapshot["battle_wins"]),
			int(snapshot["battle_losses"]),
			StringName(snapshot["elimination_node_id"])
		))
	value.act_snapshots = snapshots
	return value


func _act_gate_reasons(report: BalanceBotReport) -> Array[String]:
	var result: Array[String] = []
	for reason: StringName in report.gate_reasons(false):
		if String(reason).begins_with("BALANCE_ACT_"):
			result.append(String(reason))
	return result


func _expected_reasons(scenario: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for reason: Variant in scenario["expected_gate_reasons"] as Array:
		result.append(String(reason))
	return result
