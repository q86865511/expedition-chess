class_name PlaytestSessionReportCodecV1
extends RefCounted

const ALLOWED_KEYS: Array[String] = [
	"schema_version", "session_id", "candidate_id", "build_version", "content_version", "tune_digest",
	"started_at_utc", "duration_seconds", "route_ids", "build_summary", "outcome",
	"error_codes",
]


func encode(report: PlaytestSessionReport) -> String:
	if report == null or not report.is_valid():
		return ""
	return JSON.stringify({
		"schema_version": PlaytestSessionReport.SCHEMA_VERSION,
		"session_id": report.session_id,
		"candidate_id": String(report.candidate_id),
		"build_version": report.build_version,
		"content_version": report.content_version,
		"tune_digest": report.tune_digest,
		"started_at_utc": report.started_at_utc,
		"duration_seconds": report.duration_seconds,
		"route_ids": _names(report.route_ids),
		"build_summary": _names(report.build_summary),
		"outcome": String(report.outcome),
		"error_codes": _names(report.error_codes),
	})


func try_decode(text: String) -> PlaytestSessionReport:
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		return null
	var source := parsed as Dictionary
	if int(source.get("schema_version", 0)) != PlaytestSessionReport.SCHEMA_VERSION:
		return null
	for key: Variant in source.keys():
		if not ALLOWED_KEYS.has(str(key)):
			return null
	if not source.get("route_ids", null) is Array \
		or not source.get("build_summary", null) is Array \
		or not source.get("error_codes", null) is Array:
		return null
	if not _all_strings(source["route_ids"]) \
		or not _all_strings(source["build_summary"]) \
		or not _all_strings(source["error_codes"]):
		return null
	var report := PlaytestSessionReport.new()
	report.session_id = str(source.get("session_id", ""))
	report.candidate_id = StringName(str(source.get("candidate_id", "")))
	report.build_version = str(source.get("build_version", ""))
	report.content_version = str(source.get("content_version", ""))
	report.tune_digest = str(source.get("tune_digest", ""))
	report.started_at_utc = str(source.get("started_at_utc", ""))
	report.duration_seconds = int(source.get("duration_seconds", -1))
	report.route_ids = _decode_names(source["route_ids"])
	report.build_summary = _decode_names(source["build_summary"])
	report.outcome = StringName(str(source.get("outcome", "")))
	report.error_codes = _decode_names(source["error_codes"])
	return report if report.is_valid() else null


static func _names(values: Array[StringName]) -> Array[String]:
	var result: Array[String] = []
	for value: StringName in values:
		result.append(String(value))
	return result


func _decode_names(values: Array) -> Array[StringName]:
	var result: Array[StringName] = []
	for value: Variant in values:
		if not value is String:
			return [] as Array[StringName]
		result.append(StringName(value))
	return result


static func _all_strings(values: Array) -> bool:
	for value: Variant in values:
		if not value is String:
			return false
	return true
