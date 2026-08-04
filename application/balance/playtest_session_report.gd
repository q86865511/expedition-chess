class_name PlaytestSessionReport
extends RefCounted

const SCHEMA_VERSION: int = 2
const OUTCOMES: Array[StringName] = [&"victory", &"failed", &"abandoned"]
const ROUTE_PREFIXES: Array[String] = ["node_", "route."]
const BUILD_PREFIXES: Array[String] = [
	"build.", "commander.", "unit.", "trait.", "relic.", "equipment.",
]
const MAX_STABLE_VALUE_LENGTH: int = 128
const MAX_ERROR_CODE_LENGTH: int = 64
const MAX_ERROR_CODE_COUNT: int = 32

var session_id: String
var candidate_id: StringName
var build_version: String
var content_version: String
var tune_digest: String
var started_at_utc: String
var duration_seconds: int
var route_ids: Array[StringName] = []
var build_summary: Array[StringName] = []
var outcome: StringName
var error_codes: Array[StringName] = []


func deep_clone() -> PlaytestSessionReport:
	var clone := PlaytestSessionReport.new()
	clone.session_id = session_id
	clone.candidate_id = candidate_id
	clone.build_version = build_version
	clone.content_version = content_version
	clone.tune_digest = tune_digest
	clone.started_at_utc = started_at_utc
	clone.duration_seconds = duration_seconds
	clone.route_ids.assign(route_ids)
	clone.build_summary.assign(build_summary)
	clone.outcome = outcome
	clone.error_codes.assign(error_codes)
	return clone


func is_valid() -> bool:
	return session_id.length() == 32 and session_id.is_valid_hex_number(false) \
		and not candidate_id.is_empty() and not build_version.is_empty() \
		and not content_version.is_empty() \
		and tune_digest.length() == 64 and tune_digest.is_valid_hex_number(false) \
		and _is_hour_bucket_utc(started_at_utc) \
		and duration_seconds >= 0 and OUTCOMES.has(outcome) \
		and _all_allowlisted(route_ids, ROUTE_PREFIXES) \
		and _all_allowlisted(build_summary, BUILD_PREFIXES) \
		and _error_codes_valid(error_codes)


static func hour_bucket_utc(value: String) -> String:
	if value.length() < 13 or value.substr(4, 1) != "-" \
		or value.substr(7, 1) != "-" or value.substr(10, 1) != "T":
		return ""
	var prefix := value.left(13)
	for index: int in [0, 1, 2, 3, 5, 6, 8, 9, 11, 12]:
		var code := prefix.unicode_at(index)
		if code < 48 or code > 57:
			return ""
	var hour := int(prefix.substr(11, 2))
	return "%s:00:00Z" % prefix if hour >= 0 and hour <= 23 else ""


static func _is_hour_bucket_utc(value: String) -> bool:
	return value.length() == 20 and value.ends_with(":00:00Z") \
		and hour_bucket_utc(value) == value


static func _all_allowlisted(
	values: Array[StringName], prefixes: Array[String]
) -> bool:
	for value: StringName in values:
		if not _allowlisted_value(String(value), prefixes):
			return false
	return true


static func _allowlisted_value(value: String, prefixes: Array[String]) -> bool:
	if value.is_empty() or value.length() > MAX_STABLE_VALUE_LENGTH:
		return false
	var prefix_ok := false
	for prefix: String in prefixes:
		if value.begins_with(prefix):
			prefix_ok = true
			break
	if not prefix_ok:
		return false
	# F07：逐 codepoint 明確拒收非 ASCII。實測 Godot 4.7 的 to_ascii_buffer()
	# 將非 ASCII 映為 0x20（亦會被白名單拒收），但該替換行為未見文件保證；
	# 改用 unicode_at 使拒收不依賴未保證行為。
	for index: int in range(value.length()):
		var code := value.unicode_at(index)
		var allowed := (code >= 97 and code <= 122) or (code >= 48 and code <= 57) \
			or code == 95 or code == 46
		if not allowed:
			return false
	return true


## B-07：error_codes 先前未經任何驗證。fail-closed 收斂為封閉字元集
## `[A-Z0-9_]`（與既有具名錯誤碼慣例一致，如 `EXPEDITION_FAILED`），
## 逐碼長度與陣列長度皆設上限；違反者整份報告視為不合法（is_valid() 回 false）。
static func _error_codes_valid(values: Array[StringName]) -> bool:
	if values.size() > MAX_ERROR_CODE_COUNT:
		return false
	for value: StringName in values:
		if not _is_error_code(String(value)):
			return false
	return true


static func _is_error_code(value: String) -> bool:
	if value.is_empty() or value.length() > MAX_ERROR_CODE_LENGTH:
		return false
	# F07：同 _allowlisted_value——逐 codepoint 明確拒收非 ASCII，
	# 不依賴 to_ascii_buffer 的未保證替換行為。
	for index: int in range(value.length()):
		var code := value.unicode_at(index)
		var allowed := (code >= 65 and code <= 90) or (code >= 48 and code <= 57) \
			or code == 95
		if not allowed:
			return false
	return true
