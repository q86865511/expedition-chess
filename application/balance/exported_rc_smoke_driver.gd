class_name ExportedRcSmokeDriver
extends RefCounted

const CLI_FLAG: String = "--rc-smoke-phase"
const PHASE_START_SAVE: StringName = &"start-save"
const PHASE_RESTART_TERMINAL: StringName = &"restart-terminal"
const PHASE_RESTART_ABANDON_VERIFY: StringName = &"restart-abandon-verify"
const INVALID_PHASE: StringName = &"invalid"
const CHECKPOINT_PATH: String = "user://rc_smoke/checkpoint.json"
const RESULT_ROOT: String = "user://rc_smoke"
const PCK_INVENTORY_PATH: String = "user://rc_smoke/pck-inventory.json"
const REPORT_ROOT: String = "user://playtest_reports"
const RESULT_MARKER: String = "RC_SMOKE_RESULT="
const STEP_LIMIT: int = 32
const FORBIDDEN_RES_PREFIXES: Array[String] = [
	"addons/gut/", "tests/", "specs/", "tools/",
]


static func phase_from(arguments: PackedStringArray) -> StringName:
	for index: int in range(arguments.size()):
		var argument := arguments[index]
		if argument.begins_with(CLI_FLAG + "="):
			var value := argument.trim_prefix(CLI_FLAG + "=")
			return StringName(value) if not value.is_empty() else INVALID_PHASE
		if argument == CLI_FLAG:
			if index + 1 >= arguments.size() or arguments[index + 1].begins_with("--"):
				return INVALID_PHASE
			return StringName(arguments[index + 1])
	return &""


func run(root: ApplicationRoot, phase: StringName) -> void:
	var result: Dictionary
	if root == null or not OS.has_feature("provisional_rc"):
		result = _failure(&"RC_SMOKE_NOT_AUTHORIZED")
	else:
		match phase:
			PHASE_START_SAVE:
				result = _start_save(root)
			PHASE_RESTART_TERMINAL:
				result = _restart_terminal(root)
			PHASE_RESTART_ABANDON_VERIFY:
				result = _restart_abandon_verify(root)
			_:
				result = _failure(&"RC_SMOKE_PHASE_INVALID")
	_finish(root, phase, result)


func _start_save(root: ApplicationRoot) -> Dictionary:
	var inventory := _write_pck_inventory()
	if not bool(inventory.get("ok", false)):
		return _failure_with(
			StringName(inventory.get("error", "RC_SMOKE_PCK_INVENTORY_FAILED")),
			{
				"inventory_file_count": int(inventory.get("file_count", 0)),
				"inventory_passed": false,
				"inventory_path": PCK_INVENTORY_PATH,
			}
		)
	if not bool(inventory.get("passed", false)):
		return _failure_with(&"RC_SMOKE_PCK_FORBIDDEN_ENTRY", {
			"inventory_file_count": int(inventory.get("file_count", 0)),
			"inventory_passed": false,
			"inventory_path": PCK_INVENTORY_PATH,
		})
	var report_result := _read_reports()
	if not bool(report_result.get("ok", false)):
		return _failure(StringName(report_result.get("error", "RC_SMOKE_REPORT_READ_FAILED")))
	if not (report_result.get("reports", []) as Array).is_empty():
		return _failure(&"RC_SMOKE_PROFILE_NOT_FRESH")
	var opened := root.open_camp()
	if opened == null or not opened.ok:
		return _failure(_app_error(opened, &"RC_SMOKE_OPEN_CAMP_FAILED"))
	var helper := _helper(root)
	if helper == null:
		return _failure(&"RC_SMOKE_CONTENT_UNAVAILABLE")
	var commander_id := helper._commander_id()
	if commander_id.is_empty():
		return _failure(&"RC_SMOKE_COMMANDER_UNAVAILABLE")
	var started := root.start_expedition(StartExpeditionRequest.new(commander_id, 0))
	if started == null or not started.ok:
		return _failure(_app_error(started, &"RC_SMOKE_START_FAILED"))
	var session_result := root.current_run_presentation()
	if session_result == null or not session_result.ok or session_result.session == null:
		return _failure(&"RC_SMOKE_SESSION_UNAVAILABLE")
	var snapshot := session_result.session.snapshot()
	if snapshot == null or snapshot.run_id.is_empty():
		return _failure(&"RC_SMOKE_RUN_ID_MISSING")
	if not _loaded_run_matches(root._save_repository.load(), snapshot.run_id):
		return _failure(&"RC_SMOKE_DURABLE_READBACK_MISMATCH")
	var checkpoint := {
		"schema_version": 1,
		"first_run_id": String(snapshot.run_id),
		"second_run_id": "",
		"terminal_session_id": "",
		"terminal_outcome": "",
	}
	var checkpoint_error := _write_json(CHECKPOINT_PATH, checkpoint)
	if not checkpoint_error.is_empty():
		return _failure(checkpoint_error)
	return _success({
		"first_run_id": String(snapshot.run_id),
		"durable_readback": true,
		"inventory_file_count": int(inventory.get("file_count", 0)),
		"inventory_passed": true,
		"inventory_path": PCK_INVENTORY_PATH,
		"report_count": 0,
	})


func _restart_terminal(root: ApplicationRoot) -> Dictionary:
	var checkpoint_result := _read_checkpoint()
	if not bool(checkpoint_result.get("ok", false)):
		return _failure(StringName(checkpoint_result.get("error", "RC_SMOKE_CHECKPOINT_INVALID")))
	var checkpoint: Dictionary = checkpoint_result.get("checkpoint", {})
	var expected_run_id := StringName(str(checkpoint.get("first_run_id", "")))
	if expected_run_id.is_empty() or not _menu_run_matches(root, expected_run_id):
		return _failure(&"RC_SMOKE_RESTART_LOAD_MISMATCH")
	var continued := root.continue_active_run()
	if continued == null or not continued.ok:
		return _failure(_app_error(continued, &"RC_SMOKE_CONTINUE_FAILED"))
	var session_result := root.current_run_presentation()
	if session_result == null or not session_result.ok or session_result.session == null:
		return _failure(&"RC_SMOKE_SESSION_UNAVAILABLE")
	if session_result.session.snapshot().run_id != expected_run_id:
		return _failure(&"RC_SMOKE_CONTINUED_RUN_MISMATCH")
	var terminal_session_id := root._playtest_session_id
	var drive_error := _drive_to_terminal(root, session_result.session)
	if not drive_error.is_empty():
		return _failure(drive_error)
	var settled := root.settle_active_run()
	if settled == null or not settled.ok:
		return _failure(_app_error(settled, &"RC_SMOKE_SETTLEMENT_FAILED"))
	var report_result := _read_reports()
	if not bool(report_result.get("ok", false)):
		return _failure(StringName(report_result.get("error", "RC_SMOKE_REPORT_READ_FAILED")))
	var reports: Array = report_result.get("reports", [])
	if reports.size() != 1:
		return _failure(&"RC_SMOKE_TERMINAL_REPORT_COUNT_INVALID")
	var terminal_report := reports[0] as PlaytestSessionReport
	if terminal_report == null or terminal_report.session_id != terminal_session_id \
		or terminal_report.outcome not in [&"victory", &"failed"]:
		return _failure(&"RC_SMOKE_TERMINAL_REPORT_INVALID")
	var camp_result := root.return_results_to_camp()
	if camp_result == null or not camp_result.ok:
		return _failure(_app_error(camp_result, &"RC_SMOKE_RETURN_CAMP_FAILED"))
	var helper := _helper(root)
	if helper == null:
		return _failure(&"RC_SMOKE_CONTENT_UNAVAILABLE")
	var commander_id := helper._commander_id()
	var second_started := root.start_expedition(StartExpeditionRequest.new(commander_id, 0))
	if second_started == null or not second_started.ok:
		return _failure(_app_error(second_started, &"RC_SMOKE_SECOND_START_FAILED"))
	var second_session := root.current_run_presentation()
	if second_session == null or not second_session.ok or second_session.session == null:
		return _failure(&"RC_SMOKE_SECOND_SESSION_UNAVAILABLE")
	var second_run_id := second_session.session.snapshot().run_id
	if second_run_id.is_empty() or second_run_id == expected_run_id:
		return _failure(&"RC_SMOKE_SECOND_RUN_ID_INVALID")
	if not _loaded_run_matches(root._save_repository.load(), second_run_id):
		return _failure(&"RC_SMOKE_SECOND_DURABLE_READBACK_MISMATCH")
	checkpoint["second_run_id"] = String(second_run_id)
	checkpoint["terminal_session_id"] = terminal_report.session_id
	checkpoint["terminal_outcome"] = String(terminal_report.outcome)
	var checkpoint_error := _write_json(CHECKPOINT_PATH, checkpoint)
	if not checkpoint_error.is_empty():
		return _failure(checkpoint_error)
	return _success({
		"first_run_id": String(expected_run_id),
		"second_run_id": String(second_run_id),
		"terminal_outcome": String(terminal_report.outcome),
		"report_count": 1,
		"report_codec_readback": true,
	})


func _restart_abandon_verify(root: ApplicationRoot) -> Dictionary:
	var checkpoint_result := _read_checkpoint()
	if not bool(checkpoint_result.get("ok", false)):
		return _failure(StringName(checkpoint_result.get("error", "RC_SMOKE_CHECKPOINT_INVALID")))
	var checkpoint: Dictionary = checkpoint_result.get("checkpoint", {})
	var expected_run_id := StringName(str(checkpoint.get("second_run_id", "")))
	if expected_run_id.is_empty() or not _menu_run_matches(root, expected_run_id):
		return _failure(&"RC_SMOKE_SECOND_RESTART_LOAD_MISMATCH")
	var continued := root.continue_active_run()
	if continued == null or not continued.ok:
		return _failure(_app_error(continued, &"RC_SMOKE_SECOND_CONTINUE_FAILED"))
	var session_result := root.current_run_presentation()
	if session_result == null or not session_result.ok or session_result.session == null \
		or session_result.session.snapshot().run_id != expected_run_id:
		return _failure(&"RC_SMOKE_SECOND_CONTINUED_RUN_MISMATCH")
	var abandon_session_id := root._playtest_session_id
	var abandoned := root._rc_smoke_abandon_active_run(expected_run_id)
	if abandoned == null or not abandoned.ok:
		return _failure(_app_error(abandoned, &"RC_SMOKE_ABANDON_FAILED"))
	var loaded := root._save_repository.load()
	if loaded == null or not loaded.ok or loaded.run_status != LoadResult.RunStatus.NONE:
		return _failure(&"RC_SMOKE_ABANDON_DURABLE_READBACK_FAILED")
	var report_result := _read_reports()
	if not bool(report_result.get("ok", false)):
		return _failure(StringName(report_result.get("error", "RC_SMOKE_REPORT_READ_FAILED")))
	var reports: Array = report_result.get("reports", [])
	if reports.size() != 2:
		return _failure(&"RC_SMOKE_FINAL_REPORT_COUNT_INVALID")
	var outcomes: Array[String] = []
	var session_ids: Array[String] = []
	var found_terminal := false
	var found_abandoned := false
	for value: Variant in reports:
		var report := value as PlaytestSessionReport
		if report == null or session_ids.has(report.session_id):
			return _failure(&"RC_SMOKE_REPORT_ID_INVALID")
		session_ids.append(report.session_id)
		outcomes.append(String(report.outcome))
		if report.session_id == str(checkpoint.get("terminal_session_id", "")) \
			and String(report.outcome) == str(checkpoint.get("terminal_outcome", "")) \
			and report.outcome in [&"victory", &"failed"]:
			found_terminal = true
		if report.session_id == abandon_session_id and report.outcome == &"abandoned":
			found_abandoned = true
	if not found_terminal or not found_abandoned:
		return _failure(&"RC_SMOKE_REPORT_OUTCOMES_INVALID")
	outcomes.sort()
	return _success({
		"second_run_id": String(expected_run_id),
		"outcomes": outcomes,
		"report_count": reports.size(),
		"report_codec_readback": true,
		"abandon_durable_readback": true,
	})


func _drive_to_terminal(root: ApplicationRoot, session: RunPresentationSession) -> StringName:
	var helper := _helper(root)
	if helper == null or root._run_controller == null:
		return &"RC_SMOKE_DRIVER_UNAVAILABLE"
	var strategy := BalanceBotStrategy.new(BalanceBotStrategy.TEMPO)
	var case_result := BalanceBotCaseResult.new()
	case_result.strategy_id = BalanceBotStrategy.TEMPO
	var replay_parts: Array[String] = ["EXPORTED-RC-SMOKE-V1"]
	var snapshot := session.snapshot()
	if snapshot == null or snapshot.map == null:
		return &"RC_SMOKE_SNAPSHOT_INVALID"
	if snapshot.map.nodes.is_empty():
		var generated_error := helper._dispatch(session, RunPresentationIntent.Kind.GENERATE_MAP)
		if not generated_error.is_empty():
			return generated_error
		root._observe_playtest_snapshot(session.snapshot())
	var previous_node_id := ""
	for _step: int in range(STEP_LIMIT):
		if session.view_state().run_phase == RunState.RunPhase.RESULTS:
			return &""
		if session.view_state().run_phase != RunState.RunPhase.MAP:
			return &"RC_SMOKE_UNEXPECTED_RUN_PHASE"
		var reachable := session.reachable_nodes()
		if reachable.is_empty():
			return &"RC_SMOKE_NO_REACHABLE_NODE"
		var current_snapshot := session.snapshot()
		var node_id := helper._choose_route_node(
			BalanceBotStrategy.TEMPO, reachable, current_snapshot.map, previous_node_id
		)
		var node := helper._try_node(current_snapshot.map, node_id)
		if node == null:
			return &"RC_SMOKE_ROUTE_NODE_MISSING"
		var enter := RunPresentationIntent.new(RunPresentationIntent.Kind.ENTER_NODE)
		enter.target_node_id = node_id
		var entered_error := helper._dispatch_intent(session, enter)
		if not entered_error.is_empty():
			return entered_error
		previous_node_id = node_id
		if helper._is_combat(node):
			var combat_error := helper._resolve_combat_node(
				session, root._run_controller, strategy, node, case_result, replay_parts
			)
			if not combat_error.is_empty():
				return combat_error
		elif session.view_state().run_phase == RunState.RunPhase.PREPARE \
			and session.snapshot().node_choice_overlay == null:
			var noncombat_error := helper._dispatch(
				session, RunPresentationIntent.Kind.RESOLVE_NON_COMBAT
			)
			if not noncombat_error.is_empty():
				return noncombat_error
		var resolution_error := helper._resolve_post_node(
			session, BalanceBotStrategy.TEMPO, case_result, replay_parts
		)
		if not resolution_error.is_empty():
			return resolution_error
		root._observe_playtest_snapshot(session.snapshot())
	return &"RC_SMOKE_STEP_LIMIT"


func _helper(root: ApplicationRoot) -> BalanceProductionCaseDriver:
	var content := root._try_content()
	return BalanceProductionCaseDriver.new(content, Callable()) \
		if content != null and content.ok else null


func _menu_run_matches(root: ApplicationRoot, expected_run_id: StringName) -> bool:
	var menu := root.current_menu_snapshot()
	return menu != null and menu.can_continue \
		and StringName(menu.active_run_id_display) == expected_run_id \
		and _loaded_run_matches(root._save_repository.load(), expected_run_id)


func _loaded_run_matches(loaded: LoadResult, expected_run_id: StringName) -> bool:
	return loaded != null and loaded.ok \
		and loaded.run_status == LoadResult.RunStatus.LOADED \
		and loaded.run != null and StringName(loaded.run.run_id) == expected_run_id


func _read_checkpoint() -> Dictionary:
	if not FileAccess.file_exists(CHECKPOINT_PATH):
		return {"ok": false, "error": "RC_SMOKE_CHECKPOINT_MISSING"}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CHECKPOINT_PATH))
	if not parsed is Dictionary or int((parsed as Dictionary).get("schema_version", 0)) != 1:
		return {"ok": false, "error": "RC_SMOKE_CHECKPOINT_INVALID"}
	return {"ok": true, "checkpoint": parsed}


func _read_reports() -> Dictionary:
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(REPORT_ROOT)):
		return {"ok": true, "reports": []}
	var directory := DirAccess.open(REPORT_ROOT)
	if directory == null:
		return {"ok": false, "error": "RC_SMOKE_REPORT_DIRECTORY_FAILED"}
	var names: Array[String] = []
	directory.list_dir_begin()
	var name := directory.get_next()
	while not name.is_empty():
		if not directory.current_is_dir():
			names.append(name)
		name = directory.get_next()
	directory.list_dir_end()
	names.sort()
	var reports: Array[PlaytestSessionReport] = []
	var codec := PlaytestSessionReportCodecV1.new()
	for report_name: String in names:
		if not report_name.begins_with("session-") or report_name.get_extension() != "json":
			return {"ok": false, "error": "RC_SMOKE_REPORT_FILE_INVALID"}
		var report := codec.try_decode(
			FileAccess.get_file_as_string(REPORT_ROOT.path_join(report_name))
		)
		if report == null:
			return {"ok": false, "error": "RC_SMOKE_REPORT_CODEC_FAILED"}
		reports.append(report)
	return {"ok": true, "reports": reports}


func _write_pck_inventory() -> Dictionary:
	var runtime_paths: Array[String] = []
	var scan_error := _scan_runtime_res_tree("res://", runtime_paths)
	if not scan_error.is_empty():
		return {"ok": false, "error": String(scan_error)}
	runtime_paths.sort()
	var entries: Array[Dictionary] = []
	var forbidden_matches: Array[String] = []
	for runtime_path: String in runtime_paths:
		var logical_path := _logical_res_path(runtime_path)
		if logical_path.is_empty():
			return {"ok": false, "error": "RC_SMOKE_PCK_PATH_INVALID"}
		entries.append({
			"logical_res_path": logical_path,
			"remapped": runtime_path.ends_with(".remap"),
			"runtime_res_path": runtime_path,
		})
		var relative_path := logical_path.trim_prefix("res://")
		for prefix: String in FORBIDDEN_RES_PREFIXES:
			if relative_path.begins_with(prefix):
				if not forbidden_matches.has(logical_path):
					forbidden_matches.append(logical_path)
				break
	forbidden_matches.sort()
	var inventory := {
		"schema_version": 1,
		"source": "runtime-mounted-res",
		"entries": entries,
		"file_count": entries.size(),
		"forbidden_entries": forbidden_matches,
		"forbidden_entry_count": forbidden_matches.size(),
		"forbidden_prefixes": FORBIDDEN_RES_PREFIXES,
		"forbidden_matches": forbidden_matches,
		"passed": forbidden_matches.is_empty(),
	}
	var write_error := _write_json(PCK_INVENTORY_PATH, inventory)
	if not write_error.is_empty():
		return {"ok": false, "error": String(write_error)}
	return {
		"ok": true,
		"file_count": entries.size(),
		"passed": forbidden_matches.is_empty(),
	}


func _scan_runtime_res_tree(
	directory_path: String,
	entries: Array[String]
) -> StringName:
	var directory := DirAccess.open(directory_path)
	if directory == null:
		return &"RC_SMOKE_PCK_DIRECTORY_FAILED"
	directory.list_dir_begin()
	var child_directories: Array[String] = []
	var files: Array[String] = []
	var name := directory.get_next()
	while not name.is_empty():
		if name not in [".", ".."]:
			if directory.current_is_dir():
				child_directories.append(name)
			else:
				files.append(name)
		name = directory.get_next()
	directory.list_dir_end()
	files.sort()
	for file_name: String in files:
		entries.append(directory_path.path_join(file_name).replace("\\", "/"))
	child_directories.sort()
	for entry_name: String in child_directories:
		var runtime_path := directory_path.path_join(entry_name).replace("\\", "/")
		var nested_error := _scan_runtime_res_tree(runtime_path, entries)
		if not nested_error.is_empty():
			return nested_error
	return &""


func _logical_res_path(runtime_path: String) -> String:
	var normalized := runtime_path.replace("\\", "/")
	if not normalized.begins_with("res://"):
		return ""
	return normalized.trim_suffix(".remap") if normalized.ends_with(".remap") else normalized


func _write_json(path: String, value: Dictionary) -> StringName:
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(RESULT_ROOT)) != OK:
		return &"RC_SMOKE_RESULT_DIRECTORY_FAILED"
	var text := JSON.stringify(value)
	var temp_path := path + ".tmp"
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		return &"RC_SMOKE_RESULT_WRITE_FAILED"
	file.store_string(text)
	file.flush()
	file.close()
	if FileAccess.get_file_as_string(temp_path) != text:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temp_path))
		return &"RC_SMOKE_RESULT_READBACK_FAILED"
	var absolute_path := ProjectSettings.globalize_path(path)
	var absolute_temp := ProjectSettings.globalize_path(temp_path)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(absolute_path)
	if DirAccess.rename_absolute(absolute_temp, absolute_path) != OK:
		return &"RC_SMOKE_RESULT_RENAME_FAILED"
	return &""


func _finish(root: ApplicationRoot, phase: StringName, result: Dictionary) -> void:
	result["schema_version"] = 1
	result["phase"] = String(phase)
	var write_error := _write_json(
		RESULT_ROOT.path_join("phase-%s.json" % String(phase)), result
	)
	if not write_error.is_empty():
		result["ok"] = false
		var errors: Array = result.get("error_codes", [])
		errors.append(String(write_error))
		result["error_codes"] = errors
	print(RESULT_MARKER + JSON.stringify(result))
	root.get_tree().quit(0 if bool(result.get("ok", false)) else 2)


func _success(values: Dictionary = {}) -> Dictionary:
	var result := {"ok": true, "error_codes": []}
	for key: Variant in values.keys():
		result[key] = values[key]
	return result


func _failure(code: StringName) -> Dictionary:
	return {"ok": false, "error_codes": [String(code)]}


func _failure_with(code: StringName, values: Dictionary) -> Dictionary:
	var result := _failure(code)
	for key: Variant in values.keys():
		result[key] = values[key]
	return result


func _app_error(result: AppActionResult, fallback: StringName) -> StringName:
	return result.error.source_code \
		if result != null and result.error != null \
		and not result.error.source_code.is_empty() else fallback
