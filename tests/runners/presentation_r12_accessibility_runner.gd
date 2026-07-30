extends SceneTree

const FIXTURE_PATH := (
	"res://tests/fixtures/presentation_r12_accessibility/"
	+ "accessibility_runtime_probe.tscn"
)
const RENDERER_PATH := (
	"res://presentation/accessibility/accessibility_runtime_renderer.gd"
)
const TYPOGRAPHY_PATH := (
	"res://presentation/accessibility/localized_typography_policy.gd"
)
const REQUIRED_ZH_TW_PROBE := "遠征棋設定羈絆稀有度傷害提示"


func _initialize() -> void:
	call_deferred(&"_capture")


func _capture() -> void:
	var output_dir := _output_directory()
	var issues: Array[String] = []
	var saved: Array[String] = []
	for path: String in [FIXTURE_PATH, RENDERER_PATH, TYPOGRAPHY_PATH]:
		if not FileAccess.file_exists(path):
			issues.append("missing:%s" % path)
	if not issues.is_empty():
		_finish(output_dir, issues, saved, [])
		return
	var packed := load(FIXTURE_PATH) as PackedScene
	var renderer_script := load(RENDERER_PATH) as Script
	var typography_script := load(TYPOGRAPHY_PATH) as Script
	if packed == null or renderer_script == null or typography_script == null:
		_finish(output_dir, ["runtime_contract_load_failed"], saved, [])
		return
	var renderer: Variant = renderer_script.new()
	var typography: Variant = typography_script.new()
	for method_name: StringName in [
		&"apply_settings",
		&"runtime_effect_report",
		&"open_tooltip",
	]:
		if not renderer.has_method(method_name):
			issues.append("renderer_method_missing:%s" % method_name)
	for method_name: StringName in [&"readability_report", &"apply_to"]:
		if not typography.has_method(method_name):
			issues.append("typography_method_missing:%s" % method_name)
	if not issues.is_empty():
		_finish(output_dir, issues, saved, [])
		return
	var absolute_output := ProjectSettings.globalize_path(output_dir)
	if DirAccess.make_dir_recursive_absolute(absolute_output) != OK:
		_finish(output_dir, ["output_directory_failed"], saved, [])
		return

	var reports: Array[Dictionary] = []
	for case: Dictionary in _settings_cases():
		var probe := packed.instantiate() as Control
		get_root().add_child(probe)
		get_root().size = Vector2i(1280, 720)
		var settings: SettingsSnapshot = case["settings"]
		var applied: Variant = renderer.call(&"apply_settings", probe, settings)
		var typography_applied: Variant = typography.call(
			&"apply_to",
			probe.get_node(^"CjkProbe"),
			&"zh_TW",
			REQUIRED_ZH_TW_PROBE
		)
		renderer.call(&"open_tooltip", probe, 2)
		if not _ok(applied) or not _ok(typography_applied):
			issues.append("runtime_apply_failed:%s" % case["name"])
			probe.queue_free()
			await process_frame
			continue
		# Godot 4.7's Windows compatibility renderer needs a second warm-up
		# frame before the first viewport texture contains the newly added UI.
		await process_frame
		await process_frame
		var report: Variant = renderer.call(&"runtime_effect_report", probe)
		var typography_report: Variant = typography.call(
			&"readability_report",
			&"zh_TW",
			REQUIRED_ZH_TW_PROBE
		)
		if not _ok(report) or not _ok(typography_report):
			issues.append("runtime_report_failed:%s" % case["name"])
		else:
			reports.append({
				"name": case["name"],
				"effects": report,
				"typography": typography_report,
			})
		var resource_path := "%s/r12-b02-%s.png" % [
			output_dir.trim_suffix("/"),
			case["name"],
		]
		var image := get_root().get_texture().get_image()
		var save_error := image.save_png(
			ProjectSettings.globalize_path(resource_path)
		)
		if save_error == OK:
			saved.append(resource_path)
		else:
			issues.append("screenshot_write_failed:%s" % resource_path)
		probe.queue_free()
		await process_frame
	_finish(output_dir, issues, saved, reports)


func _settings_cases() -> Array[Dictionary]:
	var defaults := SettingsSnapshot.new()
	var reduced := SettingsSnapshot.new()
	reduced.reduced_motion = true
	reduced.reduced_flash = true
	reduced.reduced_particles = true
	reduced.damage_number_density = &"off"
	var reduced_density := SettingsSnapshot.new()
	reduced_density.damage_number_density = &"reduced"
	return [
		{"name": "default-full", "settings": defaults},
		{"name": "reduced-all-off", "settings": reduced},
		{"name": "default-reduced", "settings": reduced_density},
	]


func _output_directory() -> String:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output-dir="):
			return argument.trim_prefix("--output-dir=")
	return "res://.pipeline/visual/r12-accessibility"


func _ok(value: Variant) -> bool:
	return value is Dictionary and bool((value as Dictionary).get("ok", false))


func _finish(
	output_dir: String,
	issues: Array[String],
	saved: Array[String],
	reports: Array[Dictionary]
) -> void:
	print(JSON.stringify({
		"ok": issues.is_empty(),
		"exit_code": 0 if issues.is_empty() else 2,
		"output_dir": output_dir,
		"expected_count": 3,
		"saved": saved,
		"reports": reports,
		"issues": issues,
	}))
	quit(0 if issues.is_empty() else 2)
