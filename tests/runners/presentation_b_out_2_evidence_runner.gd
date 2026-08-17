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
const ROUTES: Array[Dictionary] = [
	{"route": &"CAMP_WORLD", "slug": "camp"},
	{"route": &"FACILITY_EXPEDITION_GATE", "slug": "expedition-gate"},
	{"route": &"FACILITY_COMMANDER_HALL", "slug": "commander-hall"},
	{"route": &"COLLECTION", "slug": "collection"},
	{"route": &"FACILITY_UNLOCK_WORKSHOP", "slug": "unlock-workshop"},
	{"route": &"FACILITY_CHALLENGE_MONUMENT", "slug": "challenge-monument"},
]
const FACILITY_ROUTES: Array[StringName] = [
	&"FACILITY_EXPEDITION_GATE",
	&"FACILITY_COMMANDER_HALL",
	&"COLLECTION",
	&"FACILITY_UNLOCK_WORKSHOP",
	&"FACILITY_CHALLENGE_MONUMENT",
]
const UI_REFERENCE_SIZE := Vector2i(1920, 1080)
const EVIDENCE_ROOT := "res://specs/ui-art-refresh/evidence"
const DEFAULT_OUTPUT_DIR := EVIDENCE_ROOT + "/b-out-2"

var _harness: Support.BootHarness
var _reports: Array[Dictionary] = []
var _issues: Array[String] = []
var _selected_cases: Array[Dictionary] = []
var _selected_routes: Array[Dictionary] = []


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	_configure_selection()
	if _selected_cases.is_empty() or _selected_routes.is_empty():
		quit(3)
		return
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
	for route_spec: Dictionary in _selected_routes:
		var route := StringName(route_spec["route"])
		if route != &"CAMP_WORLD":
			if not await _open_facility(route):
				break
		for case: Dictionary in _selected_cases:
			await _capture(
				output_dir,
				route,
				String(route_spec["slug"]),
				case
			)
		if route != &"CAMP_WORLD" and not await _return_to_camp(route):
			break
	await _finish(output_dir)


func _configure_selection() -> void:
	var route_filter := &""
	var ui_scales: Array[int] = []
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--route="):
			route_filter = StringName(argument.trim_prefix("--route="))
		elif argument.begins_with("--ui-scales="):
			for value: String in argument.trim_prefix("--ui-scales=").split(","):
				var parsed := value.to_int()
				if parsed in [100, 125, 150] and not ui_scales.has(parsed):
					ui_scales.append(parsed)
	for route_spec: Dictionary in ROUTES:
		if route_filter.is_empty() or StringName(route_spec["route"]) == route_filter:
			_selected_routes.append(route_spec)
	for case: Dictionary in CASES:
		if ui_scales.is_empty() or ui_scales.has(int(case["ui"])):
			_selected_cases.append(case)


func _open_facility(route: StringName) -> bool:
	var screen := Support.active_screen(_harness)
	var camp := (
		screen.get_node_or_null(^"Composition") as CampWorldScreen
		if screen != null and screen.route_kind == &"CAMP_WORLD"
		else null
	)
	if camp == null:
		_issues.append("camp_composition_missing_before:%s" % route)
		return false
	var opened := camp.open_facility(route)
	if not opened.ok:
		_issues.append("facility_route_failed:%s" % route)
		return false
	await process_frame
	await process_frame
	var active := Support.active_screen(_harness)
	if active == null or active.route_kind != route:
		_issues.append("facility_route_mismatch:%s" % route)
		return false
	return true


func _return_to_camp(route: StringName) -> bool:
	var screen := Support.active_screen(_harness)
	if screen == null or screen.route_kind != route:
		_issues.append("facility_missing_before_return:%s" % route)
		return false
	var composition := screen.get_node_or_null(^"Composition")
	var returned: AppActionResult
	if composition is CollectionScreen:
		returned = (composition as CollectionScreen).return_to_camp()
	elif composition is CampFacilityScreen:
		returned = (composition as CampFacilityScreen).return_to_camp()
	else:
		_issues.append("facility_composition_type:%s" % route)
		return false
	if not returned.ok:
		_issues.append("facility_return_failed:%s" % route)
		return false
	await process_frame
	await process_frame
	var active := Support.active_screen(_harness)
	if active == null or active.route_kind != &"CAMP_WORLD":
		_issues.append("camp_missing_after_return:%s" % route)
		return false
	return true


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
	var shell := screen.get("_layout_shell") as ProductionLayoutShell
	if shell == null:
		_issues.append("shell_missing:%s:%s" % [route, case_name])
		return
	if route == &"CAMP_WORLD":
		_validate_camp(screen, shell, case_name, ui_scale)
	elif route == &"COLLECTION":
		_validate_collection(screen, shell, case_name, ui_scale)
	else:
		_validate_facility(screen, shell, route, case_name, ui_scale)
	if route in FACILITY_ROUTES:
		_validate_facility_action_band(screen, shell, route, case_name, ui_scale)


func _validate_camp(
	screen: ProductionScreen,
	shell: ProductionLayoutShell,
	case_name: String,
	ui_scale: int
) -> void:
	var center_panel := shell.find_child(
		"CenterRegion", true, false
	) as PanelContainer
	if center_panel == null or center_panel.self_modulate.a != 0.0:
		_issues.append("camp_shell_frame_not_suppressed:%s" % case_name)
	var environment := screen.find_child(
		"CampEnvironmentView", true, false
	) as Control
	var texture := screen.find_child(
		"CampEnvironmentTexture", true, false
	) as TextureRect
	if environment == null or texture == null or texture.texture == null:
		_issues.append("camp_environment_missing:%s" % case_name)
	var markers := screen.find_children("Facility*", "Button", true, false)
	if markers.size() != 5:
		_issues.append("camp_marker_count:%s:%d" % [case_name, markers.size()])
	var factor := float(ui_scale) / 100.0
	for node: Node in markers:
		var marker := node as Button
		if marker == null:
			continue
		if (
			marker.focus_mode != Control.FOCUS_ALL
			or not marker.has_meta(&"action_id")
			or marker.theme_type_variation != &"ExpeditionCampFacilityMarker"
		):
			_issues.append("camp_marker_contract:%s:%s" % [case_name, marker.name])
		if marker.get_global_rect().size.y + 1.0 < 72.0 * factor:
			_issues.append("camp_marker_hit_rect:%s:%s" % [case_name, marker.name])
		if environment != null and not environment.get_global_rect().encloses(
			marker.get_global_rect()
		):
			_issues.append("camp_marker_out_of_bounds:%s:%s" % [case_name, marker.name])
	var context := screen.find_child(
		"CampFacilityContext", true, false
	) as Label
	if (
		context == null
		or context.text.is_empty()
		or context.theme_type_variation != &"ExpeditionCampFooterContext"
	):
		_issues.append("camp_footer_context_missing:%s" % case_name)
	elif not markers.is_empty():
		var marker := markers[markers.size() - 1] as Button
		marker.grab_focus()
		if context.text != marker.text:
			_issues.append("camp_footer_context_not_bound:%s" % case_name)
	var bottom := shell.current_content_rect(
		ProductionLayoutShell.REGION_BOTTOM
	)
	if context != null and not bottom.encloses(context.get_global_rect()):
		_issues.append("camp_footer_context_out_of_bounds:%s" % case_name)
	for action_id: StringName in [&"camp.settings", &"camp.menu"]:
		var button := _action_button(screen, action_id)
		if button == null or not bottom.encloses(button.get_global_rect()):
			_issues.append("camp_footer_action_bounds:%s:%s" % [
				case_name, action_id,
			])


func _validate_facility(
	screen: ProductionScreen,
	shell: ProductionLayoutShell,
	route: StringName,
	case_name: String,
	ui_scale: int
) -> void:
	var left := shell.current_region_rect(ProductionLayoutShell.REGION_LEFT)
	var right := shell.current_region_rect(ProductionLayoutShell.REGION_RIGHT)
	if left.size.x != 0.0 or right.size.x != 0.0:
		_issues.append("facility_route_geometry:%s:%s" % [route, case_name])
	var cards := screen.find_child("FacilityData", true, false) as ItemList
	if cards == null:
		_issues.append("facility_cards_missing:%s:%s" % [route, case_name])
		return
	if (
		cards.theme_type_variation != &"ExpeditionFacilityCardGrid"
		or cards.icon_mode != ItemList.ICON_MODE_TOP
		or cards.focus_mode != Control.FOCUS_ALL
		or cards.get_meta(&"portrait_catalog_error", &"invalid") != &""
	):
		_issues.append("facility_card_contract:%s:%s" % [route, case_name])
	var center := shell.current_content_rect(ProductionLayoutShell.REGION_CENTER)
	if not center.encloses(cards.get_global_rect()):
		_issues.append("facility_cards_out_of_bounds:%s:%s" % [route, case_name])
	var expected_icon := roundi(144.0 * float(ui_scale) / 100.0)
	if cards.fixed_icon_size != Vector2i.ONE * expected_icon:
		_issues.append("facility_card_scale:%s:%s" % [route, case_name])


func _validate_collection(
	screen: ProductionScreen,
	shell: ProductionLayoutShell,
	case_name: String,
	ui_scale: int
) -> void:
	var left := shell.current_region_rect(ProductionLayoutShell.REGION_LEFT)
	var right := shell.current_content_rect(ProductionLayoutShell.REGION_RIGHT)
	var center := shell.current_content_rect(ProductionLayoutShell.REGION_CENTER)
	if left.size.x != 0.0 or right.size.x != ProductionLayoutShell.SIDE_WIDTH - 48.0:
		_issues.append("collection_route_geometry:%s" % case_name)
	var category := screen.find_child("CategorySelector", true, false) as OptionButton
	var search := screen.find_child("SearchInput", true, false) as LineEdit
	var entries := screen.find_child("EntrySelector", true, false) as ItemList
	var compare := screen.find_child("CompareSelector", true, false) as ItemList
	var result := screen.find_child("CompareResult", true, false) as Label
	for control: Control in [category, search, entries]:
		if control == null or not center.encloses(control.get_global_rect()):
			_issues.append("collection_center_bounds:%s" % case_name)
	for control: Control in [compare, result]:
		if control == null or not right.encloses(control.get_global_rect()):
			_issues.append("collection_right_bounds:%s" % case_name)
	if entries == null:
		return
	if (
		entries.icon_mode != ItemList.ICON_MODE_TOP
		or entries.theme_type_variation != &"ExpeditionCollectionCardGrid"
		or entries.focus_mode != Control.FOCUS_ALL
		or entries.get_meta(&"portrait_catalog_error", &"invalid") != &""
	):
		_issues.append("collection_card_contract:%s" % case_name)
	var portrait_count := 0
	for index: int in entries.item_count:
		if entries.get_item_icon(index) != null:
			portrait_count += 1
	if portrait_count == 0:
		_issues.append("collection_portraits_missing:%s" % case_name)
	var expected_icon := roundi(168.0 * float(ui_scale) / 100.0)
	if entries.fixed_icon_size != Vector2i.ONE * expected_icon:
		_issues.append("collection_card_scale:%s" % case_name)


func _validate_facility_action_band(
	screen: ProductionScreen,
	shell: ProductionLayoutShell,
	route: StringName,
	case_name: String,
	_ui_scale: int
) -> void:
	var bottom := shell.current_content_rect(ProductionLayoutShell.REGION_BOTTOM)
	var back := _action_button(screen, &"camp.back")
	if (
		back == null
		or back.focus_mode != Control.FOCUS_ALL
		or not bottom.encloses(back.get_global_rect())
	):
		_issues.append("facility_back_contract:%s:%s" % [route, case_name])
		return
	# set_fixed_min 是骨架 reference 尺寸：UI scale 放大字級與內距，但
	# 固定 action band control 維持 72 reference 高，避免反向撐破底帶。
	if back.get_global_rect().size.y + 1.0 < 72.0:
		_issues.append("facility_back_hit_rect:%s:%s" % [route, case_name])


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
	var viewport_texture := get_root().get_texture()
	var image := (
		viewport_texture.get_image()
		if viewport_texture != null
		else null
	)
	var error := image.save_png(absolute_path) if image != null else ERR_UNAVAILABLE
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
		_issues.append("screenshot_failed:%s:%s:%s" % [
			prefix, case["name"], error,
		])
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
	var expected := _selected_cases.size() * _selected_routes.size()
	var report := {
		"ok": _issues.is_empty() and _reports.size() == expected,
		"exit_code": 0 if _issues.is_empty() else 2,
		"expected_screenshot_count": expected,
		"actual_screenshot_count": _reports.size(),
		"route_count": _selected_routes.size(),
		"matrix_case_count": _selected_cases.size(),
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
