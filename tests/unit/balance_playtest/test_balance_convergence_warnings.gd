extends GutTest

## G2 Phase 2 R0（g2-roadmap §6.3b 收斂判準自動化）：
## (a) 三策略勝率 45~60% 帶與勝局血量分佈只產生報告欄位與 WARN 清單，
##     `gate_reasons()` 完全不消費——迭代中期偏離收斂帶不得讓 gate 變紅；
## (b) `to_json()` 發布 `convergence` 區塊供人工判讀與逐輪比較；
## (c) 本檔與 `tools/balance/tests/test-convergence-warnings.ps1` 消費同一份 golden
##     （`GOLDEN_PATH`），兩份實作必須對每個 scenario 產出逐字相同的 token 與 WARN。

const GOLDEN_PATH := "res://tests/fixtures/balance_playtest/convergence_golden.json"


func test_golden_scenarios_match_pinned_convergence_token_and_warnings() -> void:
	var scenarios := _golden_scenarios()
	assert_eq(scenarios.size(), 6, "golden 必須涵蓋帶內／過高／過低／滿血／零勝／帶邊界")
	for scenario_value: Variant in scenarios:
		var scenario := scenario_value as Dictionary
		var name := String(scenario["name"])
		var report := _report_for(scenario)
		assert_eq(
			report.cases.size(), (scenario["case_proofs"] as Array).size(),
			"%s：golden case 必須全部通過 is_valid()" % name
		)
		assert_eq(
			report.convergence_token(), String(scenario["expected_convergence_token"]),
			"%s：convergence token 必須與 golden 逐字相同" % name
		)
		assert_eq(
			report.convergence_warnings(), _expected_warnings(scenario),
			"%s：WARN 清單必須與 golden 逐字相同" % name
		)


func test_report_json_publishes_convergence_block() -> void:
	var scenario := _scenario(&"tempo_above_band")
	var report := _report_for(scenario)
	var parsed := JSON.parse_string(report.to_json(false)) as Dictionary
	var convergence := parsed["convergence"] as Dictionary
	assert_eq(int(convergence["win_rate_band_low_bps"]), 4500)
	assert_eq(int(convergence["win_rate_band_high_bps"]), 6000)
	assert_eq(int(convergence["win_hp_ceiling_warn_bps"]), 5000)
	assert_eq(convergence["token"], String(scenario["expected_convergence_token"]))
	var rows := convergence["strategy_win_rates"] as Array
	assert_eq(rows.size(), 3, "三策略各一列，缺樣本也要出現")
	var tempo := rows[0] as Dictionary
	assert_eq(String(tempo["strategy_id"]), "tempo")
	assert_eq(int(tempo["cases"]), 4)
	assert_eq(int(tempo["wins"]), 3)
	assert_eq(int(tempo["win_rate_bps"]), 7500)
	assert_false(tempo["in_band"], "7500 bps 超出 45~60% 帶")
	var distribution := convergence["win_hp_distribution"] as Dictionary
	assert_eq(int(distribution["win_case_count"]), 5)
	assert_eq(int(distribution["distinct_hp_count"]), 5)
	assert_eq(int(distribution["min_hp"]), 10)
	assert_eq(int(distribution["max_hp"]), 30)
	assert_eq(int(distribution["ceiling_win_count"]), 1)
	assert_eq(int(distribution["ceiling_win_rate_bps"]), 2000)
	assert_true(distribution["distributed"], "只有 20% 勝局停在觀測血量天花板＝有分佈")


## 這是本批改動的核心約束：收斂 WARN 是迭代訊號，不是 gate。任何一個 scenario
## 的 gate_reasons 都不得因為 WARN 而多出理由。
func test_warnings_never_enter_gate_reasons() -> void:
	for scenario_value: Variant in _golden_scenarios():
		var scenario := scenario_value as Dictionary
		var report := _report_for(scenario)
		var warnings := report.convergence_warnings()
		var reasons: Array[String] = []
		for reason: StringName in report.gate_reasons(false):
			reasons.append(String(reason))
		for warning: String in warnings:
			assert_false(
				reasons.has(warning),
				"%s：WARN %s 不得出現在 gate_reasons" % [String(scenario["name"]), warning]
			)
		for reason: String in reasons:
			assert_false(
				reason.begins_with("BALANCE_WARN_"),
				"%s：gate_reasons 不得含任何 WARN 前綴理由（%s）" % [
					String(scenario["name"]), reason
				]
			)


func test_band_boundaries_are_inclusive_on_both_ends() -> void:
	assert_eq(BalanceBotReport.WIN_RATE_BAND_LOW_BPS, 4500, "帶下緣是 TUNE 值，改動要連 PS 鏡射與 golden")
	assert_eq(BalanceBotReport.WIN_RATE_BAND_HIGH_BPS, 6000, "帶上緣是 TUNE 值，改動要連 PS 鏡射與 golden")
	assert_eq(BalanceBotReport.WIN_HP_CEILING_WARN_BPS, 5000, "滿血通關門檻是 TUNE 值")
	var edges := _report_for(_scenario(&"band_edges_are_inclusive"))
	assert_eq(
		edges.convergence_warnings(), [] as Array[String],
		"恰好落在 4500 與 6000 的策略必須算帶內，不得 WARN"
	)


func test_all_wins_at_observed_ceiling_warns_even_when_win_rates_are_in_band() -> void:
	var report := _report_for(_scenario(&"all_wins_at_hp_ceiling"))
	assert_eq(
		report.convergence_warnings(),
		["BALANCE_WARN_WIN_HP_NOT_DISTRIBUTED"] as Array[String],
		"三策略勝率都在帶內時，滿血通關仍必須被單獨標記"
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
	var proofs := scenario["case_proofs"] as Array
	@warning_ignore("integer_division")
	var report := BalanceBotReport.new(candidate, proofs.size() / 3)
	for proof_value: Variant in proofs:
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
	value.act_reached = 3 if value.won else 1
	value.build_id = &"build.trait.golden"
	value.ending_gold = BalanceBotStrategy.IDS.find(value.strategy_id) + 1
	value.ending_hp = int(proof["ending_hp"])
	value.final_phase = &"RESULTS"
	value.settlement_receipt_digests = ["settlement"]
	value.reward_receipt_digests = ["reward"]
	value.replay_digest = "digest-%s-%d" % [String(value.strategy_id), value.seed_index]
	return value


func _expected_warnings(scenario: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for warning: Variant in scenario["expected_warnings"] as Array:
		result.append(String(warning))
	return result
