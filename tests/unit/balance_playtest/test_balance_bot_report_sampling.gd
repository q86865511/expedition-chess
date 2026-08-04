extends GutTest


func test_replay_sampling_is_deterministic_five_percent_by_absolute_seed() -> void:
	assert_true(BalanceBotReport.replay_selected(0))
	assert_false(BalanceBotReport.replay_selected(1))
	assert_false(BalanceBotReport.replay_selected(19))
	assert_true(BalanceBotReport.replay_selected(20))
	assert_true(BalanceBotReport.replay_selected(40))
	var selected := 0
	for seed_index: int in range(1000, 2000):
		if BalanceBotReport.replay_selected(seed_index):
			selected += 1
	assert_eq(selected, 50, "任一對齊整數 cohort 的 replay 抽樣率必須恰為 5%")


func test_report_records_replay_sample_list_and_split_elapsed_metrics() -> void:
	var entries: Array[BalanceTuneEntry] = [
		BalanceTuneEntry.new(&"economy.reroll_cost", "2"),
	]
	var candidate := BalanceCandidateDescriptor.new(
		&"", "test", "a".repeat(64), 1, entries
	)
	var report := BalanceBotReport.new(candidate, 20)
	report.record_primary_elapsed_ms(80)
	report.record_primary_elapsed_ms(120)
	report.record_replay_sample(&"tempo", 0, 90, true)
	report.record_replay_sample(&"synergy", 20, 110, false)
	var parsed: Variant = JSON.parse_string(report.to_json(false))
	assert_true(parsed is Dictionary)
	if not parsed is Dictionary:
		return
	var payload := parsed as Dictionary
	var replay := payload["replay_validation"] as Dictionary
	assert_eq(replay["mode"], "deterministic_sample")
	assert_eq(int(replay["sample_rate_bps"]), 500)
	assert_eq(replay["selection_rule"], "seed_index % 20 == 0")
	assert_eq(int(replay["sampled_case_count"]), 2)
	assert_eq((replay["sampled_cases"] as Array)[0], {
		"strategy_id": "synergy", "seed_index": 20.0,
	})
	assert_eq((replay["sampled_cases"] as Array)[1], {
		"strategy_id": "tempo", "seed_index": 0.0,
	})
	assert_eq(replay["drift_case_ids"], ["synergy:20"])
	var metrics := payload["execution_metrics"] as Dictionary
	assert_eq(int(metrics["primary_case_count"]), 2)
	assert_eq(float(metrics["primary_mean_elapsed_ms"]), 100.0)
	assert_eq(int(metrics["replay_sample_count"]), 2)
	assert_eq(float(metrics["replay_mean_elapsed_ms"]), 100.0)
	assert_eq(float(metrics["effective_mean_elapsed_ms"]), 200.0)


func test_report_serializes_authoritative_case_proof_and_regression_evidence() -> void:
	var candidate := BalanceCandidateDescriptor.new(
		&"", "test", "a".repeat(64), 1,
		[BalanceTuneEntry.new(&"economy.reroll_cost", "2")] as Array[BalanceTuneEntry]
	)
	var report := BalanceBotReport.new(candidate, 1)
	for index: int in range(BalanceBotStrategy.IDS.size()):
		var value := _case(BalanceBotStrategy.IDS[index], index + 1)
		value.won = index == 0
		report.append(value)
	var parsed := JSON.parse_string(report.to_json(false)) as Dictionary
	assert_eq((parsed["case_proofs"] as Array).size(), 3)
	var first := (parsed["case_proofs"] as Array)[0] as Dictionary
	assert_eq(first["final_phase"], "RESULTS")
	assert_eq(int(first["settlement_receipt_count"]), 1)
	assert_eq(int(first["reward_receipt_count"]), 1)
	var proof := parsed["regression_proof"] as Dictionary
	assert_false(proof["all_strategies_perfect_win_rate"])
	assert_eq(int(proof["fallback_build_count"]), 0)
	assert_eq(proof["unique_ending_gold"], [1.0, 2.0, 3.0])
	assert_false(report.gate_reasons(false).has(&"BALANCE_ENDING_GOLD_CONSTANT"))


func test_report_regression_gate_rejects_old_artifact_pathologies() -> void:
	var candidate := BalanceCandidateDescriptor.new(
		&"", "test", "a".repeat(64), 1,
		[BalanceTuneEntry.new(&"economy.reroll_cost", "2")] as Array[BalanceTuneEntry]
	)
	var report := BalanceBotReport.new(candidate, 1)
	for strategy_id: StringName in BalanceBotStrategy.IDS:
		var value := _case(strategy_id, 20)
		value.won = true
		value.build_id = &"build.unit.fallback"
		report.append(value)
	var reasons := report.gate_reasons(false)
	assert_has(reasons, &"BALANCE_ALL_STRATEGIES_PERFECT_WIN_RATE")
	assert_has(reasons, &"BALANCE_BUILD_ID_ALL_FALLBACK")
	assert_has(reasons, &"BALANCE_ENDING_GOLD_CONSTANT")


func test_build_none_is_visible_but_excluded_from_build_dominance_gate() -> void:
	var candidate := BalanceCandidateDescriptor.new(
		&"", "test", "a".repeat(64), 1,
		[BalanceTuneEntry.new(&"economy.reroll_cost", "2")] as Array[BalanceTuneEntry]
	)
	var report := BalanceBotReport.new(candidate, 60)
	for seed_index: int in range(60):
		for strategy_id: StringName in BalanceBotStrategy.IDS:
			var value := _case(strategy_id, seed_index % 7)
			value.seed_index = seed_index
			value.build_id = &"build.none" if seed_index < 50 else (
				&"build.trait.trait.faction_arcane" if seed_index % 2 == 0
				else &"build.trait.trait.faction_verdant"
			)
			report.append(value)
	assert_false(
		report.gate_reasons(false).has(&"BALANCE_BUILD_SELECTION_DOMINANCE"),
		"build.none 不是已啟動構築，不得參與 dominance 排名"
	)


func _case(strategy_id: StringName, ending_gold: int) -> BalanceBotCaseResult:
	var value := BalanceBotCaseResult.new()
	value.strategy_id = strategy_id
	value.seed_index = 0
	value.run_id = &"shared_run"
	value.world_digest = "b".repeat(64)
	value.terminal = true
	value.act_reached = 3
	value.build_id = &"build.trait.test"
	value.ending_gold = ending_gold
	value.final_phase = &"RESULTS"
	value.settlement_receipt_digests = ["settlement"]
	value.reward_receipt_digests = ["reward"]
	value.replay_digest = "digest-%s" % String(strategy_id)
	return value
