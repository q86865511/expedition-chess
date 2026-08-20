extends SceneTree

const Support = preload("res://tests/runners/runner_support.gd")
const ProductionCaseDriver = preload(
	"res://application/balance/balance_production_case_driver.gd"
)
const DEFAULT_ARTIFACT_PATH: String = "res://artifacts/test/balance-playtest.json"

var _started_at_utc: String


func _init() -> void:
	_started_at_utc = Support.utc_now()
	call_deferred("_run")


func _run() -> void:
	var seed_count := _seed_count()
	var seed_start := _integer_argument("--seed-start", 0)
	var seed_stride := _integer_argument("--seed-stride", 1)
	if seed_count < 1 or seed_stride < 1:
		_finish(null, 3, ["invalid --seed-count"])
		return
	var registry := ContentRegistryService.new()
	root.add_child(registry)
	var content := ProjectContentBootstrap.new().run(registry)
	if not content.ok:
		_finish(null, 3, ["production bootstrap: %s: %s" % [
			String(content.error_code), content.error_message,
		]])
		return
	var candidate := BalanceTuneInventory.production_candidate(
		content.manifest_digest, content.content_version
	)
	if not candidate.is_valid():
		_finish(null, 3, ["balance candidate invalid"])
		return
	var archive_error := BalanceTuneInventory.archive_candidate(candidate)
	if not archive_error.is_empty():
		_finish(null, 3, ["balance candidate archive: %s" % String(archive_error)])
		return
	if OS.get_cmdline_user_args().has("--archive-only"):
		_finish(BalanceBotReport.new(candidate, 0), 0, [] as Array[String])
		return
	var report := BalanceBotReport.new(candidate, seed_count)
	var driver: RefCounted = ProductionCaseDriver.new(
		content, func() -> SaveStoragePort: return FakeSaveStorage.new()
	)
	driver.trace_enabled = OS.get_cmdline_user_args().has("--trace")
	driver.diagnostic_node_limit = _integer_argument("--diagnostic-node-limit", 0)
	var ledger := _checkpoint_ledger()
	var shard_index := _integer_argument("--shard-index", seed_start)
	var completed_cases := 0
	var skipped_cases := 0
	var paused := false
	var strategy_ids: Array[StringName] = _strategy_ids()
	for strategy_id: StringName in strategy_ids:
		if paused:
			break
		for case_offset: int in range(seed_count):
			var seed_index := seed_start + case_offset * seed_stride
			# 跳過清單只決定「哪些 case 要跑」；每個 case 都由 seed_index 重建，
			# 跳過不會改變後續 case 的 RNG（決定性不依賴行程連續性）。
			if ledger != null and ledger.should_skip(strategy_id, seed_index):
				skipped_cases += 1
				continue
			# 暫停在 case 邊界檢查：已開始的 case 一定跑完並落帳，不留半筆。
			if ledger != null and ledger.pause_requested():
				paused = true
				break
			var case_started := Time.get_ticks_msec()
			var value: BalanceBotCaseResult = driver.run_case(strategy_id, seed_index)
			var primary_elapsed_ms := Time.get_ticks_msec() - case_started
			# An invalid case is dropped by report.append() rather than counted
			# into cases, so its elapsed time must not be counted either
			# (previously polluted primary_case_count / mean elapsed_ms; F10).
			var case_valid := value != null and value.is_valid()
			if case_valid:
				report.record_primary_elapsed_ms(primary_elapsed_ms)
			print("BALANCE_CASE strategy=%s seed=%d elapsed_ms=%d terminal=%s failures=%s" % [
				String(strategy_id), seed_index,
				primary_elapsed_ms, str(value.terminal),
				str(value.failure_codes),
			])
			var replay_sampled := BalanceBotReport.replay_selected(seed_index)
			var replay_elapsed_ms := 0
			var replay_matches := false
			if replay_sampled:
				var replay_started := Time.get_ticks_msec()
				var replay: BalanceBotCaseResult = driver.run_case(strategy_id, seed_index)
				replay_matches = replay.replay_digest == value.replay_digest
				replay_elapsed_ms = Time.get_ticks_msec() - replay_started
				report.record_replay_sample(
					strategy_id, seed_index, replay_elapsed_ms, replay_matches
				)
				if not replay_matches:
					value.failure_codes.append(&"BALANCE_REPLAY_DRIFT")
			# report.append() runs last so a drift code appended above is already
			# on value.failure_codes before the case is committed into report.cases
			# / case_proofs (fixes the ordering flagged by F10).
			report.append(value)
			if ledger != null and case_valid:
				var append_error := ledger.append_line(report.checkpoint_line(
					value, shard_index, primary_elapsed_ms,
					replay_sampled, replay_elapsed_ms, replay_matches
				))
				if append_error != OK:
					_finish(null, 3, [
						"checkpoint append failed with error %d" % append_error,
					])
					return
			completed_cases += 1
	if ledger != null:
		var status := BalanceCheckpointLedger.STATUS_PAUSED if paused \
			else BalanceCheckpointLedger.STATUS_COMPLETED
		var status_error := ledger.write_status(report.checkpoint_status_line(
			status, shard_index, completed_cases, skipped_cases
		))
		if status_error != OK:
			_finish(null, 3, ["checkpoint status write failed with error %d" % status_error])
			return
		print("BALANCE_SHARD_STATUS shard=%d status=%s completed=%d skipped=%d" % [
			shard_index, status, completed_cases, skipped_cases,
		])
	_finish(report, _report_exit_code(report), [] as Array[String])


func _strategy_ids() -> Array[StringName]:
	var arguments := OS.get_cmdline_user_args()
	for index: int in range(arguments.size() - 1):
		if arguments[index] == "--strategy-id":
			var requested := StringName(arguments[index + 1])
			var selected: Array[StringName] = []
			if BalanceBotStrategy.IDS.has(requested):
				selected.append(requested)
			return selected
	var all_ids: Array[StringName] = []
	all_ids.assign(BalanceBotStrategy.IDS)
	return all_ids


func _seed_count() -> int:
	return _integer_argument("--seed-count", 1000)


func _integer_argument(name: String, fallback: int) -> int:
	var arguments := OS.get_cmdline_user_args()
	for index: int in range(arguments.size() - 1):
		if arguments[index] == name:
			return int(arguments[index + 1])
	return fallback


## `--checkpoint-path` 存在時才啟用逐案 checkpoint（未傳＝維持舊行為，
## run-final-cohort / run-calibration 等既有呼叫端不受影響）。
func _checkpoint_ledger() -> BalanceCheckpointLedger:
	var checkpoint_path := _resource_argument("--checkpoint-path")
	if checkpoint_path.is_empty():
		return null
	return BalanceCheckpointLedger.new(
		checkpoint_path,
		_resource_argument("--skip-list-path"),
		_resource_argument("--pause-flag-path")
	)


## 只接受 res://artifacts/test/ 底下的路徑（與 `--artifact-path` 同一條界線），
## 回傳 globalize 後的絕對路徑；未傳或越界時回空字串。
func _resource_argument(name: String) -> String:
	var arguments := OS.get_cmdline_user_args()
	for index: int in range(arguments.size() - 1):
		if arguments[index] == name:
			var candidate := arguments[index + 1]
			if candidate.begins_with("res://artifacts/test/"):
				return ProjectSettings.globalize_path(candidate)
			return ""
	return ""


func _artifact_path() -> String:
	var arguments := OS.get_cmdline_user_args()
	for index: int in range(arguments.size() - 1):
		if arguments[index] == "--artifact-path":
			var candidate := arguments[index + 1]
			if candidate.begins_with("res://artifacts/test/") \
				and candidate.ends_with(".json"):
				return candidate
	return DEFAULT_ARTIFACT_PATH


func _final_gate() -> bool:
	return OS.get_cmdline_user_args().has("--final")


func _screening_gate() -> bool:
	return OS.get_cmdline_user_args().has("--screening")


func _report_exit_code(report: BalanceBotReport) -> int:
	if not OS.get_cmdline_user_args().has("--shard"):
		return 0 if report.passed(_final_gate(), _screening_gate()) else 2
	if not report.failures.is_empty():
		return 2
	for value: BalanceBotCaseResult in report.cases:
		if not value.terminal or not value.failure_codes.is_empty():
			return 2
	return 0


func _finish(
	report: BalanceBotReport,
	exit_code: int,
	infrastructure_failures: Array[String]
) -> void:
	var payload: Dictionary
	if report != null:
		var parsed: Variant = JSON.parse_string(report.to_json(
			_final_gate(), _screening_gate()
		))
		payload = parsed if parsed is Dictionary else {}
	else:
		payload = Support.base_report(
			"balance-playtest", _started_at_utc, [] as Array[String],
			[] as Array[String]
		)
		payload["failures"] = infrastructure_failures
		payload["gate"] = "INFRASTRUCTURE"
	if payload.is_empty():
		quit(3)
		return
	payload["started_at_utc"] = _started_at_utc
	payload["finished_at_utc"] = Support.utc_now()
	var written := Support.write_json_artifact(_artifact_path(), payload)
	quit(3 if written != OK else exit_code)
