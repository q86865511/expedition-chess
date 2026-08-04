extends GutTest

## B-02：`PlaytestSessionReportPending` 是 sidecar 的寫入/刪除/補發判定邏輯，抽成可測
## 純函式（try_parse／build_abandoned_report）＋檔案級生命週期（write／load／clear）。


func test_try_parse_round_trips_a_well_formed_sidecar() -> void:
	var text := PlaytestSessionReportPending.to_json(
		"0123456789abcdef0123456789abcdef", "balance.test.1", "0.3.0-rc1", "test",
		"c".repeat(64), "2026-08-04T09:37:00Z", 1754300000
	)
	assert_false(text.is_empty())
	var parsed := PlaytestSessionReportPending.try_parse(text)
	assert_eq(parsed.get("session_id"), "0123456789abcdef0123456789abcdef")
	assert_eq(parsed.get("candidate_id"), "balance.test.1")
	assert_eq(parsed.get("tune_digest"), "c".repeat(64))
	assert_eq(parsed.get("start_unix"), 1754300000)


func test_try_parse_rejects_missing_key_or_wrong_type() -> void:
	# 用「語法合法但非 Dictionary」的 JSON（而非真的語法錯誤）避免觸發 Godot 引擎層級的
	# parse-error log——GUT 預設把引擎錯誤視為測試失敗，這裡要驗證的是 fail-closed 的
	# 回傳值，不是 JSON.parse_string 本身會不會印錯誤。
	assert_eq(PlaytestSessionReportPending.try_parse("[]"), {})
	assert_eq(PlaytestSessionReportPending.try_parse(JSON.stringify({"session_id": "a"})), {})
	var partial := {
		"session_id": "0123456789abcdef0123456789abcdef",
		"candidate_id": "balance.test.1",
		"build_version": "0.3.0-rc1",
		"content_version": "test",
		"tune_digest": "c".repeat(64),
		"started_at_utc": "2026-08-04T09:37:00Z",
		"start_unix": "not-a-number",
	}
	assert_eq(
		PlaytestSessionReportPending.try_parse(JSON.stringify(partial)), {},
		"wrong-typed start_unix must fail-closed, not coerce"
	)


func test_to_json_refuses_incomplete_fields() -> void:
	assert_true(
		PlaytestSessionReportPending.to_json(
			"", "balance.test.1", "0.3.0", "test", "c".repeat(64),
			"2026-08-04T09:00:00Z", 1
		).is_empty(),
		"empty session_id must not encode"
	)


func test_build_abandoned_report_derives_hour_bucket_and_duration() -> void:
	var pending := {
		"session_id": "0123456789abcdef0123456789abcdef",
		"candidate_id": "balance.g2.7d47fada8091",
		"build_version": "0.3.0-rc1",
		"content_version": "test",
		"tune_digest": "d".repeat(64),
		"started_at_utc": "2026-08-04T09:37:12Z",
		"start_unix": 1754300000,
	}
	var report := PlaytestSessionReportPending.build_abandoned_report(
		pending, 1754300000 + 90
	)
	assert_not_null(report)
	if report == null:
		return
	assert_eq(report.session_id, "0123456789abcdef0123456789abcdef")
	assert_eq(String(report.outcome), "abandoned")
	assert_eq(report.error_codes, [&"EXPEDITION_ABANDONED"] as Array[StringName])
	assert_eq(report.started_at_utc, "2026-08-04T09:00:00Z")
	assert_eq(report.duration_seconds, 90)
	assert_true(report.route_ids.is_empty())
	assert_true(report.build_summary.is_empty())
	assert_true(report.is_valid())


func test_build_abandoned_report_fails_closed_on_empty_or_malformed_pending() -> void:
	assert_null(PlaytestSessionReportPending.build_abandoned_report({}, 100))
	var bad_digest := {
		"session_id": "0123456789abcdef0123456789abcdef",
		"candidate_id": "balance.g2.7d47fada8091",
		"build_version": "0.3.0-rc1",
		"content_version": "test",
		"tune_digest": "not-hex",
		"started_at_utc": "2026-08-04T09:37:12Z",
		"start_unix": 1754300000,
	}
	assert_null(
		PlaytestSessionReportPending.build_abandoned_report(bad_digest, 1754300100),
		"a malformed sidecar must not produce a report is_valid() would reject"
	)


func test_write_load_clear_file_lifecycle() -> void:
	PlaytestSessionReportPending.clear()
	assert_false(PlaytestSessionReportPending.exists())
	var write_result := PlaytestSessionReportPending.write(
		"fedcba9876543210fedcba9876543210", "balance.g2.7d47fada8091", "0.3.0-rc1",
		"test", "e".repeat(64), "2026-08-04T09:00:00Z", 1754300000
	)
	assert_eq(write_result, &"")
	assert_true(PlaytestSessionReportPending.exists())
	var loaded := PlaytestSessionReportPending.load()
	assert_eq(loaded.get("session_id"), "fedcba9876543210fedcba9876543210")
	PlaytestSessionReportPending.clear()
	assert_false(PlaytestSessionReportPending.exists())
	assert_eq(PlaytestSessionReportPending.load(), {})
