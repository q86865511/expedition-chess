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
const SCALE_CASES: Array[Dictionary] = [
	{"name": "720p-ui100", "size": Vector2i(1280, 720), "ui": 100},
	{"name": "720p-ui125", "size": Vector2i(1280, 720), "ui": 125},
	{"name": "720p-ui150", "size": Vector2i(1280, 720), "ui": 150},
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
	for case: Dictionary in SCALE_CASES:
		await _capture(output_dir, &"MENU_MAIN", "menu-main", case)
	var settings_opened := _harness.root.open_settings()
	if not settings_opened.ok:
		_issues.append("settings_route_failed")
		await _finish(output_dir)
		return
	await process_frame
	await process_frame
	for case: Dictionary in SCALE_CASES:
		await _capture_settings_after_apply(output_dir, case)
	var settings_closed := _harness.root.close_settings()
	if not settings_closed.ok:
		_issues.append("settings_close_failed")
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
	await _capture_prepare_groups(output_dir)
	await _capture_scale_rebuild(output_dir)
	await _capture_node_choice(output_dir)
	await _capture_status_band(output_dir)
	await _capture_focus(output_dir)
	await _finish(output_dir)


func _capture_settings_after_apply(
	output_dir: String,
	case: Dictionary
) -> void:
	_configure_window(case["size"])
	var screen := Support.active_screen(_harness)
	var composition := (
		screen.get_node_or_null(^"Composition") as SettingsScreenComposition
		if screen != null and screen.route_kind == &"SETTINGS"
		else null
	)
	if composition == null:
		_issues.append("settings_composition_missing:%s" % case["name"])
		return
	var candidate := composition.settings_draft()
	candidate.locale = &"zh_TW"
	candidate.ui_scale_percent = int(case["ui"])
	var edit_error := composition.replace_settings_draft(candidate)
	var apply_button := _action_button(screen, &"settings.apply")
	if not edit_error.is_empty() or apply_button == null:
		_issues.append("settings_prepare_apply_failed:%s" % case["name"])
		return
	apply_button.pressed.emit()
	await process_frame
	await process_frame
	await process_frame
	if screen.last_control_result() == null or not bool(screen.last_control_result().ok):
		_issues.append("settings_live_apply_failed:%s" % case["name"])
		return
	_validate_action_buttons(screen, String(case["name"]))
	_reports.append(_save_viewport(
		"%s/settings-after-apply-%s.png" % [output_dir, case["name"]],
		"settings-after-apply",
		case
	))


func _capture_prepare_groups(output_dir: String) -> void:
	var screen := Support.active_screen(_harness)
	var selector := screen.find_child(
		"PrepareActionGroupSelector", true, false
	) as OptionButton if screen != null else null
	if selector == null:
		_issues.append("prepare_group_selector_missing")
		return
	for case: Dictionary in SCALE_CASES:
		_configure_window(case["size"])
		var settings := Support.candidate(int(case["ui"]), &"default")
		settings.locale = &"zh_TW"
		var applied := _harness.root.settings_application_port().apply(settings)
		if not applied.ok:
			_issues.append("prepare_group_scale_failed:%s" % case["name"])
			continue
		await process_frame
		await process_frame
		for group_index: int in selector.item_count:
			selector.select(group_index)
			selector.item_selected.emit(group_index)
			await process_frame
			await process_frame
			_validate_action_buttons(
				screen,
				"%s-group-%d" % [case["name"], group_index]
			)
			var group_id := String(
				ProductionScreen.PREPARE_ACTION_GROUPS[group_index]["id"]
			).replace("_", "-")
			_reports.append(_save_viewport(
				"%s/prepare-group-%s-%s.png" % [
					output_dir, group_id, case["name"],
				],
				"prepare-group-%s" % group_id,
				case
			))


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
	_validate_action_buttons(screen, "%s:%s" % [prefix, case["name"]])
	if expected_route == &"SETTINGS":
		_validate_settings_layout(screen, String(case["name"]))
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
	var center_scroll := screen.find_child(
		"PrepareCenterScroll", true, false
	) as ScrollContainer
	var center_rect := (
		center_scroll.get_global_rect()
		if center_scroll != null
		else shell.current_region_rect(ProductionLayoutShell.REGION_CENTER)
	)
	var status_rect := shell.current_region_rect(ProductionLayoutShell.REGION_STATUS)
	var bottom_rect := shell.current_region_rect(ProductionLayoutShell.REGION_BOTTOM)
	for node_name: String in [
		"BoardGrid",
		"BenchRow",
		"InventorySelector",
	]:
		var control := screen.find_child(node_name, true, false) as Control
		if control == null:
			_issues.append("prepare_region_control_missing:%s:%s" % [case_name, node_name])
			continue
		var control_rect := control.get_global_rect()
		if not shell.is_status_visible() and not center_rect.encloses(control_rect):
			_issues.append("prepare_center_overflow:%s:%s:%s" % [case_name, node_name, control_rect])
		if (
			not shell.is_status_visible()
			and control_rect.intersects(bottom_rect)
		):
			_issues.append("prepare_center_cross_region:%s:%s" % [case_name, node_name])
	var bottom_panel := screen.find_child("BottomRegion", true, false) as Control
	var safe_rect := Rect2(Vector2(24.0, 24.0), Vector2(1232.0, 672.0))
	if bottom_panel == null or not safe_rect.encloses(bottom_panel.get_global_rect()):
		_issues.append("prepare_bottom_outside_safe_area:%s:%s" % [
			case_name,
			bottom_panel.get_global_rect() if bottom_panel != null else Rect2(),
		])


func _validate_action_buttons(screen: Control, case_name: String) -> void:
	var canvas := Rect2(Vector2.ZERO, Vector2(1280.0, 720.0))
	for node: Node in screen.find_children("*", "Button", true, false):
		var button := node as Button
		if (
			button == null
			or not button.is_visible_in_tree()
			or not button.has_meta(&"action_id")
		):
			continue
		var text_width := _button_text_width(button)
		var rect := button.get_global_rect()
		if rect.size.x + 0.5 < text_width:
			_issues.append("action_text_clipped:%s:%s:%s<%s" % [
				case_name,
				button.get_meta(&"action_id"),
				rect.size.x,
				text_width,
			])
		if _ancestor_scroll_container(button) == null and not canvas.encloses(rect):
			_issues.append("action_outside_canvas:%s:%s:%s" % [
				case_name, button.get_meta(&"action_id"), rect,
			])


func _validate_settings_layout(screen: Control, case_name: String) -> void:
	var title := screen.get_node_or_null(^"Label") as Label
	var locale_row := screen.find_child("LocaleRow", true, false) as Control
	var locale_editor := screen.find_child("Locale", true, false) as Control
	var action_gap := screen.get_node_or_null(^"SettingsActionGap") as Control
	var actions := screen.get_node_or_null(^"Actions") as Control
	if (
		title == null
		or locale_row == null
		or locale_editor == null
		or action_gap == null
		or actions == null
	):
		_issues.append("settings_layout_nodes_missing:%s" % case_name)
		return
	if title.get_global_rect().intersects(locale_row.get_global_rect()):
		_issues.append("settings_title_locale_overlap:%s" % case_name)
	if not locale_editor.tooltip_text.is_empty():
		_issues.append("settings_duplicate_hover_text:%s" % case_name)
	if not is_equal_approx(
		action_gap.get_global_rect().end.y,
		actions.get_global_rect().position.y
	):
		_issues.append("settings_action_gap_not_reserved:%s" % case_name)


func _button_text_width(button: Button) -> float:
	if button == null or button.text.is_empty():
		return 0.0
	var widest := 0.0
	var font := button.get_theme_font(&"font")
	var size := button.get_theme_font_size(&"font_size")
	for line: String in button.text.split("\n"):
		widest = maxf(widest, font.get_string_size(
			line, HORIZONTAL_ALIGNMENT_LEFT, -1, size
		).x)
	return widest


func _ancestor_scroll_container(control: Control) -> ScrollContainer:
	var ancestor := control.get_parent()
	while ancestor != null:
		if ancestor is ScrollContainer:
			return ancestor as ScrollContainer
		ancestor = ancestor.get_parent()
	return null


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
	var baseline_settings := Support.candidate(100, &"default")
	baseline_settings.locale = &"zh_TW"
	var baseline_applied := _harness.root.settings_application_port().apply(
		baseline_settings
	)
	await process_frame
	await process_frame
	var baseline_screen := Support.active_screen(_harness)
	var baseline_start := _action_button(baseline_screen, &"prepare.start")
	var recorded_100_minimum := (
		baseline_start.custom_minimum_size
		if baseline_start != null
		else Vector2.ZERO
	)
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
	var restored := _harness.root.settings_application_port().apply(
		baseline_settings
	)
	await process_frame
	await process_frame
	var screen := Support.active_screen(_harness)
	var start := _action_button(screen, &"prepare.start")
	var report := {
		"ok": (
			baseline_applied.ok
			and restored.ok
			and start != null
			and recorded_100_minimum.x > 8.0
			and start.custom_minimum_size == recorded_100_minimum
			and start.get_global_rect().size.x >= _button_text_width(start)
		),
		"sequence": [150, "rebuild", 100],
		"recorded_100_minimum": recorded_100_minimum,
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
		"shop_card_count": 0,
		"disabled_shop_card_count": 0,
	}
	for node: Node in screen.find_children("ShopCard*", "Button", true, false):
		var card := node as Button
		if card == null or not card.has_meta(&"shop_offer_id"):
			continue
		scenario["shop_card_count"] = int(scenario["shop_card_count"]) + 1
		if card.disabled:
			scenario["disabled_shop_card_count"] = int(
				scenario["disabled_shop_card_count"]
			) + 1
	scenario["ok"] = bool(scenario["ok"]) and (
		int(scenario["shop_card_count"]) == 5
		and int(scenario["disabled_shop_card_count"]) == 5
	)
	if not bool(scenario["ok"]):
		_issues.append("node_choice_layout_failed:%s" % compose_error)
	_write_json("%s/node-choice-layout-report.json" % output_dir, scenario)
	for case: Dictionary in SCALE_CASES:
		_configure_window(case["size"])
		var settings := Support.candidate(int(case["ui"]), &"default")
		settings.locale = &"zh_TW"
		_harness.root.settings_application_port().apply(settings)
		await process_frame
		await process_frame
		_validate_prepare_content_regions(screen, "node-choice-%s" % case["name"])
		_reports.append(_save_viewport(
			"%s/prepare-node-choice-%s.png" % [output_dir, case["name"]],
			"prepare-node-choice",
			case
		))
	var begin := _action_button(screen, &"choice.begin")
	if begin == null:
		_issues.append("node_choice_modal_trigger_missing")
		return
	begin.pressed.emit()
	await process_frame
	await process_frame
	var modal := screen.get_node_or_null(^"NodeChoiceConfirmation") as PanelContainer
	if modal == null or not screen.is_confirmation_modal_open():
		_issues.append("node_choice_modal_missing")
		return
	var modal_style := modal.get_theme_stylebox(&"panel") as StyleBoxFlat
	if modal_style == null or modal_style.bg_color.a < 0.99:
		_issues.append("node_choice_modal_not_opaque")
	for case: Dictionary in SCALE_CASES:
		_configure_window(case["size"])
		var modal_settings := Support.candidate(int(case["ui"]), &"default")
		modal_settings.locale = &"zh_TW"
		_harness.root.settings_application_port().apply(modal_settings)
		await process_frame
		await process_frame
		_reports.append(_save_viewport(
			"%s/prepare-node-choice-modal-%s.png" % [output_dir, case["name"]],
			"prepare-node-choice-modal",
			case
		))
	screen.call(&"_close_confirmation_modal")
	await process_frame
	var run_menu := _action_button(screen, &"run.menu")
	if run_menu == null:
		_issues.append("return_modal_trigger_missing")
		return
	run_menu.pressed.emit()
	await process_frame
	await process_frame
	var return_modal := screen.get_node_or_null(
		^"RunMenuConfirmation"
	) as PanelContainer
	if return_modal == null or not screen.is_confirmation_modal_open():
		_issues.append("return_modal_missing")
		return
	var return_style := return_modal.get_theme_stylebox(&"panel") as StyleBoxFlat
	if return_style == null or return_style.bg_color.a < 0.99:
		_issues.append("return_modal_not_opaque")
	for case: Dictionary in SCALE_CASES:
		_configure_window(case["size"])
		var return_settings := Support.candidate(int(case["ui"]), &"default")
		return_settings.locale = &"zh_TW"
		_harness.root.settings_application_port().apply(return_settings)
		await process_frame
		await process_frame
		_reports.append(_save_viewport(
			"%s/prepare-return-modal-%s.png" % [output_dir, case["name"]],
			"prepare-return-modal",
			case
		))
	screen.call(&"_close_confirmation_modal")
	await process_frame


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
		"ok": (
			not screen.status_message_text().is_empty()
			and shell.is_status_visible()
			and not status_rect.intersects(center_rect)
		),
		"message": screen.status_message_text(),
		"status_rect": status_rect,
		"content_rect": center_rect,
	}
	if not bool(report["ok"]):
		_issues.append("status_band_not_reserved")
	_write_json("%s/status-band-report.json" % output_dir, report)
	for case: Dictionary in SCALE_CASES:
		_configure_window(case["size"])
		var settings := Support.candidate(int(case["ui"]), &"default")
		settings.locale = &"zh_TW"
		_harness.root.settings_application_port().apply(settings)
		await process_frame
		await process_frame
		_validate_prepare_content_regions(screen, "status-%s" % case["name"])
		_reports.append(_save_viewport(
			"%s/prepare-status-message-%s.png" % [output_dir, case["name"]],
			"prepare-status",
			case
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
	return "res://specs/ui-art-refresh/evidence/phase-b1r2"


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
