extends GutTest


func test_session_report_round_trip_has_only_anonymous_allowlisted_fields() -> void:
	var report := _report()
	var codec := PlaytestSessionReportCodecV1.new()
	var text := codec.encode(report)
	assert_false(text.is_empty())
	assert_false(text.contains("user_name"))
	assert_false(text.contains("hardware"))
	assert_false(text.contains("ip_address"))
	var decoded := codec.try_decode(text)
	assert_not_null(decoded)
	assert_eq(decoded.session_id, report.session_id)
	assert_eq(decoded.outcome, &"victory")
	assert_true(decoded.error_codes.is_empty())


func test_session_report_rejects_future_schema_and_unknown_privacy_field() -> void:
	var codec := PlaytestSessionReportCodecV1.new()
	var parsed: Dictionary = JSON.parse_string(codec.encode(_report()))
	parsed["schema_version"] = 3
	assert_null(codec.try_decode(JSON.stringify(parsed)))
	parsed["schema_version"] = PlaytestSessionReport.SCHEMA_VERSION
	parsed["user_name"] = "forbidden"
	assert_null(codec.try_decode(JSON.stringify(parsed)))
	parsed.erase("user_name")
	parsed["schema_version"] = 1
	assert_null(codec.try_decode(JSON.stringify(parsed)), "v1 精確拒讀，不做隱式升級")


func test_session_report_rejects_non_string_route_values_and_non_hex_digest() -> void:
	var codec := PlaytestSessionReportCodecV1.new()
	var parsed: Dictionary = JSON.parse_string(codec.encode(_report()))
	parsed["route_ids"] = [123]
	assert_null(codec.try_decode(JSON.stringify(parsed)))
	parsed["route_ids"] = ["route.a"]
	parsed["tune_digest"] = "z".repeat(64)
	assert_null(codec.try_decode(JSON.stringify(parsed)))


func test_session_report_writer_publishes_readable_local_json() -> void:
	var report := _report()
	var path := "user://playtest_reports/session-%s.json" % report.session_id
	var absolute := ProjectSettings.globalize_path(path)
	DirAccess.remove_absolute(absolute)
	assert_eq(PlaytestSessionReportWriter.new().write(report), &"")
	assert_true(FileAccess.file_exists(path))
	var decoded := PlaytestSessionReportCodecV1.new().try_decode(
		FileAccess.get_file_as_string(path)
	)
	assert_not_null(decoded)
	assert_eq(decoded.build_version, "0.2.0")
	DirAccess.remove_absolute(absolute)


func test_session_report_rejects_path_like_or_unknown_prefix_values() -> void:
	var codec := PlaytestSessionReportCodecV1.new()
	for bad_route: String in [
		"node_/users/name", "node_\\users", "node_c:drive", "unknown.route",
		"node_" + "a".repeat(129),
	]:
		var parsed: Dictionary = JSON.parse_string(codec.encode(_report()))
		parsed["route_ids"] = [bad_route]
		assert_null(codec.try_decode(JSON.stringify(parsed)), bad_route)
	for bad_build: String in ["unit/path", "unit\\path", "unit:c", "account.name"]:
		var parsed: Dictionary = JSON.parse_string(codec.encode(_report()))
		parsed["build_summary"] = [bad_build]
		assert_null(codec.try_decode(JSON.stringify(parsed)), bad_build)


func test_session_report_requires_hour_bucket_and_three_terminal_outcomes() -> void:
	assert_eq(
		PlaytestSessionReport.hour_bucket_utc("2026-08-01T14:37:52Z"),
		"2026-08-01T14:00:00Z"
	)
	var codec := PlaytestSessionReportCodecV1.new()
	for outcome: StringName in [&"victory", &"failed", &"abandoned"]:
		var report := _report()
		report.outcome = outcome
		assert_not_null(codec.try_decode(codec.encode(report)), String(outcome))
	var bad_time := _report()
	bad_time.started_at_utc = "2026-08-01T14:37:52Z"
	assert_true(codec.encode(bad_time).is_empty())
	var old_outcome := _report()
	old_outcome.outcome = &"completed"
	assert_true(codec.encode(old_outcome).is_empty())


func _report() -> PlaytestSessionReport:
	var report := PlaytestSessionReport.new()
	report.session_id = "0123456789abcdef0123456789abcdef"
	report.candidate_id = &"balance.test.1"
	report.build_version = "0.2.0"
	report.content_version = "test"
	report.tune_digest = "c".repeat(64)
	report.started_at_utc = "2026-08-01T00:00:00Z"
	report.duration_seconds = 2700
	report.route_ids = [&"route.a"]
	report.build_summary = [&"trait.arcane"]
	report.outcome = &"victory"
	return report
