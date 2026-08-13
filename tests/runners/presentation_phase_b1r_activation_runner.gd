extends SceneTree

const OUTPUT_DEFAULT := "res://specs/ui-art-refresh/evidence/phase-b1r"

var _issues: Array[String] = []


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var output_dir := _argument("--output-dir=", OUTPUT_DEFAULT).trim_suffix("/")
	var expected := _argument("--expected-diagnostic=", "absent")
	var absolute_output := ProjectSettings.globalize_path(output_dir)
	if DirAccess.make_dir_recursive_absolute(absolute_output) != OK:
		quit(3)
		return
	get_root().content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	get_root().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	get_root().content_scale_size = Vector2i(1280, 720)
	get_root().size = Vector2i(1280, 720)
	var scene := load("res://app/main.tscn") as PackedScene
	var main := scene.instantiate() if scene != null else null
	if main == null:
		_issues.append("main_scene_missing")
		_finish(output_dir, expected, null, null)
		return
	get_root().add_child(main)
	var app_root := main.get_node_or_null(^"AppRoot") as ApplicationRoot
	for _frame: int in 240:
		if app_root != null and app_root.is_booted():
			break
		await process_frame
	if app_root == null or not app_root.is_booted():
		_issues.append("app_root_boot_failed")
		_finish(output_dir, expected, app_root, null)
		return
	var opened := app_root.open_settings()
	if opened == null or not opened.ok:
		_issues.append("settings_route_failed")
		_finish(output_dir, expected, app_root, null)
		return
	await process_frame
	await process_frame
	var screen := _active_screen(app_root)
	var toggle := screen.find_child("ReducedMotion", true, false) as CheckButton if screen != null else null
	if toggle == null:
		_issues.append("reduced_motion_toggle_missing")
	else:
		toggle.button_pressed = not toggle.button_pressed
		toggle.toggled.emit(toggle.button_pressed)
	var apply_button := _action_button(screen, &"settings.apply")
	if apply_button == null:
		_issues.append("settings_apply_button_missing")
	else:
		apply_button.pressed.emit()
	await process_frame
	await process_frame
	await process_frame
	_finish(output_dir, expected, app_root, screen)


func _finish(
	output_dir: String,
	expected: String,
	app_root: ApplicationRoot,
	screen: ProductionScreen
) -> void:
	var status := screen.status_report() if screen != null else {}
	var message := screen.status_message_text() if screen != null else ""
	var source_code := String(status.get("source_code", ""))
	var diagnostic_visible := not message.is_empty()
	var viewport_report := _viewport_report(app_root)
	if expected == "present" and not diagnostic_visible:
		_issues.append("expected_diagnostic_missing")
	if expected == "absent" and diagnostic_visible:
		_issues.append("unexpected_diagnostic_visible:%s" % source_code)
	var screenshot_path := "%s/activation-%s-real-machine.png" % [output_dir, expected]
	var absolute_screenshot := ProjectSettings.globalize_path(screenshot_path)
	var image := get_root().get_texture().get_image()
	var image_error := image.save_png(absolute_screenshot)
	if image_error != OK:
		_issues.append("screenshot_failed:%s" % image_error)
	var report := {
		"ok": _issues.is_empty(),
		"fresh_process": true,
		"headless": DisplayServer.get_name() == "headless",
		"display_server": DisplayServer.get_name(),
		"locale": TranslationServer.get_locale(),
		"expected_diagnostic": expected,
		"single_toggle": "reduced_motion",
		"diagnostic_visible": diagnostic_visible,
		"visible_message": message,
		"source_code": source_code,
		"status_report": status,
		"audio_buses": _audio_bus_names(),
		"viewport_runtime": viewport_report,
		"app_booted": app_root != null and app_root.is_booted(),
		"screenshot": screenshot_path,
		"screenshot_sha256": FileAccess.get_sha256(absolute_screenshot),
		"issues": _issues,
	}
	_write_json("%s/activation-%s-real-machine.json" % [output_dir, expected], report)
	if app_root != null:
		app_root.get_parent().queue_free()
	await process_frame
	quit(0 if _issues.is_empty() else 2)


func _active_screen(app_root: ApplicationRoot) -> ProductionScreen:
	if app_root == null:
		return null
	var host := app_root.get_node_or_null(^"UiLayer/UiRoot/PresentationHost")
	if host == null:
		return null
	for child: Node in host.get_children():
		if child is ProductionScreen:
			return child as ProductionScreen
	return null


func _action_button(screen: ProductionScreen, action_id: StringName) -> Button:
	if screen == null:
		return null
	for node: Node in screen.find_children("*", "Button", true, false):
		var button := node as Button
		if button != null and StringName(button.get_meta(&"action_id", &"")) == action_id:
			return button
	return null


func _audio_bus_names() -> Array[String]:
	var result: Array[String] = []
	for index: int in AudioServer.bus_count:
		result.append(AudioServer.get_bus_name(index))
	return result


func _viewport_report(app_root: ApplicationRoot) -> Dictionary:
	var runtime := app_root.get_node_or_null(^"ViewportCoordinator") if app_root != null else null
	if runtime == null:
		return {"runtime_present": false}
	var report := {
		"runtime_present": true,
		"inside_tree": runtime.is_inside_tree(),
		"window_size": runtime.call(&"window_size") if runtime.has_method(&"window_size") else Vector2i.ZERO,
	}
	for property_name: StringName in [
		&"world_container_path",
		&"world_viewport_path",
		&"ui_layer_path",
		&"ui_root_path",
		&"presentation_host_path",
	]:
		var path := runtime.get(property_name) as NodePath
		report[String(property_name)] = String(path)
		report["%s_resolves" % property_name] = runtime.get_node_or_null(path) != null
	if runtime.has_method(&"synchronize"):
		report["direct_probe"] = StringName(runtime.call(
			&"synchronize",
			Vector2i(get_root().get_visible_rect().size)
		))
	return report


func _argument(prefix: String, fallback: String) -> String:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with(prefix):
			return argument.trim_prefix(prefix)
	return fallback


func _write_json(path: String, value: Dictionary) -> void:
	var file := FileAccess.open(ProjectSettings.globalize_path(path), FileAccess.WRITE)
	if file == null:
		_issues.append("report_write_failed:%s" % path)
		return
	file.store_string(JSON.stringify(value, "\t"))
	file.close()
