extends SceneTree

const Support = preload(
	"res://tests/integration/presentation_ui_r14_accessibility_joint/"
	+ "r14_accessibility_joint_test_support.gd"
)

const CASES: Array[Dictionary] = [
	{"name": "baseline-720", "size": Vector2i(1280, 720), "ui": 100, "color": &"default", "covers": ["720p", "16:9", "ui-100", "color-default"]},
	{"name": "resolution-1080", "size": Vector2i(1920, 1080), "ui": 100, "color": &"default", "covers": ["1080p", "16:9"]},
	{"name": "resolution-1440", "size": Vector2i(2560, 1440), "ui": 100, "color": &"default", "covers": ["1440p", "16:9"]},
	{"name": "aspect-4x3", "size": Vector2i(1024, 768), "ui": 100, "color": &"default", "covers": ["4:3"]},
	{"name": "aspect-16x10", "size": Vector2i(1280, 800), "ui": 100, "color": &"default", "covers": ["16:10"]},
	{"name": "ui-125", "size": Vector2i(1280, 720), "ui": 125, "color": &"default", "covers": ["ui-125"]},
	{"name": "ui-150", "size": Vector2i(1280, 720), "ui": 150, "color": &"default", "covers": ["ui-150"]},
	{"name": "color-protanopia", "size": Vector2i(1280, 720), "ui": 100, "color": &"protanopia", "covers": ["color-protanopia"]},
	{"name": "color-deuteranopia", "size": Vector2i(1280, 720), "ui": 100, "color": &"deuteranopia", "covers": ["color-deuteranopia"]},
	{"name": "color-tritanopia", "size": Vector2i(1280, 720), "ui": 100, "color": &"tritanopia", "covers": ["color-tritanopia"]},
]

var _issues: Array[String] = []
var _reports: Array[Dictionary] = []
var _saved: Array[String] = []
var _harness: Support.BootHarness


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var output_dir := _output_directory().trim_suffix("/")
	var absolute_output := ProjectSettings.globalize_path(output_dir)
	if DirAccess.make_dir_recursive_absolute(absolute_output) != OK:
		await _finish(output_dir, ["output_directory_failed"])
		return
	_harness = Support.boot_runtime(self)
	if not _harness.settings_bind_error.is_empty():
		await _finish(
			output_dir,
			["settings_service_binding:%s" % _harness.settings_bind_error]
		)
		return
	if not _harness.boot_error.is_empty() or not _harness.root.is_booted():
		await _finish(
			output_dir,
			["app_root_boot_failed:%s" % _harness.boot_error]
		)
		return
	var driven := Support.drive_to_run_prepare(_harness)
	if not bool(driven.get("ok", false)):
		await _finish(
			output_dir,
			["run_prepare_route_failed:%s" % driven.get("error", &"")]
		)
		return
	var seed_error := Support.seed_committed_combat_phase(_harness)
	if not seed_error.is_empty():
		await _finish(output_dir, ["combat_seed_failed:%s" % seed_error])
		return
	var gameplay_storage := _harness.gameplay_storage
	var settings_storage := _harness.settings_storage
	_harness.dispose()
	await process_frame
	await process_frame
	await process_frame
	_harness = Support.boot_runtime(
		self,
		gameplay_storage,
		settings_storage
	)
	if (
		not _harness.settings_bind_error.is_empty()
		or not _harness.boot_error.is_empty()
		or not _harness.root.is_booted()
	):
		await _finish(output_dir, ["combat_app_root_reboot_failed"])
		return
	var continued := Support.continue_to_run_combat(_harness)
	if not bool(continued.get("ok", false)):
		await _finish(
			output_dir,
			["run_combat_route_failed:%s" % continued.get("error", &"")]
		)
		return
	await process_frame
	await process_frame
	await process_frame

	for case: Dictionary in CASES:
		await _capture_case(output_dir, case)
	_validate_coverage()
	_validate_visual_variants()
	await _finish(output_dir, _issues)


func _capture_case(output_dir: String, case: Dictionary) -> void:
	var case_name := String(case["name"])
	var window_size: Vector2i = case["size"]
	get_root().content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	get_root().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	get_root().content_scale_size = window_size
	get_root().size = window_size
	var settings := Support.candidate(
		int(case["ui"]),
		StringName(case["color"])
	)
	var port := _harness.root.settings_application_port()
	if port == null:
		_issues.append("settings_port_missing:%s" % case_name)
		return
	var applied: SettingsApplicationResult = port.apply(settings)
	if not applied.ok:
		_issues.append(
			"settings_apply_failed:%s:%s"
			% [
				case_name,
				applied.error.source_code if applied.error != null else &"",
			]
		)
		return
	var reload_error := Support.reload_current_route(_harness)
	if not reload_error.is_empty():
		_issues.append("route_reload_failed:%s:%s" % [case_name, reload_error])
		return
	await process_frame
	await process_frame
	await process_frame
	await process_frame
	var report := Support.machine_report(_harness, window_size, settings)
	report["name"] = case_name
	report["covers"] = (case["covers"] as Array).duplicate()
	report["settings_repository_committed"] = Support.snapshots_equal(
		_harness.settings_repository.current_snapshot(),
		settings
	)
	if not bool(report["settings_repository_committed"]):
		(report["issues"] as Array).append("settings_repository_mismatch")
		report["ok"] = false

	var resource_path := "%s/r14-%s.png" % [output_dir, case_name]
	var absolute_path := ProjectSettings.globalize_path(resource_path)
	var image := get_root().get_texture().get_image()
	var save_error := image.save_png(absolute_path)
	if save_error != OK:
		_issues.append("screenshot_write_failed:%s" % case_name)
		report["screenshot"] = {"ok": false}
		_reports.append(report)
		return
	var readback := Image.load_from_file(absolute_path)
	var dimensions_ok := (
		readback != null
		and readback.get_width() == window_size.x
		and readback.get_height() == window_size.y
	)
	var non_black := _image_non_black(readback)
	var sha256 := FileAccess.get_sha256(absolute_path)
	report["screenshot"] = {
		"ok": dimensions_ok and non_black and not sha256.is_empty(),
		"path": resource_path,
		"sha256": sha256,
		"width": readback.get_width() if readback != null else 0,
		"height": readback.get_height() if readback != null else 0,
		"non_black": non_black,
		"readback": readback != null,
	}
	if not bool((report["screenshot"] as Dictionary)["ok"]):
		(report["issues"] as Array).append("screenshot_readback_failed")
		report["ok"] = false
	for issue: Variant in report["issues"] as Array:
		_issues.append("%s:%s" % [case_name, String(issue)])
	_saved.append(resource_path)
	_reports.append(report)


func _validate_coverage() -> void:
	var required := [
		"720p",
		"1080p",
		"1440p",
		"4:3",
		"16:10",
		"ui-100",
		"ui-125",
		"ui-150",
		"color-default",
		"color-protanopia",
		"color-deuteranopia",
		"color-tritanopia",
	]
	var observed: Array[String] = []
	for report: Dictionary in _reports:
		for item: Variant in report.get("covers", []):
			var coverage := String(item)
			if not observed.has(coverage):
				observed.append(coverage)
	for coverage: String in required:
		if not observed.has(coverage):
			_issues.append("coverage_missing:%s" % coverage)


func _validate_visual_variants() -> void:
	var ui_hashes: Array[String] = []
	var color_hashes: Array[String] = []
	for report: Dictionary in _reports:
		var name := String(report.get("name", ""))
		var screenshot := report.get("screenshot", {}) as Dictionary
		var digest := String(screenshot.get("sha256", ""))
		if name in ["baseline-720", "ui-125", "ui-150"]:
			if not ui_hashes.has(digest):
				ui_hashes.append(digest)
		if name.begins_with("color-") or name == "baseline-720":
			if not color_hashes.has(digest):
				color_hashes.append(digest)
	if ui_hashes.size() < 3:
		_issues.append("ui_scale_visual_variants_not_distinct")
	if color_hashes.size() < 4:
		_issues.append("color_mode_visual_variants_not_distinct")


func _image_non_black(image: Image) -> bool:
	if image == null or image.is_empty():
		return false
	var width := image.get_width()
	var height := image.get_height()
	for y: int in range(0, height, maxi(1, height / 32)):
		for x: int in range(0, width, maxi(1, width / 32)):
			var color := image.get_pixel(x, y)
			if color.a > 0.1 and (
				color.r > 0.02 or color.g > 0.02 or color.b > 0.02
			):
				return true
	return false


func _output_directory() -> String:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output-dir="):
			return argument.trim_prefix("--output-dir=")
	return "res://.pipeline/visual/r14-production-runtime"


func _finish(output_dir: String, issues: Array[String]) -> void:
	var coverage_model := {
		"kind": "layered_matrix",
		"full_cartesian": false,
		"case_count": CASES.size(),
		"dimensions": {
			"resolutions": ["1280x720", "1920x1080", "2560x1440"],
			"additional_aspects": ["1024x768 (4:3)", "1280x800 (16:10)"],
			"ui_scales": [100, 125, 150],
			"color_modes": [
				"default",
				"protanopia",
				"deuteranopia",
				"tritanopia",
			],
		},
	}
	var result := {
		"ok": issues.is_empty(),
		"exit_code": 0 if issues.is_empty() else 2,
		"production_entry": "ApplicationRoot",
		"production_route": "RUN_COMBAT",
		"settings_entry": "ApplicationRoot.settings_application_port",
		"consumer_constructed_by_test": false,
		"fixture_scene_used": false,
		"output_dir": output_dir,
		"coverage_model": coverage_model,
		"expected_count": CASES.size(),
		"saved": _saved,
		"reports": _reports,
		"issues": issues,
	}
	var absolute_report := ProjectSettings.globalize_path(
		"%s/runtime-screenshot-report.json" % output_dir
	)
	var file := FileAccess.open(absolute_report, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(result, "\t"))
		file.close()
	else:
		result["ok"] = false
		result["exit_code"] = 2
		(result["issues"] as Array).append("report_write_failed")
	print(JSON.stringify(result))
	if _harness != null:
		_harness.dispose()
		_harness = null
		await process_frame
		await process_frame
		await process_frame
	quit(int(result["exit_code"]))
