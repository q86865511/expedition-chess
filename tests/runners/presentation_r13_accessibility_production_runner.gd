extends SceneTree

const RUN_COMBAT_SCENE_PATH := "res://scenes/production/run_combat.tscn"
const CONSUMER_PATH := "res://services/settings/adapters/presentation_settings_runtime_consumer.gd"


func _initialize() -> void:
	call_deferred(&"_capture")


func _capture() -> void:
	var output_dir := _output_directory()
	var absolute_output := ProjectSettings.globalize_path(output_dir)
	var issues: Array[String] = []
	var saved: Array[String] = []
	var reports: Array[Dictionary] = []
	if DirAccess.make_dir_recursive_absolute(absolute_output) != OK:
		_finish(output_dir, ["output_directory_failed"], saved, reports)
		return
	var packed := load(RUN_COMBAT_SCENE_PATH) as PackedScene
	var consumer_script := load(CONSUMER_PATH) as Script
	if packed == null or consumer_script == null:
		_finish(output_dir, ["production_contract_load_failed"], saved, reports)
		return
	get_root().size = Vector2i(1280, 720)
	for case: Dictionary in _settings_cases():
		var root := packed.instantiate() as Control
		get_root().add_child(root)
		var consumer: Object = consumer_script.new(root)
		if not consumer.has_method(&"runtime_accessibility_report"):
			issues.append("runtime_report_missing:%s" % case["name"])
			root.queue_free()
			await process_frame
			continue
		var activation: Variant = consumer.call(
			&"activate",
			&"theme",
			case["settings"]
		)
		if not StringName(activation).is_empty():
			issues.append("runtime_apply_failed:%s" % case["name"])
			root.queue_free()
			await process_frame
			continue
		var tooltip := consumer.call(
			&"open_accessibility_tooltip",
			2
		) as AccessibilityTooltipResult
		if tooltip == null or not tooltip.ok:
			issues.append("tooltip_apply_failed:%s" % case["name"])
			root.queue_free()
			await process_frame
			continue
		await process_frame
		await process_frame
		var report := consumer.call(
			&"runtime_accessibility_report"
		) as AccessibilityRuntimeReport
		if report == null or not report.ok:
			issues.append("runtime_report_failed:%s" % case["name"])
		else:
			reports.append({
				"name": case["name"],
				"production_scene": RUN_COMBAT_SCENE_PATH,
				"runtime": _report_evidence(report),
			})
		var resource_path := "%s/r13-b02-%s.png" % [
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
			issues.append("screenshot_write_failed:%s" % case["name"])
		root.queue_free()
		await process_frame
	_finish(output_dir, issues, saved, reports)


func _settings_cases() -> Array[Dictionary]:
	var baseline := SettingsSnapshot.new()
	var motion := SettingsSnapshot.new()
	motion.reduced_motion = true
	var flash := SettingsSnapshot.new()
	flash.reduced_flash = true
	var particles := SettingsSnapshot.new()
	particles.reduced_particles = true
	var off := SettingsSnapshot.new()
	off.damage_number_density = &"off"
	var reduced := SettingsSnapshot.new()
	reduced.damage_number_density = &"reduced"
	var full := SettingsSnapshot.new()
	full.damage_number_density = &"full"
	return [
		{"name": "baseline-full", "settings": baseline},
		{"name": "motion-reduced", "settings": motion},
		{"name": "flash-reduced", "settings": flash},
		{"name": "particles-reduced", "settings": particles},
		{"name": "density-off", "settings": off},
		{"name": "density-reduced", "settings": reduced},
		{"name": "density-full", "settings": full},
	]


func _report_evidence(
	report: AccessibilityRuntimeReport
) -> Dictionary:
	return {
		"ok": report.ok,
		"error": report.error,
		"motion_effects_enabled": report.motion_effects_enabled,
		"flash_effects_enabled": report.flash_effects_enabled,
		"particle_effects_enabled": report.particle_effects_enabled,
		"damage_number_density": report.damage_number_density,
		"damage_event_budget": report.damage_event_budget,
		"visible_damage_samples": report.visible_damage_samples,
		"rule_information_visible": report.rule_information_visible,
		"tooltip_opened_depth": report.tooltip_opened_depth,
		"tooltip_visible_layers": report.tooltip_visible_layers,
		"tooltip_maximum_depth": report.tooltip_maximum_depth,
		"production_host": report.production_host,
		"capabilities": report.capabilities.duplicate(),
		"cjk": {
			"ok": report.cjk_ok,
			"locale": report.cjk_locale,
			"font_source": report.cjk_font_source,
			"readable": report.cjk_readable,
			"required_glyph_count": report.cjk_required_glyph_count,
			"missing_glyphs": report.cjk_missing_glyphs.duplicate(),
		},
	}


func _output_directory() -> String:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output-dir="):
			return argument.trim_prefix("--output-dir=")
	return "res://.pipeline/visual/r13-accessibility-production"


func _finish(
	output_dir: String,
	issues: Array[String],
	saved: Array[String],
	reports: Array[Dictionary]
) -> void:
	print(JSON.stringify({
		"ok": issues.is_empty(),
		"exit_code": 0 if issues.is_empty() else 2,
		"production_scene": RUN_COMBAT_SCENE_PATH,
		"output_dir": output_dir,
		"expected_count": 7,
		"saved": saved,
		"reports": reports,
		"issues": issues,
	}))
	quit(0 if issues.is_empty() else 2)
