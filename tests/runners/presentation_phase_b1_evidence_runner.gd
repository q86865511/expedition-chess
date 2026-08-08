extends SceneTree

const Support = preload(
	"res://tests/integration/presentation_ui_r14_accessibility_joint/"
	+ "r14_accessibility_joint_test_support.gd"
)

const CASES: Array[Dictionary] = [
	{"name": "720p-ui100", "size": Vector2i(1280, 720), "ui": 100},
	{"name": "720p-ui125", "size": Vector2i(1280, 720), "ui": 125},
	{"name": "720p-ui150", "size": Vector2i(1280, 720), "ui": 150},
	{"name": "1080p-ui100", "size": Vector2i(1920, 1080), "ui": 100},
	{"name": "1080p-ui125", "size": Vector2i(1920, 1080), "ui": 125},
	{"name": "1080p-ui150", "size": Vector2i(1920, 1080), "ui": 150},
]

var _harness: Support.BootHarness
var _reports: Array[Dictionary] = []
var _issues: Array[String] = []


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var output_dir := _output_directory().trim_suffix("/")
	var absolute_output := ProjectSettings.globalize_path(output_dir)
	if DirAccess.make_dir_recursive_absolute(absolute_output) != OK:
		quit(3)
		return
	_harness = Support.boot_runtime(self)
	await process_frame
	await process_frame
	if not _harness.root.is_booted():
		_issues.append("app_root_boot_failed:%s" % _harness.boot_error)
		await _finish(output_dir)
		return
	var opened := _harness.root.open_camp()
	if not opened.ok:
		_issues.append("camp_route_failed")
		await _finish(output_dir)
		return
	await process_frame
	await process_frame
	for case: Dictionary in CASES:
		await _capture(output_dir, &"CAMP_WORLD", "camp", case)

	var returned := _harness.root.return_to_menu()
	if not returned.ok:
		_issues.append("return_to_menu_failed")
		await _finish(output_dir)
		return
	await process_frame
	await process_frame
	var driven := Support.drive_to_run_prepare(_harness)
	if not bool(driven.get("ok", false)):
		_issues.append("run_prepare_route_failed:%s" % driven.get("error", &""))
		await _finish(output_dir)
		return
	await process_frame
	await process_frame
	for case: Dictionary in CASES:
		await _capture(output_dir, &"RUN_PREPARE", "prepare", case)
	await _capture_scale_rebuild(output_dir)
	await _capture_node_choice(output_dir)
	await _capture_status_band(output_dir)
	await _capture_focus(output_dir)
	await _finish(output_dir)


func _capture(
	output_dir: String,
	expected_route: StringName,
	prefix: String,
	case: Dictionary
) -> void:
	_configure_window(case["size"])
	var settings := Support.candidate(int(case["ui"]), &"default")
	settings.locale = &"zh_TW"
	var applied := _harness.root.settings_application_port().apply(settings)
	if not applied.ok:
		_issues.append("settings_apply_failed:%s:%s" % [prefix, case["name"]])
		return
	await process_frame
	await process_frame
	await process_frame
	var screen := Support.active_screen(_harness)
	if screen == null or screen.route_kind != expected_route:
		_issues.append("route_mismatch:%s:%s" % [prefix, case["name"]])
		return
	if prefix == "prepare":
		_validate_prepare_top_bar(screen, String(case["name"]))
		_validate_prepare_content_regions(screen, String(case["name"]))
	var path := "%s/%s-%s.png" % [output_dir, prefix, case["name"]]
	_reports.append(_save_viewport(path, prefix, case))


func _validate_prepare_top_bar(screen: Control, case_name: String) -> void:
	var title := screen.get_node_or_null(^"Label") as Label
	var metrics := screen.get_node_or_null(^"Composition/PrepareContent/PrepareMetrics") as Control
	if title == null or metrics == null:
		_issues.append("prepare_top_bar_missing:%s" % case_name)
		return
	var title_rect := title.get_global_rect()
	var metrics_rect := metrics.get_global_rect()
	if title_rect.intersects(metrics_rect):
		_issues.append("prepare_top_bar_overlap:%s" % case_name)
	var viewport_rect := get_root().get_visible_rect()
	for node: Node in metrics.get_children():
		var label := node as Label
		if label == null:
			continue
		if not viewport_rect.encloses(label.get_global_rect()):
			_issues.append("prepare_metric_overflow:%s:%s" % [case_name, label.name])


func _validate_prepare_content_regions(screen: Control, case_name: String) -> void:
	var shell := screen.get("_layout_shell") as ProductionLayoutShell
	if shell == null:
		_issues.append("prepare_layout_shell_missing:%s" % case_name)
		return
	var center_rect := shell.current_region_rect(ProductionLayoutShell.REGION_CENTER)
	var status_rect := shell.current_region_rect(ProductionLayoutShell.REGION_STATUS)
	var bottom_rect := shell.current_region_rect(ProductionLayoutShell.REGION_BOTTOM)
	for node_path: NodePath in [
		^"Composition/PrepareContent/PrepareCenterContent/BoardGrid",
		^"Composition/PrepareContent/PrepareCenterContent/BenchRow",
	]:
		var control := screen.get_node_or_null(node_path) as Control
		if control == null:
			_issues.append("prepare_region_control_missing:%s:%s" % [case_name, node_path])
			continue
		var control_rect := control.get_global_rect()
		if not center_rect.encloses(control_rect):
			_issues.append("prepare_center_overflow:%s:%s" % [case_name, node_path])
		if control_rect.intersects(status_rect) or control_rect.intersects(bottom_rect):
			_issues.append("prepare_center_cross_region:%s:%s" % [case_name, node_path])


func _capture_focus(output_dir: String) -> void:
	_configure_window(Vector2i(1280, 720))
	var settings := Support.candidate(100, &"default")
	settings.locale = &"zh_TW"
	_harness.root.settings_application_port().apply(settings)
	var screen := Support.active_screen(_harness)
	var start_button: Button
	if screen != null:
		for node: Node in screen.find_children("*", "Button", true, false):
			var button := node as Button
			if button != null and StringName(button.get_meta(&"action_id", &"")) == &"prepare.start":
				start_button = button
				break
	if start_button == null:
		_issues.append("focus_target_missing")
		return
	start_button.grab_focus()
	await process_frame
	await process_frame
	var case := {"name": "focus-prepare-start", "size": Vector2i(1280, 720), "ui": 100}
	_reports.append(_save_viewport(
		"%s/focus-prepare-start.png" % output_dir,
		"focus",
		case
	))


func _capture_scale_rebuild(output_dir: String) -> void:
	_configure_window(Vector2i(1280, 720))
	var scaled := Support.candidate(150, &"default")
	scaled.locale = &"zh_TW"
	var applied := _harness.root.settings_application_port().apply(scaled)
	if not applied.ok:
		_issues.append("scale_rebuild_150_apply_failed")
		return
	await process_frame
	await process_frame
	var reload_error := Support.reload_current_route(_harness)
	if not reload_error.is_empty():
		_issues.append("scale_rebuild_route_failed:%s" % reload_error)
		return
	await process_frame
	await process_frame
	var baseline := Support.candidate(100, &"default")
	baseline.locale = &"zh_TW"
	var restored := _harness.root.settings_application_port().apply(baseline)
	await process_frame
	await process_frame
	var screen := Support.active_screen(_harness)
	var start := _action_button(screen, &"prepare.start")
	var report := {
		"ok": restored.ok and start != null and start.custom_minimum_size.y == 48.0,
		"sequence": [150, "rebuild", 100],
		"start_button_minimum": start.custom_minimum_size if start != null else Vector2.ZERO,
		"effective_scale": (
			_harness.root.presentation_host.get_meta(
				&"effective_theme_scale_percent", 0
			)
			if _harness.root.presentation_host != null
			else 0
		),
	}
	if not bool(report["ok"]):
		_issues.append("scale_rebuild_baseline_not_restored")
	_write_json("%s/scale-rebuild-report.json" % output_dir, report)
	_reports.append(_save_viewport(
		"%s/prepare-scale-rebuild-150-rebuild-100.png" % output_dir,
		"prepare-scale-rebuild",
		{"name": "150-rebuild-100", "size": Vector2i(1280, 720), "ui": 100}
	))


func _capture_node_choice(output_dir: String) -> void:
	var screen := Support.active_screen(_harness)
	var composition := screen.get_node_or_null(^"Composition") as RunPrepareScreen if screen != null else null
	var context := screen.get("_context") as StagedScreenContext if screen != null else null
	var live_context := screen.get("_live_context") as ProductionLiveScreenContext if screen != null else null
	var snapshot := context.snapshot_clone() as RunPresentationSnapshot if context != null else null
	if composition == null or live_context == null or snapshot == null:
		_issues.append("node_choice_prepare_context_missing")
		return
	var overlay := NodeChoiceOverlaySnapshot.new()
	overlay.choice_set_id = &"evidence.choice_set"
	overlay.display_name_key = &"prepare.panel.expedition"
	overlay.options = [
		NodeChoiceOptionSnapshot.new(
			&"choice_a", &"prepare.panel.party", &"prepare.panel.party",
			&"prepare.empty.synergies", true
		),
		NodeChoiceOptionSnapshot.new(
			&"choice_b", &"prepare.panel.inventory", &"prepare.panel.inventory",
			&"prepare.empty.overflow", true
		),
		NodeChoiceOptionSnapshot.new(
			&"choice_c", &"prepare.panel.shop", &"prepare.panel.shop",
			&"prepare.empty.issues", true
		),
	]
	snapshot.node_choice_overlay = overlay
	var report := screen.call(&"_snapshot_board_validation_report", snapshot) as BoardValidationReport
	var compose_error := composition.compose(snapshot, report, live_context.intent_port)
	screen.refresh_interaction_state()
	await process_frame
	await process_frame
	var scroll := screen.find_child("PrepareRightScroll", true, false) as ScrollContainer
	var start := _action_button(screen, &"prepare.start")
	var choice := screen.find_child("ChoiceSelector", true, false) as ItemList
	var canvas := Rect2(Vector2.ZERO, Vector2(1280.0, 720.0))
	var start_rect := start.get_global_rect() if start != null else Rect2()
	var right_rect := scroll.get_global_rect() if scroll != null else Rect2()
	var scenario := {
		"ok": (
			compose_error.is_empty()
			and scroll != null
			and choice != null
			and start != null
			and canvas.encloses(start_rect)
			and not right_rect.intersects(start_rect)
		),
		"right_scroll_present": scroll != null,
		"choice_count": choice.item_count if choice != null else 0,
		"start_button_rect": start_rect,
		"right_panel_rect": right_rect,
	}
	if not bool(scenario["ok"]):
		_issues.append("node_choice_layout_failed:%s" % compose_error)
	_write_json("%s/node-choice-layout-report.json" % output_dir, scenario)
	_reports.append(_save_viewport(
		"%s/prepare-node-choice-720p-ui100.png" % output_dir,
		"prepare-node-choice",
		{"name": "node-choice-720p-ui100", "size": Vector2i(1280, 720), "ui": 100}
	))


func _capture_status_band(output_dir: String) -> void:
	var screen := Support.active_screen(_harness)
	if screen == null:
		_issues.append("status_screen_missing")
		return
	var injected := AppActionResult.failure(
		DiagnosticError.new(
			&"PREPARE_SELECTION_REQUIRED",
			&"error.presentation.prepare_selection_required"
		)
	)
	screen.report_composition_result(injected)
	await process_frame
	await process_frame
	var shell := screen.get("_layout_shell") as ProductionLayoutShell
	var status_rect := shell.current_region_rect(ProductionLayoutShell.REGION_STATUS)
	var center_rect := shell.current_region_rect(ProductionLayoutShell.REGION_CENTER)
	var report := {
		"ok": not screen.status_message_text().is_empty() and not status_rect.intersects(center_rect),
		"message": screen.status_message_text(),
		"status_rect": status_rect,
		"content_rect": center_rect,
	}
	if not bool(report["ok"]):
		_issues.append("status_band_not_reserved")
	_write_json("%s/status-band-report.json" % output_dir, report)
	_reports.append(_save_viewport(
		"%s/prepare-status-message-720p-ui100.png" % output_dir,
		"prepare-status",
		{"name": "status-720p-ui100", "size": Vector2i(1280, 720), "ui": 100}
	))


func _action_button(screen: ProductionScreen, action_id: StringName) -> Button:
	if screen == null:
		return null
	for node: Node in screen.find_children("*", "Button", true, false):
		var button := node as Button
		if button != null and StringName(button.get_meta(&"action_id", &"")) == action_id:
			return button
	return null


func _configure_window(size: Vector2i) -> void:
	get_root().content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	get_root().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	get_root().content_scale_size = Vector2i(1280, 720)
	get_root().size = size


func _save_viewport(path: String, prefix: String, case: Dictionary) -> Dictionary:
	var absolute_path := ProjectSettings.globalize_path(path)
	var image := get_root().get_texture().get_image()
	var error := image.save_png(absolute_path)
	var readback := Image.load_from_file(absolute_path)
	var report := {
		"ok": error == OK and readback != null and _image_non_black(readback),
		"route": prefix,
		"case": String(case["name"]),
		"ui_scale": int(case["ui"]),
		"requested_width": (case["size"] as Vector2i).x,
		"requested_height": (case["size"] as Vector2i).y,
		"width": readback.get_width() if readback != null else 0,
		"height": readback.get_height() if readback != null else 0,
		"sha256": FileAccess.get_sha256(absolute_path),
		"path": path,
	}
	if not bool(report["ok"]):
		_issues.append("screenshot_failed:%s:%s" % [prefix, case["name"]])
	return report


func _image_non_black(image: Image) -> bool:
	if image == null or image.is_empty():
		return false
	for y: int in range(0, image.get_height(), maxi(1, image.get_height() / 32)):
		for x: int in range(0, image.get_width(), maxi(1, image.get_width() / 32)):
			var color := image.get_pixel(x, y)
			if color.a > 0.1 and (color.r > 0.02 or color.g > 0.02 or color.b > 0.02):
				return true
	return false


func _output_directory() -> String:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output-dir="):
			return argument.trim_prefix("--output-dir=")
	return "res://specs/ui-art-refresh/evidence/phase-b1"


func _write_json(path: String, value: Dictionary) -> void:
	var file := FileAccess.open(ProjectSettings.globalize_path(path), FileAccess.WRITE)
	if file == null:
		_issues.append("report_write_failed:%s" % path)
		return
	file.store_string(JSON.stringify(value, "\t"))
	file.close()


func _finish(output_dir: String) -> void:
	_write_json("%s/evidence-report.json" % output_dir, {
		"ok": _issues.is_empty(),
		"exit_code": 0 if _issues.is_empty() else 2,
		"locale": "zh_TW",
		"cases": _reports,
		"issues": _issues,
	})
	if _harness != null:
		_harness.dispose()
		await process_frame
		await process_frame
	quit(0 if _issues.is_empty() else 2)
