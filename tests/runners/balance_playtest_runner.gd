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
	var strategy_ids: Array[StringName] = _strategy_ids()
	for strategy_id: StringName in strategy_ids:
		for case_offset: int in range(seed_count):
			var seed_index := seed_start + case_offset * seed_stride
			var case_started := Time.get_ticks_msec()
			var value: BalanceBotCaseResult = driver.run_case(strategy_id, seed_index)
			var primary_elapsed_ms := Time.get_ticks_msec() - case_started
			report.append(value)
			report.record_primary_elapsed_ms(primary_elapsed_ms)
			print("BALANCE_CASE strategy=%s seed=%d elapsed_ms=%d terminal=%s failures=%s" % [
				String(strategy_id), seed_index,
				primary_elapsed_ms, str(value.terminal),
				str(value.failure_codes),
			])
			if BalanceBotReport.replay_selected(seed_index):
				var replay_started := Time.get_ticks_msec()
				var replay: BalanceBotCaseResult = driver.run_case(strategy_id, seed_index)
				var replay_matches := replay.replay_digest == value.replay_digest
				report.record_replay_sample(
					strategy_id, seed_index,
					Time.get_ticks_msec() - replay_started, replay_matches
				)
				if not replay_matches:
					value.failure_codes.append(&"BALANCE_REPLAY_DRIFT")
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
