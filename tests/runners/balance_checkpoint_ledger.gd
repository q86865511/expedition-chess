class_name BalanceCheckpointLedger
extends RefCounted

## 分片 screening 的逐案 checkpoint 帳本。
## 分片每完成一個 case 就 append 一行 JSONL，讓中斷（當機、重開機、明示暫停）之後
## 能從最後一個已提交的 case 續跑，而不是整片重來。
## 續跑時由協調端（tools/balance/run-sharded-cohort.ps1）把「已完成的 (strategy, seed)」
## 寫成跳過清單交給本帳本；跳過只影響「哪些 case 要跑」，不影響任何 case 的 RNG
## ——每個 case 都由 seed_index 重建，與行程連續性無關。
## 路徑一律是呼叫端已 globalize 過的絕對路徑。

const STATUS_COMPLETED: String = "completed"
const STATUS_PAUSED: String = "paused"
const KEY_PATTERN: String = "^[A-Za-z_][A-Za-z0-9_]*:(0|[1-9][0-9]*)$"

var _checkpoint_path: String = ""
var _status_path: String = ""
var _pause_flag_path: String = ""
var _skip_keys: Dictionary = {}


func _init(
	checkpoint_path: String, skip_list_path: String, pause_flag_path: String
) -> void:
	_checkpoint_path = checkpoint_path
	_status_path = status_path_for(checkpoint_path)
	_pause_flag_path = pause_flag_path
	if not skip_list_path.is_empty() and FileAccess.file_exists(skip_list_path):
		for key: String in parse_skip_list(FileAccess.get_file_as_string(skip_list_path)):
			_skip_keys[key] = true


## 一個 case 在帳本中的鍵；PowerShell 端（screening-checkpoint.ps1）產生跳過清單時
## 必須逐字使用同一格式。
static func case_key(strategy_id: StringName, seed_index: int) -> String:
	return "%s:%d" % [String(strategy_id), seed_index]


## 跳過清單解析：一行一個 key，忽略空行、前後空白與 `#` 註解行；格式不合的行丟棄
## （丟棄的後果只會是那個 case 被重跑，合併端會以重複 case 明確擋下，不會靜默污染統計）。
## 回傳去重且排序後的清單，讓同一份輸入永遠得到同一份輸出。
static func parse_skip_list(text: String) -> PackedStringArray:
	var matcher := RegEx.new()
	matcher.compile(KEY_PATTERN)
	var seen: Dictionary = {}
	var keys: PackedStringArray = PackedStringArray()
	for raw_line: String in text.split("\n"):
		var line := raw_line.strip_edges()
		if line.is_empty() or line.begins_with("#"):
			continue
		if matcher.search(line) == null or seen.has(line):
			continue
		seen[line] = true
		keys.append(line)
	keys.sort()
	return keys


static func status_path_for(checkpoint_path: String) -> String:
	if checkpoint_path.is_empty():
		return ""
	return checkpoint_path.get_basename() + ".status.json"


func skip_count() -> int:
	return _skip_keys.size()


func should_skip(strategy_id: StringName, seed_index: int) -> bool:
	return _skip_keys.has(case_key(strategy_id, seed_index))


func pause_requested() -> bool:
	return not _pause_flag_path.is_empty() and FileAccess.file_exists(_pause_flag_path)


## 逐案 append。每次重新開檔＋flush，讓行程被強殺時最多只損失「當下未跑完的那個 case」。
func append_line(line: String) -> int:
	var directory_error := DirAccess.make_dir_recursive_absolute(
		_checkpoint_path.get_base_dir()
	)
	if directory_error != OK:
		return directory_error
	var file: FileAccess
	if FileAccess.file_exists(_checkpoint_path):
		file = FileAccess.open(_checkpoint_path, FileAccess.READ_WRITE)
	else:
		file = FileAccess.open(_checkpoint_path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.seek_end()
	file.store_line(line)
	file.flush()
	var write_error := file.get_error()
	file = null
	return write_error


## 尾記錄：分片是「跑完」還是「暫停」由本檔決定，合併端不得以行程退出碼推測。
func write_status(text: String) -> int:
	if _status_path.is_empty():
		return ERR_INVALID_PARAMETER
	var directory_error := DirAccess.make_dir_recursive_absolute(
		_status_path.get_base_dir()
	)
	if directory_error != OK:
		return directory_error
	var file := FileAccess.open(_status_path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(text)
	file.flush()
	var write_error := file.get_error()
	file = null
	return write_error
