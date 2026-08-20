extends GutTest

## 逐案 checkpoint 帳本（分片 screening 的暫停／續跑基礎）：
## (a) 跳過清單解析必須去重、排序、忽略空行與註解、丟棄格式不合的行——同一份輸入
##     永遠得到同一份輸出，續跑才不會因清單順序不同而跑到不同的 case 集合；
## (b) `should_skip()` 只認 `strategy:seed` 這個鍵格式，與 PowerShell 端
##     （tools/balance/screening-checkpoint.ps1）產生清單時使用的格式逐字相同；
## (c) `append_line()` 是逐案 append 且可跨「行程重開」續寫，一個 case 一行 JSONL；
## (d) `BalanceBotReport.checkpoint_line()` 寫出的行必須能還原出與 `to_json()` 的
##     case_proofs 元素逐欄位相同的內容——合併端只靠 checkpoint 就能重算全部統計。

const Ledger := preload("res://tests/runners/balance_checkpoint_ledger.gd")
const ROOT := "user://test_balance_checkpoint"


func before_each() -> void:
	_remove_root()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ROOT))


func after_each() -> void:
	_remove_root()


func test_case_key_matches_the_powershell_side_format() -> void:
	assert_eq(Ledger.case_key(&"tempo", 0), "tempo:0")
	assert_eq(Ledger.case_key(&"economy", 1234), "economy:1234")


func test_parse_skip_list_dedupes_sorts_and_drops_malformed_lines() -> void:
	var parsed := Ledger.parse_skip_list(
		"synergy:16\n" +
		"tempo:0\n" +
		"  economy:8  \n" +
		"tempo:0\n" +
		"\n" +
		"# 註解行\n" +
		"tempo:-1\n" +
		"tempo:00\n" +
		"tempo\n" +
		"tempo:1:2\n"
	)
	assert_eq(
		Array(parsed), ["economy:8", "synergy:16", "tempo:0"],
		"必須去重、排序，且丟棄負數／前導零／缺欄位／多欄位的行"
	)


func test_parse_skip_list_of_empty_text_is_empty() -> void:
	assert_eq(Array(Ledger.parse_skip_list("")), [])
	assert_eq(Array(Ledger.parse_skip_list("   \n\n# only comments\n")), [])


func test_should_skip_reads_the_skip_list_file() -> void:
	var skip_path := _path("shard-00.skip")
	_write(skip_path, "tempo:0\nsynergy:32\n")
	var ledger := Ledger.new(_path("shard-00.jsonl"), skip_path, _path("pause.flag"))
	assert_eq(ledger.skip_count(), 2)
	assert_true(ledger.should_skip(&"tempo", 0))
	assert_true(ledger.should_skip(&"synergy", 32))
	assert_false(ledger.should_skip(&"tempo", 32), "策略不同就不是同一個 case")
	assert_false(ledger.should_skip(&"economy", 0), "沒列進清單的 case 一定要跑")


func test_missing_skip_list_skips_nothing() -> void:
	var ledger := Ledger.new(_path("shard-00.jsonl"), _path("absent.skip"), "")
	assert_eq(ledger.skip_count(), 0)
	assert_false(ledger.should_skip(&"tempo", 0))


func test_pause_flag_is_polled_from_disk_not_cached() -> void:
	var flag_path := _path("pause.flag")
	var ledger := Ledger.new(_path("shard-00.jsonl"), "", flag_path)
	assert_false(ledger.pause_requested(), "旗標不存在時不得暫停")
	_write(flag_path, "paused")
	assert_true(ledger.pause_requested(), "旗標必須每次現查，才能在 case 邊界生效")
	DirAccess.remove_absolute(flag_path)
	assert_false(ledger.pause_requested())


func test_append_line_survives_a_reopened_ledger() -> void:
	var checkpoint_path := _path("shard-01.jsonl")
	var first := Ledger.new(checkpoint_path, "", "")
	assert_eq(first.append_line("{\"seed_index\":0}"), OK)
	assert_eq(first.append_line("{\"seed_index\":1}"), OK)
	# 模擬行程被殺後重開：新帳本必須接在既有內容後面，不得覆寫。
	var second := Ledger.new(checkpoint_path, "", "")
	assert_eq(second.append_line("{\"seed_index\":2}"), OK)
	var lines := FileAccess.get_file_as_string(checkpoint_path).strip_edges().split("\n")
	assert_eq(lines.size(), 3, "一個 case 一行")
	assert_eq(lines[0], "{\"seed_index\":0}")
	assert_eq(lines[2], "{\"seed_index\":2}")


func test_status_path_is_derived_from_the_checkpoint_path() -> void:
	assert_eq(
		Ledger.status_path_for("C:/x/shard-03.jsonl"), "C:/x/shard-03.status.json"
	)
	assert_eq(Ledger.status_path_for(""), "")


func test_write_status_publishes_the_shard_tail_record() -> void:
	var checkpoint_path := _path("shard-02.jsonl")
	var ledger := Ledger.new(checkpoint_path, "", "")
	var report := _report()
	assert_eq(
		ledger.write_status(report.checkpoint_status_line(
			Ledger.STATUS_PAUSED, 2, 5, 7
		)),
		OK
	)
	var parsed := JSON.parse_string(
		FileAccess.get_file_as_string(Ledger.status_path_for(checkpoint_path))
	) as Dictionary
	assert_eq(String(parsed["status"]), "paused", "暫停的分片不得被讀成已完成")
	assert_eq(int(parsed["shard_index"]), 2)
	assert_eq(int(parsed["completed_cases"]), 5)
	assert_eq(int(parsed["skipped_cases"]), 7)
	assert_eq(
		String(parsed["tune_digest"]), report.candidate.tune_digest,
		"尾記錄必須帶 candidate 身分，合併端才能逐片比對"
	)
	assert_eq(String(parsed["candidate_id"]), String(report.candidate.candidate_id))


func test_checkpoint_line_round_trips_the_case_proof() -> void:
	var report := _report()
	var value := _case(&"tempo", 20)
	report.append(value)
	var line := report.checkpoint_line(value, 4, 1234, true, 567, true)
	assert_false(line.contains("\n"), "一個 case 必須是單獨一行，不能含換行")
	var record := JSON.parse_string(line) as Dictionary
	assert_eq(int(record["shard_index"]), 4)
	assert_eq(String(record["strategy_id"]), "tempo")
	assert_eq(int(record["seed_index"]), 20)
	assert_eq(int(record["primary_elapsed_ms"]), 1234)
	assert_true(bool(record["replay_sampled"]))
	assert_eq(int(record["replay_elapsed_ms"]), 567)
	assert_true(bool(record["replay_matched"]))
	var published := JSON.parse_string(report.to_json(false)) as Dictionary
	var expected := (published["case_proofs"] as Array)[0] as Dictionary
	assert_eq(
		record["case"], expected,
		"checkpoint 的 case 欄位必須與 to_json() 的 case_proofs 元素逐欄位相同"
	)


func _report() -> BalanceBotReport:
	var candidate := BalanceCandidateDescriptor.new(
		&"", "test", "a".repeat(64), 1,
		[BalanceTuneEntry.new(&"economy.reroll_cost", "2")] as Array[BalanceTuneEntry]
	)
	return BalanceBotReport.new(candidate, 1)


func _case(strategy_id: StringName, seed_index: int) -> BalanceBotCaseResult:
	var value := BalanceBotCaseResult.new()
	value.strategy_id = strategy_id
	value.seed_index = seed_index
	value.run_id = &"ledger_run"
	value.world_digest = "b".repeat(64)
	value.terminal = true
	value.won = true
	value.act_reached = 3
	value.build_id = &"build.trait.ledger"
	value.selected_ids = [&"unit.alpha"] as Array[StringName]
	value.route_ids = [&"node.a"] as Array[StringName]
	value.ending_gold = 7
	value.ending_hp = 11
	value.battle_wins = 2
	value.battle_losses = 1
	value.completed_node_count = 1
	value.final_phase = &"RESULTS"
	value.settlement_receipt_digests = ["settlement"]
	value.reward_receipt_digests = ["reward"]
	value.replay_digest = "replay-digest"
	value.act_snapshots = [
		BalanceBotActSnapshot.new(1, 7, 11, 1, 1, [&"unit.alpha"] as Array[StringName], 2, 1, &"")
	] as Array[BalanceBotActSnapshot]
	return value


func _path(file_name: String) -> String:
	return ProjectSettings.globalize_path(ROOT).path_join(file_name)


func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _remove_root() -> void:
	var absolute := ProjectSettings.globalize_path(ROOT)
	if not DirAccess.dir_exists_absolute(absolute):
		return
	for file_name: String in DirAccess.get_files_at(absolute):
		DirAccess.remove_absolute(absolute.path_join(file_name))
	DirAccess.remove_absolute(absolute)
