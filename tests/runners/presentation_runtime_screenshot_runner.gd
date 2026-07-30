extends SceneTree

const FIXTURE_PATH := \
	"res://tests/fixtures/presentation_runtime/runtime_probe.tscn"
const WORLD_HOST_PATH := \
	"res://presentation/viewport/world_viewport_host.gd"
const UI_SCALE_ROOT_PATH := \
	"res://presentation/viewport/ui_scale_root.gd"
const RENDERER_PATH := \
	"res://presentation/accessibility/accessibility_runtime_renderer.gd"
const RESOLUTIONS: Array[Vector2i] = [
	Vector2i(1280, 720),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440),
]
const COLOR_MODES: Array[StringName] = [
	&"standard",
	&"protanopia",
	&"deuteranopia",
	&"tritanopia",
]


func _initialize() -> void:
	call_deferred(&"_capture_matrix")


func _capture_matrix() -> void:
	var output_dir := _output_directory()
	var issues: Array[String] = []
	for path: String in [FIXTURE_PATH, WORLD_HOST_PATH, UI_SCALE_ROOT_PATH, RENDERER_PATH]:
		if not FileAccess.file_exists(path):
			issues.append("missing:%s" % path)
	if not issues.is_empty():
		_finish(output_dir, issues, [])
		return
	var packed := load(FIXTURE_PATH) as PackedScene
	var world_script := load(WORLD_HOST_PATH) as Script
	var ui_script := load(UI_SCALE_ROOT_PATH) as Script
	var renderer_script := load(RENDERER_PATH) as Script
	if packed == null or world_script == null or ui_script == null or renderer_script == null:
		_finish(output_dir, ["runtime_contract_load_failed"], [])
		return
	var saved: Array[String] = []
	var absolute_output := ProjectSettings.globalize_path(output_dir)
	if DirAccess.make_dir_recursive_absolute(absolute_output) != OK:
		_finish(output_dir, ["output_directory_failed"], [])
		return
	for resolution: Vector2i in RESOLUTIONS:
		for color_mode: StringName in COLOR_MODES:
			var probe := packed.instantiate() as Control
			get_root().add_child(probe)
			get_root().size = resolution
			var world: Variant = world_script.new()
			var ui: Variant = ui_script.new()
			var renderer: Variant = renderer_script.new()
			if world is Node:
				probe.add_child(world)
			if ui is Node:
				probe.add_child(ui)
			var world_report: Variant = world.call(&"configure", resolution)
			var ui_report: Variant = ui.call(&"configure", resolution, 150)
			var accessibility_report: Variant = renderer.call(
				&"apply", probe, color_mode, 150
			)
			if not _ok(world_report) or not _ok(ui_report) \
				or not _ok(accessibility_report):
				issues.append("runtime_apply_failed:%s:%s" % [resolution, color_mode])
				probe.queue_free()
				await process_frame
				continue
			await process_frame
			# The Windows compatibility renderer needs one additional warm-up
			# frame before the first viewport texture contains drawn controls.
			await process_frame
			var image := get_root().get_texture().get_image()
			var file_name := "runtime-%dx%d-%s-ui150.png" % [
				resolution.x, resolution.y, String(color_mode)
			]
			var resource_path := "%s/%s" % [output_dir.trim_suffix("/"), file_name]
			var saved_error := image.save_png(ProjectSettings.globalize_path(resource_path))
			if saved_error == OK:
				saved.append(resource_path)
			else:
				issues.append("screenshot_write_failed:%s" % resource_path)
			probe.queue_free()
			await process_frame
	_finish(output_dir, issues, saved)


func _output_directory() -> String:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output-dir="):
			return argument.trim_prefix("--output-dir=")
	return "res://.pipeline/visual/runtime"


func _ok(value: Variant) -> bool:
	return value is Dictionary and bool((value as Dictionary).get("ok", false))


func _finish(
	output_dir: String,
	issues: Array[String],
	saved: Array[String]
) -> void:
	print(JSON.stringify({
		"ok": issues.is_empty(),
		"exit_code": 0 if issues.is_empty() else 2,
		"output_dir": output_dir,
		"expected_count": RESOLUTIONS.size() * COLOR_MODES.size(),
		"saved": saved,
		"issues": issues,
	}))
	quit(0 if issues.is_empty() else 2)
