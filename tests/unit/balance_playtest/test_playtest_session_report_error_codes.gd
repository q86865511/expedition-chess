extends GutTest

## B-07：`playtest_session_report.gd` 的 `is_valid()` 先前只對 route_ids／build_summary
## 做 allowlist，error_codes 完全未驗證。本檔鎖定新增的 fail-closed 驗證：字元集
## `[A-Z0-9_]`、單碼長度 ≤64、陣列長度 ≤32，違反者整份報告視為不合法。


func test_uppercase_underscore_error_codes_are_accepted() -> void:
	var report := _report()
	report.error_codes = [&"EXPEDITION_FAILED", &"BALANCE_CANDIDATE_INVALID"]
	assert_true(report.is_valid())


func test_lowercase_or_symbol_error_code_is_rejected() -> void:
	var lower := _report()
	lower.error_codes = [&"expedition_failed"]
	assert_false(lower.is_valid(), "lowercase must not pass the allowlist")

	var path_like := _report()
	path_like.error_codes = [&"/etc/passwd"]
	assert_false(path_like.is_valid(), "path-like values must fail-closed")

	var with_space := _report()
	with_space.error_codes = [&"USER NAME"]
	assert_false(with_space.is_valid(), "spaces are outside the allowed character set")


func test_error_code_length_and_count_are_bounded() -> void:
	var too_long := _report()
	too_long.error_codes = [StringName("A".repeat(65))]
	assert_false(too_long.is_valid(), "single code beyond 64 chars must fail-closed")

	var at_limit := _report()
	at_limit.error_codes = [StringName("A".repeat(64))]
	assert_true(at_limit.is_valid(), "exactly 64 chars is still allowed")

	var too_many: Array[StringName] = []
	for index: int in range(33):
		too_many.append(StringName("CODE_%d" % index))
	var over_count := _report()
	over_count.error_codes = too_many
	assert_false(over_count.is_valid(), "more than 32 error codes must fail-closed")


## F07：鎖定所有字串欄位對非 ASCII 的 fail-closed 拒收。
## 註：實測 Godot 4.7 的 to_ascii_buffer() 將非 ASCII 映為 0x20（原實作亦會拒收），
## 審查假說的低位摺疊（U+015F→0x5F）未重現；本測試鎖定的是「非 ASCII 必拒」
## 這一行為契約本身，與實作用哪種走法無關。
func test_non_ascii_folding_is_rejected_in_all_string_fields() -> void:
	var folded_error := _report()
	folded_error.error_codes = [StringName("EXPEDITI%sN_FAILED" % char(0x00D6))]
	assert_false(folded_error.is_valid(), "non-ASCII in error_codes must fail-closed")

	var folded_route := _report()
	folded_route.route_ids = [StringName("route.a%s" % char(0x015F))]
	assert_false(
		folded_route.is_valid(),
		"non-ASCII in route_ids must fail-closed regardless of encoding walk"
	)

	var folded_build := _report()
	folded_build.build_summary = [StringName("trait.arcane%s" % char(0x016E))]
	assert_false(folded_build.is_valid(), "non-ASCII in build_summary must fail-closed")


func test_codec_round_trip_rejects_report_with_invalid_error_code() -> void:
	var codec := PlaytestSessionReportCodecV1.new()
	var report := _report()
	report.error_codes = [&"not-allowed"]
	assert_true(codec.encode(report).is_empty(), "encode must refuse an invalid report")

	var parsed: Dictionary = JSON.parse_string(codec.encode(_report()))
	parsed["error_codes"] = ["not-allowed"]
	assert_null(
		codec.try_decode(JSON.stringify(parsed)),
		"decode must fail-closed on a bad error code, not silently drop it"
	)


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
