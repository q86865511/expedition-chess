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
	{"name": "1440p-ui100", "size": Vector2i(2560, 1440), "ui": 100},
	{"name": "1440p-ui125", "size": Vector2i(2560, 1440), "ui": 125},
	{"name": "1440p-ui150", "size": Vector2i(2560, 1440), "ui": 150},
]
const UI_REFERENCE_SIZE := Vector2i(1920, 1080)
const EVIDENCE_ROOT := "res://specs/ui-art-refresh/evidence"
const DEFAULT_OUTPUT_DIR := EVIDENCE_ROOT + "/b-out-1"

var _harness: Support.BootHarness
var _reports: Array[Dictionary] = []
var _issues: Array[String] = []


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var output_dir := _output_directory().trim_suffix("/")
	if output_dir.is_empty():
		quit(3)
		return
	if DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(output_dir)
	) != OK:
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
	for case: Dictionary in CASES:
		await _capture(output_dir, &"MENU_MAIN", "menu-main", case)
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
	_validate_visual_contract(
		screen,
		expected_route,
		String(case["name"]),
		int(case["ui"])
	)
	var path := "%s/%s-%s.png" % [output_dir, prefix, case["name"]]
	_reports.append(_save_viewport(path, prefix, case))


func _validate_visual_contract(
	screen: ProductionScreen,
	route: StringName,
	case_name: String,
	ui_scale: int
) -> void:
	if route == &"CAMP_WORLD":
		var texture := screen.find_child(
			"CampEnvironmentTexture", true, false
		) as TextureRect
		if texture == null or texture.texture == null:
			_issues.append("camp_environment_missing:%s" % case_name)
		var environment_view := screen.find_child(
			"CampEnvironmentView", true, false
		) as Control
		if (
			environment_view == null
			or environment_view.get_global_rect().size.x < 1200.0
		):
			_issues.append("camp_environment_not_primary:%s" % case_name)
		var markers := screen.find_children("Facility*", "Button", true, false)
		if markers.size() != 5:
			_issues.append("camp_facility_marker_count:%s:%d" % [
				case_name, markers.size(),
			])
		for node: Node in markers:
			var marker := node as Button
			if (
				marker == null
				or marker.focus_mode != Control.FOCUS_ALL
				or not marker.has_meta(&"action_id")
			):
				_issues.append("camp_marker_not_interactive:%s:%s" % [
					case_name, node.name,
				])
		_validate_camp_region_bounds(screen, case_name, ui_scale)
		return
	var key_art := screen.get_node_or_null(^"MenuKeyArt") as TextureRect
	var actions := screen.get_node_or_null(^"Actions") as BoxContainer
	if key_art == null or key_art.texture == null:
		_issues.append("menu_key_art_missing:%s" % case_name)
	if screen.get_node_or_null(^"MenuActionPanel") != null:
		_issues.append("menu_backing_panel_present:%s" % case_name)
	if actions == null:
		_issues.append("menu_actions_missing:%s" % case_name)
		return
	var safe_rect := Rect2(Vector2.ZERO, UI_REFERENCE_SIZE)
	if not safe_rect.encloses(actions.get_rect()):
		_issues.append("menu_actions_out_of_bounds:%s" % case_name)
	var expected_width := (
		ExpeditionLayoutMetrics.MENU_ACTIONS_RECT.size.x
		* float(ui_scale) / 100.0
	)
	if not is_equal_approx(actions.get_rect().size.x, expected_width):
		_issues.append("menu_hit_rect_scale_mismatch:%s:%s:%s" % [
			case_name, actions.get_rect().size.x, expected_width,
		])


func _validate_camp_region_bounds(
	screen: ProductionScreen,
	case_name: String,
	ui_scale: int
) -> void:
	if screen.find_child("Actions", true, false) != null:
		_issues.append("camp_duplicate_facility_list_present:%s" % case_name)
	var environment_view := screen.find_child(
		"CampEnvironmentView", true, false
	) as Control
	if environment_view != null:
		var environment_rect := environment_view.get_global_rect()
		for node: Node in screen.find_children("Facility*", "Button", true, false):
			var marker := node as Button
			if marker != null and not environment_rect.encloses(marker.get_global_rect()):
				_issues.append("camp_facility_out_of_bounds:%s:%s" % [
					case_name, marker.name,
				])
	var right_rect := screen.layout_region_content_rect(
		ProductionLayoutShell.REGION_RIGHT
	)
	var expedition := screen.find_child(
		"ExpeditionPanelContent", true, false
	) as Control
	if expedition == null:
		_issues.append("camp_expedition_panel_missing:%s" % case_name)
		return
	if expedition.get_global_rect().size.x > ProductionLayoutShell.SIDE_WIDTH * 0.5:
		_issues.append("camp_expedition_panel_not_compact:%s" % case_name)
	for node: Node in expedition.get_children():
		var control := node as Control
		if control != null and not right_rect.encloses(control.get_global_rect()):
			_issues.append(
				"camp_expedition_control_out_of_bounds:%s:%s:%s:%s" % [
					case_name,
					control.name,
					str(control.get_global_rect()),
					str(right_rect),
				]
			)
	var start := _action_button(screen, &"camp.start")
	if start == null or not expedition.is_ancestor_of(start):
		_issues.append("camp_start_not_in_expedition_card:%s" % case_name)
	var bottom_rect := screen.layout_region_content_rect(
		ProductionLayoutShell.REGION_BOTTOM
	)
	var max_bottom_content_height := 84.0 * float(ui_scale) / 100.0
	if bottom_rect.size.y > max_bottom_content_height + 1.0:
		_issues.append("camp_bottom_band_too_tall:%s:%s" % [
			case_name, bottom_rect.size.y,
		])
	for action_id: StringName in [&"camp.settings", &"camp.menu"]:
		var action := _action_button(screen, action_id)
		if (
			action == null
			or not bottom_rect.encloses(action.get_global_rect())
			or action.get_global_rect().size.x > 240.0
		):
			_issues.append("camp_secondary_action_layout:%s:%s" % [
				case_name, action_id,
			])


func _action_button(screen: ProductionScreen, action_id: StringName) -> Button:
	for node: Node in screen.find_children("*", "Button", true, false):
		var button := node as Button
		if (
			button != null
			and button.has_meta(&"action_id")
			and StringName(button.get_meta(&"action_id")) == action_id
		):
			return button
	return null


func _configure_window(size: Vector2i) -> void:
	get_root().content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	get_root().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	get_root().content_scale_size = UI_REFERENCE_SIZE
	get_root().size = size


func _save_viewport(path: String, prefix: String, case: Dictionary) -> Dictionary:
	var absolute_path := ProjectSettings.globalize_path(path)
	var image := get_root().get_texture().get_image()
	var error := image.save_png(absolute_path)
	var readback := Image.load_from_file(absolute_path)
	var report := {
		"ok": error == OK and readback != null and not readback.is_empty(),
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


func _output_directory() -> String:
	var requested := DEFAULT_OUTPUT_DIR
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output-dir="):
			requested = argument.trim_prefix("--output-dir=")
			break
	var absolute := ProjectSettings.globalize_path(
		requested.replace("\\", "/")
	).simplify_path()
	var allowed := ProjectSettings.globalize_path(
		EVIDENCE_ROOT
	).simplify_path().trim_suffix("/") + "/"
	if not absolute.to_lower().begins_with(allowed.to_lower()):
		return ""
	return ProjectSettings.localize_path(absolute).replace("\\", "/")


func _finish(output_dir: String) -> void:
	var report := {
		"ok": _issues.is_empty() and _reports.size() == CASES.size() * 2,
		"exit_code": 0 if _issues.is_empty() else 2,
		"expected_screenshot_count": CASES.size() * 2,
		"screenshots": _reports,
		"issues": _issues,
	}
	var report_path := ProjectSettings.globalize_path(
		"%s/evidence-report.json" % output_dir
	)
	var file := FileAccess.open(report_path, FileAccess.WRITE)
	if file == null:
		quit(3)
		return
	file.store_string(JSON.stringify(report, "  ") + "\n")
	file.close()
	print(JSON.stringify(report))
	quit(0 if bool(report["ok"]) else 2)
