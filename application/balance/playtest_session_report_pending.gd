class_name PlaytestSessionReportPending
extends RefCounted

## B-02：session 開始時的 metadata 只存在行程記憶體，玩家關遊戲→重啟→在主選單棄置
## retained run 時（跨行程放棄）不會產生任何 abandoned 報告。本檔在
## `user://playtest_session/.pending-session.json` 維護一份 sidecar：session 開始時寫入、
## terminal 報告成功落檔後刪除；若下一次明示棄置發生時 sidecar 仍在（代表上次 session
## 從未走到 terminal），據 sidecar 補發一份 outcome=abandoned 報告。sidecar 純本機、不出境，
## 可存精確時間（不像最終報告需要小時桶降精度）。
## N-04：sidecar 不得放在 `user://playtest_reports/`——那是 PLAYTEST.md 要求測試者
## 整包回傳的目錄，精確時戳會繞過報告的小時桶降精度。

const PENDING_DIR: String = "user://playtest_session"
const PENDING_PATH: String = PENDING_DIR + "/.pending-session.json"
const REQUIRED_KEYS: Array[String] = [
	"session_id", "candidate_id", "build_version", "content_version",
	"tune_digest", "started_at_utc", "start_unix",
]


## 寫入 sidecar；候選欄位缺一即 fail-closed 不寫檔並回傳錯誤碼。
static func write(
	session_id: String,
	candidate_id: String,
	build_version: String,
	content_version: String,
	tune_digest: String,
	started_at_utc: String,
	start_unix: int
) -> StringName:
	var text := to_json(
		session_id, candidate_id, build_version, content_version, tune_digest,
		started_at_utc, start_unix
	)
	if text.is_empty():
		return &"PLAYTEST_PENDING_INVALID"
	var absolute_root := ProjectSettings.globalize_path(PENDING_DIR)
	if DirAccess.make_dir_recursive_absolute(absolute_root) != OK:
		return &"PLAYTEST_PENDING_DIRECTORY_FAILED"
	var file := FileAccess.open(PENDING_PATH, FileAccess.WRITE)
	if file == null:
		return &"PLAYTEST_PENDING_WRITE_FAILED"
	file.store_string(text)
	file.close()
	return &""


## 刪除 sidecar；不存在時視為成功（冪等）。
static func clear() -> void:
	if FileAccess.file_exists(PENDING_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PENDING_PATH))


static func exists() -> bool:
	return FileAccess.file_exists(PENDING_PATH)


## 讀取並解析 sidecar；不存在或格式不符一律回傳空字典（fail-closed）。
static func load() -> Dictionary:
	if not FileAccess.file_exists(PENDING_PATH):
		return {}
	return try_parse(FileAccess.get_file_as_string(PENDING_PATH))


## 純函式：JSON 文字 → 欄位字典。缺鍵、型別不符一律回傳空字典，不猜測殘缺欄位。
static func try_parse(text: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		return {}
	var source := parsed as Dictionary
	for key: String in REQUIRED_KEYS:
		if not source.has(key):
			return {}
	if not source["session_id"] is String or not source["candidate_id"] is String \
		or not source["build_version"] is String \
		or not source["content_version"] is String \
		or not source["tune_digest"] is String \
		or not source["started_at_utc"] is String \
		or not (source["start_unix"] is int or source["start_unix"] is float):
		return {}
	return {
		"session_id": source["session_id"],
		"candidate_id": source["candidate_id"],
		"build_version": source["build_version"],
		"content_version": source["content_version"],
		"tune_digest": source["tune_digest"],
		"started_at_utc": source["started_at_utc"],
		"start_unix": int(source["start_unix"]),
	}


static func to_json(
	session_id: String,
	candidate_id: String,
	build_version: String,
	content_version: String,
	tune_digest: String,
	started_at_utc: String,
	start_unix: int
) -> String:
	if session_id.is_empty() or candidate_id.is_empty() or tune_digest.is_empty() \
		or content_version.is_empty() or build_version.is_empty():
		return ""
	return JSON.stringify({
		"session_id": session_id,
		"candidate_id": candidate_id,
		"build_version": build_version,
		"content_version": content_version,
		"tune_digest": tune_digest,
		"started_at_utc": started_at_utc,
		"start_unix": start_unix,
	})


## 純函式（補發判定邏輯）：由 sidecar 欄位補建一份 outcome=abandoned 報告。route_ids／
## build_summary 在跨行程情境下已不可得，留空——PlaytestSessionReport.is_valid() 對空陣列
## 不設下限，不影響合法性。欄位不全或組出的報告本身不合法一律回傳 null，交由呼叫端
## fail-closed（不寫檔），不臆測殘缺資料。
static func build_abandoned_report(
	pending: Dictionary, now_unix: int
) -> PlaytestSessionReport:
	if pending.is_empty():
		return null
	var report := PlaytestSessionReport.new()
	report.session_id = str(pending.get("session_id", ""))
	report.candidate_id = StringName(str(pending.get("candidate_id", "")))
	report.build_version = str(pending.get("build_version", ""))
	report.content_version = str(pending.get("content_version", ""))
	report.tune_digest = str(pending.get("tune_digest", ""))
	report.started_at_utc = PlaytestSessionReport.hour_bucket_utc(
		str(pending.get("started_at_utc", ""))
	)
	report.duration_seconds = maxi(0, now_unix - int(pending.get("start_unix", 0)))
	report.outcome = &"abandoned"
	report.error_codes = [&"EXPEDITION_ABANDONED"] as Array[StringName]
	return report if report.is_valid() else null
