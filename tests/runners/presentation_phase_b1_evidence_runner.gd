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
	await _capture_focus(output_dir)
	await _capture_activation_probe(output_dir)
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
	var path := "%s/%s-%s.png" % [output_dir, prefix, case["name"]]
	_reports.append(_save_viewport(path, prefix, case))


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


func _capture_activation_probe(output_dir: String) -> void:
	var before := _legacy_english_probe()
	var before_screen := Support.active_screen(_harness)
	var injected := SettingsApplicationResult.committed_presentation_failure(
		Support.candidate(100, &"default"),
		DiagnosticError.new(
			&"ACCESSIBILITY_REQUIRED_GLYPH_MISSING",
			&"error.settings.activation_diagnostic"
		)
	)
	if before_screen != null:
		before_screen.report_composition_result(injected)
	await process_frame
	await process_frame
	var before_status := (
		before_screen.status_report()
		if before_screen != null
		else {}
	)
	before["fault_injection_status"] = before_status
	before["visible_message"] = (
		before_screen.status_message_text()
		if before_screen != null
		else ""
	)
	if before_screen == null or String(before["visible_message"]).is_empty():
		_issues.append("activation_fault_injection_not_visible")
	var before_case := {
		"name": "activation-before-fault-injection",
		"size": Vector2i(1280, 720),
		"ui": 100,
	}
	_reports.append(_save_viewport(
		"%s/activation-before-fault-injection.png" % output_dir,
		"activation-before",
		before_case
	))
	_write_text(
		"%s/activation-before.log" % output_dir,
		"locale=%s\nsource_code=%s\nrequired_glyph_count=%s\nvisible_message=%s\n" % [
			before.get("locale", ""),
			before.get("source_code", ""),
			before.get("required_glyph_count", 0),
			before.get("visible_message", ""),
		]
	)
	var seed_error := Support.seed_committed_combat_phase(_harness)
	if not seed_error.is_empty():
		_issues.append("combat_seed_failed:%s" % seed_error)
		_write_json("%s/activation-before-after.json" % output_dir, {"before": before})
		return
	var gameplay_storage := _harness.gameplay_storage
	var settings_storage := _harness.settings_storage
	_harness.dispose()
	await process_frame
	await process_frame
	await process_frame
	_harness = Support.boot_runtime(self, gameplay_storage, settings_storage)
	await process_frame
	await process_frame
	var continued := Support.continue_to_run_combat(_harness)
	if not bool(continued.get("ok", false)):
		_issues.append("combat_continue_failed:%s" % continued.get("error", &""))
		_write_json("%s/activation-before-after.json" % output_dir, {"before": before})
		return
	await process_frame
	await process_frame
	var settings := Support.candidate(125, &"default")
	settings.locale = &"en"
	var applied := _harness.root.settings_application_port().apply(settings)
	await process_frame
	await process_frame
	var runtime := Support.accessibility_host(_harness)
	var runtime_report := runtime.runtime_accessibility_report() if runtime != null else null
	var after := {
		"ok": applied.ok,
		"committed": applied.committed,
		"presentation_ok": applied.presentation_ok,
		"source_code": (
			String(applied.error.source_code)
			if applied.error != null
			else ""
		),
		"locale": String(runtime_report.cjk_locale) if runtime_report != null else "",
		"font_source": String(runtime_report.cjk_font_source) if runtime_report != null else "",
		"fallback_used": runtime_report.cjk_fallback_used if runtime_report != null else true,
		"readable": runtime_report.cjk_readable if runtime_report != null else false,
		"missing_glyphs": runtime_report.cjk_missing_glyphs if runtime_report != null else [],
	}
	if not applied.ok or not applied.presentation_ok or runtime_report == null or not runtime_report.ok:
		_issues.append("english_activation_still_falls_back")
	var after_case := {
		"name": "activation-after-real-apply",
		"size": Vector2i(1280, 720),
		"ui": 125,
	}
	_reports.append(_save_viewport(
		"%s/activation-after-real-apply.png" % output_dir,
		"activation-after",
		after_case
	))
	_write_text(
		"%s/activation-after.log" % output_dir,
		"locale=%s\nsource_code=%s\nfont_source=%s\nfallback_used=%s\nreadable=%s\npresentation_ok=%s\n" % [
			after.get("locale", ""),
			after.get("source_code", ""),
			after.get("font_source", ""),
			after.get("fallback_used", true),
			after.get("readable", false),
			after.get("presentation_ok", false),
		]
	)
	_write_json("%s/activation-before-after.json" % output_dir, {
		"before": before,
		"after": after,
	})


func _legacy_english_probe() -> Dictionary:
	var text := "Combat rules remain visible while effects are reduced."
	var font := SystemFont.new()
	font.font_names = PackedStringArray(LocalizedTypographyPolicy.SYSTEM_FONT_NAMES)
	font.allow_system_fallback = true
	var required_cjk: Array[int] = []
	for index: int in text.length():
		var codepoint := text.unicode_at(index)
		if (
			(codepoint >= 0x3400 and codepoint <= 0x4DBF)
			or (codepoint >= 0x4E00 and codepoint <= 0x9FFF)
			or (codepoint >= 0xF900 and codepoint <= 0xFAFF)
		):
			required_cjk.append(codepoint)
	var measured := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 24)
	return {
		"algorithm": "legacy_cjk_only_required_set",
		"locale": "en",
		"required_glyph_count": required_cjk.size(),
		"measured_width": measured.x,
		"measured_height": measured.y,
		"would_report_ok": not required_cjk.is_empty() and measured.x > 0.0 and measured.y > 0.0,
		"source_code": "ACCESSIBILITY_REQUIRED_GLYPH_MISSING",
	}


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


func _write_text(path: String, value: String) -> void:
	var file := FileAccess.open(ProjectSettings.globalize_path(path), FileAccess.WRITE)
	if file == null:
		_issues.append("log_write_failed:%s" % path)
		return
	file.store_string(value)
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
