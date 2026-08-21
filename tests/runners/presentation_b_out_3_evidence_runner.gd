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
const REVISION_CASE_NAMES: Array[String] = [
	"720p-ui150",
	"1080p-ui125",
	"1440p-ui150",
]
const UI_REFERENCE_SIZE := Vector2i(1920, 1080)
const EVIDENCE_ROOT := "res://specs/ui-art-refresh/evidence"
const DEFAULT_OUTPUT_DIR := EVIDENCE_ROOT + "/b-out-3"
const ROUTE_COUNT: int = 4


class FakeSettingsPort:
	extends SettingsApplicationPort

	func apply(candidate: SettingsSnapshot) -> SettingsApplicationResult:
		return SettingsApplicationResult.success(candidate)


var _harness: Support.BootHarness
var _reports: Array[Dictionary] = []
var _issues: Array[String] = []
var _synthetic_host: Control
var _revision_only: bool = false


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	_revision_only = OS.get_cmdline_user_args().has("--revision-only")
	var output_dir := _output_directory().trim_suffix("/")
	if output_dir.is_empty() or DirAccess.make_dir_recursive_absolute(
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
	if not await _capture_settings_matrix(output_dir):
		await _finish(output_dir)
		return
	if not await _capture_camp_system_menu_matrix(output_dir):
		await _finish(output_dir)
		return
	_harness.dispose()
	await process_frame
	await process_frame
	await _capture_results_matrix(output_dir, &"RESULTS", "results")
	await _capture_results_matrix(
		output_dir, &"RESULTS_FALLBACK", "results-fallback"
	)
	await _finish(output_dir)


func _capture_settings_matrix(output_dir: String) -> bool:
	var opened := _harness.root.open_settings()
	if not opened.ok:
		_issues.append("settings_route_failed")
		return false
	await process_frame
	await process_frame
	for case: Dictionary in _active_cases():
		_configure_window(case["size"])
		var settings := Support.candidate(int(case["ui"]), &"default")
		settings.locale = &"zh_TW"
		var applied := _harness.root.settings_application_port().apply(settings)
		if not applied.ok:
			_issues.append("settings_apply_failed:%s" % case["name"])
			continue
		await process_frame
		await process_frame
		await process_frame
		var screen := Support.active_screen(_harness)
		if screen == null or screen.route_kind != &"SETTINGS":
			_issues.append("settings_route_mismatch:%s" % case["name"])
			continue
		_validate_settings(screen, String(case["name"]))
		_reports.append(_save_viewport(
			"%s/settings-%s.png" % [output_dir, case["name"]],
			"settings",
			case
		))
	var closed := _harness.root.close_settings()
	if not closed.ok:
		_issues.append("settings_close_failed")
		return false
	await process_frame
	await process_frame
	return true


func _capture_camp_system_menu_matrix(output_dir: String) -> bool:
	var opened := _harness.root.open_camp()
	if not opened.ok:
		_issues.append("camp_route_failed")
		return false
	await process_frame
	await process_frame
	var screen := Support.active_screen(_harness)
	if screen == null or screen.route_kind != &"CAMP_WORLD":
		_issues.append("camp_route_mismatch")
		return false
	if not _revision_only and not screen.open_system_menu():
		_issues.append("camp_system_menu_open_failed")
		return false
	await process_frame
	await process_frame
	for case: Dictionary in _active_cases():
		_configure_window(case["size"])
		var settings := Support.candidate(int(case["ui"]), &"default")
		settings.locale = &"zh_TW"
		var applied := _harness.root.settings_application_port().apply(settings)
		if not applied.ok:
			_issues.append("camp_system_settings_failed:%s" % case["name"])
			continue
		await process_frame
		await process_frame
		await process_frame
		screen = Support.active_screen(_harness)
		if _revision_only:
			_validate_system_menu_entry(screen, String(case["name"]))
		else:
			_validate_system_menu(screen, String(case["name"]))
		var slug := (
			"camp-menu-entry" if _revision_only else "camp-system-menu"
		)
		_reports.append(_save_viewport(
			"%s/%s-%s.png" % [output_dir, slug, case["name"]],
			slug,
			case
		))
	if not _revision_only and screen.system_menu_state() != &"CLOSED":
		screen.close_system_menu()
	await process_frame
	return true


func _capture_results_matrix(
	output_dir: String,
	route: StringName,
	slug: String
) -> void:
	if _synthetic_host != null and is_instance_valid(_synthetic_host):
		_synthetic_host.queue_free()
		await process_frame
	_synthetic_host = Control.new()
	_synthetic_host.name = "BOut3SyntheticHost"
	_synthetic_host.size = Vector2(UI_REFERENCE_SIZE)
	root.add_child(_synthetic_host)
	var screen := ProductionSceneCatalog.new().instantiate(route)
	var snapshot := _results_snapshot()
	if screen == null or snapshot == null:
		_issues.append("results_fixture_failed:%s" % route)
		return
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var localized := _localized()
	var bind_error := screen.bind(StagedScreenContext.new(
		route, snapshot, null, &"zh_TW", localized
	))
	if not bind_error.is_empty():
		_issues.append("results_bind_failed:%s:%s" % [route, bind_error])
		return
	screen.bind_system_menu_settings(SettingsSnapshot.new(), FakeSettingsPort.new())
	var registry := LiveScreenLeaseRegistry.new()
	var lease := registry.activate(AppStateMachine.State.RESULTS, 1)
	var actions: Dictionary = {
		&"results.retry": Callable(self, "_noop_action"),
		&"results.camp": Callable(self, "_noop_action"),
		&"results.menu": Callable(self, "_noop_action"),
	}
	var live := ProductionLiveScreenContext.new(
		route,
		snapshot,
		null,
		ProductionScreenActionPort.new(lease, registry, actions)
	)
	var live_error := screen.prepare_live_binding(live)
	if not live_error.is_empty():
		_issues.append("results_live_failed:%s:%s" % [route, live_error])
		return
	_synthetic_host.add_child(screen)
	screen.activate_live()
	await process_frame
	await process_frame
	for case: Dictionary in _active_cases():
		_configure_window(case["size"])
		if not ExpeditionThemeRuntime.new().apply(screen, int(case["ui"])):
			_issues.append("results_theme_failed:%s:%s" % [route, case["name"]])
			continue
		await process_frame
		await process_frame
		await process_frame
		_validate_results(screen, route, String(case["name"]))
		_reports.append(_save_viewport(
			"%s/%s-%s.png" % [output_dir, slug, case["name"]],
			slug,
			case
		))


func _validate_settings(screen: ProductionScreen, case_name: String) -> void:
	var shell := screen.get("_layout_shell") as ProductionLayoutShell
	var composition := screen.get_node_or_null(^"Composition") as Control
	var actions := screen.get_node_or_null(^"Actions") as Control
	if shell == null or composition == null or actions == null:
		_issues.append("settings_shell_missing:%s" % case_name)
		return
	if (
		shell.current_region_rect(ProductionLayoutShell.REGION_LEFT).size.x != 0.0
		or shell.current_region_rect(ProductionLayoutShell.REGION_RIGHT).size.x != 0.0
	):
		_issues.append("settings_side_regions_nonzero:%s" % case_name)
	if not shell.current_content_rect(
		ProductionLayoutShell.REGION_CENTER
	).grow(1.0).encloses(composition.get_global_rect()):
		_issues.append("settings_composition_out_of_bounds:%s" % case_name)
	if not shell.current_content_rect(
		ProductionLayoutShell.REGION_BOTTOM
	).grow(1.0).encloses(actions.get_global_rect()):
		_issues.append("settings_actions_out_of_bounds:%s" % case_name)
	var scroll := composition.get_node_or_null(
		^"SettingsScroll"
	) as ScrollContainer
	if scroll == null or not is_equal_approx(
		scroll.get_rect().end.y, composition.size.y
	):
		_issues.append("settings_scroll_not_full_height:%s" % case_name)
	for required: String in [
		"LocaleRow", "AccessibilityDivider", "AudioDivider",
	]:
		if screen.find_child(required, true, false) == null:
			_issues.append("settings_section_missing:%s:%s" % [case_name, required])


func _validate_system_menu(screen: ProductionScreen, case_name: String) -> void:
	if screen == null or screen.route_kind != &"CAMP_WORLD":
		_issues.append("camp_system_route_missing:%s" % case_name)
		return
	var overlay := screen.system_menu_overlay()
	if overlay == null or overlay.state_name() != &"ROOT":
		_issues.append("camp_system_root_missing:%s" % case_name)
		return
	var panel := overlay.find_child("SystemMenuRoot", true, false) as Control
	if panel == null or not Rect2(
		Vector2.ZERO, Vector2(UI_REFERENCE_SIZE)
	).encloses(panel.get_global_rect()):
		_issues.append("camp_system_panel_out_of_bounds:%s" % case_name)
	var controls := overlay.active_focus_controls()
	if controls.size() < 3:
		_issues.append("camp_system_focus_controls_missing:%s" % case_name)


func _validate_system_menu_entry(
	screen: ProductionScreen,
	case_name: String
) -> void:
	if screen == null or screen.route_kind != &"CAMP_WORLD":
		_issues.append("camp_menu_entry_route_missing:%s" % case_name)
		return
	var button := screen.system_menu_button()
	if button == null:
		_issues.append("camp_menu_entry_missing:%s" % case_name)
		return
	if button.text != "選單" or StringName(
		button.get_meta(&"localization_key", &"")
	) != &"system_menu.open":
		_issues.append("camp_menu_entry_semantics:%s" % case_name)
	var shell := screen.get("_layout_shell") as ProductionLayoutShell
	# SystemMenuButton lives directly under the full-rect overlay host, whose
	# origin is the ProductionScreen reference origin.
	var button_rect := Rect2(button.position, button.size)
	if shell == null or not shell.current_region_rect(
		ProductionLayoutShell.REGION_TOP
	).grow(1.0).encloses(button_rect):
		_issues.append("camp_menu_entry_out_of_bounds:%s" % case_name)
	var metrics := screen.find_child("CampMetrics", true, false) as Control
	if metrics == null or metrics.get_rect().intersects(button_rect):
		_issues.append("camp_menu_entry_overlaps_metrics:%s" % case_name)


func _validate_results(
	screen: ProductionScreen,
	route: StringName,
	case_name: String
) -> void:
	var shell := screen.get("_layout_shell") as ProductionLayoutShell
	var composition := screen.get_node_or_null(
		^"Composition"
	) as ResultsScreenComposition
	if shell == null or composition == null:
		_issues.append("results_shell_missing:%s:%s" % [route, case_name])
		return
	var center := shell.current_content_rect(
		ProductionLayoutShell.REGION_CENTER
	).grow(1.0)
	var cards: Array[Control] = []
	for value_name: StringName in [
		&"Outcome", &"Reward", &"Profile", &"Receipt", &"Digest",
	]:
		var card := composition.get_node_or_null(
			NodePath("%sCard" % String(value_name))
		) as Control
		var label := composition.get_node_or_null(
			NodePath("%sValue" % String(value_name))
		) as Label
		if value_name == &"Receipt":
			if (
				card == null
				or label == null
				or card.visible
				or label.visible
				or not label.text.is_empty()
			):
				_issues.append("results_receipt_not_hidden:%s:%s" % [
					route, case_name,
				])
			continue
		if card == null or label == null or label.text.is_empty():
			_issues.append("results_card_missing:%s:%s:%s" % [
				route, case_name, value_name,
			])
			continue
		if not center.encloses(card.get_global_rect()):
			_issues.append("results_card_out_of_bounds:%s:%s:%s" % [
				route, case_name, value_name,
			])
		if not card.get_global_rect().encloses(label.get_global_rect()):
			_issues.append("results_value_out_of_card:%s:%s:%s" % [
				route, case_name, value_name,
			])
		cards.append(card)
		if value_name in [&"Reward", &"Profile"]:
			var metric_label := composition.get_node_or_null(
				NodePath("%sLabel" % String(value_name))
			) as Label
			if (
				metric_label == null
				or metric_label.text.is_empty()
				or not card.get_global_rect().encloses(
					metric_label.get_global_rect()
				)
			):
				_issues.append("results_metric_label_invalid:%s:%s:%s" % [
					route, case_name, value_name,
				])
	for left_index: int in cards.size():
		for right_index: int in range(left_index + 1, cards.size()):
			if cards[left_index].get_global_rect().intersects(
				cards[right_index].get_global_rect()
			):
				_issues.append("results_card_overlap:%s:%s:%s:%s" % [
					route,
					case_name,
					cards[left_index].name,
					cards[right_index].name,
				])


func _noop_action() -> AppActionResult:
	return AppActionResult.success()


func _results_snapshot() -> ResultsPresentationSnapshot:
	var profile := SaveRootFixture.create_valid_root().profile
	profile.meta_currency = 138
	var run_id: StringName = &"run.b_out_3_visual"
	var key_result := RuntimeKeySchemaRegistry.new().build_settlement_receipt(run_id)
	if not key_result.ok:
		return null
	var receipt := SettlementReceiptState.new(
		key_result.key_state as SettlementReceiptKeyState,
		SettlementReceiptState.Outcome.COMPLETED,
		42,
		"receipt.payload.b_out_3_visual"
	)
	profile.settlement_receipts.append(receipt)
	return ResultsPresentationSnapshot.capture(
		profile, receipt, run_id, "a".repeat(64), true
	)


func _localized() -> Dictionary:
	return {
		&"screen.results.title": "遠征結算",
		&"screen.results_fallback.title": "遠征結算",
		&"screen.run_container.title": "遠征",
		&"system_menu.open": "選單",
		&"menu.continue": "繼續遠征",
		&"menu.settings": "設定",
		&"run.menu": "返回主選單",
		&"menu.exit": "離開",
		&"run.menu.status": "返回主選單？",
		&"run.menu.confirm": "確認返回",
		&"run.menu.cancel": "取消",
		&"menu.exit.status": "確定要離開遊戲？",
		&"menu.exit.confirm": "確認離開",
		&"menu.exit.cancel": "取消",
		&"settings.apply": "套用",
		&"settings.back": "返回",
		&"results.retry": "重試顯示",
		&"results.camp": "返回營地",
		&"results.menu": "返回主選單",
		&"results.metric.currency_delta": "本次貨幣獎勵",
		&"results.metric.profile_currency": "目前持有貨幣",
		&"results.outcome.completed": "遠征完成",
	}


func _configure_window(size: Vector2i) -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	root.content_scale_size = UI_REFERENCE_SIZE
	root.size = size


func _save_viewport(
	path: String,
	prefix: String,
	case: Dictionary
) -> Dictionary:
	var absolute_path := ProjectSettings.globalize_path(path)
	var viewport_texture := root.get_texture()
	var image := (
		viewport_texture.get_image() if viewport_texture != null else null
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


func _active_cases() -> Array[Dictionary]:
	var active: Array[Dictionary] = []
	for case: Dictionary in CASES:
		if (
			not _revision_only
			or String(case["name"]) in REVISION_CASE_NAMES
		):
			active.append(case)
	return active


func _finish(output_dir: String) -> void:
	var expected := _active_cases().size() * ROUTE_COUNT
	var hashes: Dictionary = {}
	for screenshot: Dictionary in _reports:
		hashes[String(screenshot.get("sha256", ""))] = true
	var report := {
		"ok": _issues.is_empty() and _reports.size() == expected,
		"exit_code": 0 if _issues.is_empty() else 2,
		"expected_screenshot_count": expected,
		"actual_screenshot_count": _reports.size(),
		"route_count": ROUTE_COUNT,
		"matrix_case_count": _active_cases().size(),
		"revision_only": _revision_only,
		"unique_sha256_count": hashes.size(),
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
