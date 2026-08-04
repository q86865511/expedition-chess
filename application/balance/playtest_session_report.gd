class_name PlaytestSessionReport
extends RefCounted

const SCHEMA_VERSION: int = 2
const OUTCOMES: Array[StringName] = [&"victory", &"failed", &"abandoned"]
const ROUTE_PREFIXES: Array[String] = ["node_", "route."]
const BUILD_PREFIXES: Array[String] = [
	"build.", "commander.", "unit.", "trait.", "relic.", "equipment.",
]
const MAX_STABLE_VALUE_LENGTH: int = 128

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
		and _all_allowlisted(build_summary, BUILD_PREFIXES)


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
	for code: int in value.to_ascii_buffer():
		var allowed := (code >= 97 and code <= 122) or (code >= 48 and code <= 57) \
			or code == 95 or code == 46
		if not allowed:
			return false
	return true
