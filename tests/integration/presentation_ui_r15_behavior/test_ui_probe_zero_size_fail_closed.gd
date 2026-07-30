extends GutTest


func test_missing_or_zero_size_ui_probe_returns_precise_typed_failure() -> void:
	for mode: StringName in [&"missing", &"zero"]:
		var fixture := _fixture(mode != &"missing", Vector2.ZERO)
		var renderer := AccessibilityRuntimeRenderer.new()
		var applied := renderer.apply(fixture, &"default", 100)
		var report := (
			renderer.runtime_report(fixture)
			if bool(applied.get("ok", false))
			else applied
		)
		assert_false(
			bool(report.get("ok", false)),
			"%s UiProbe must never produce a green runtime report" % mode
		)
		assert_eq(
			StringName(report.get("error", &"")),
			&"ACCESSIBILITY_ROOT_SIZE_INVALID"
		)


func test_valid_probe_resize_to_zero_fails_and_restore_rechecks_real_bounds() -> void:
	var fixture := _fixture(true, Vector2(1280, 720))
	var renderer := AccessibilityRuntimeRenderer.new()
	assert_true(bool(renderer.apply(fixture, &"default", 100).get("ok")))
	var valid := renderer.runtime_report(fixture)
	assert_true(bool(valid.get("ok", false)))
	assert_eq(valid.get("clipped_required_controls"), [])

	var probe := fixture.get_node(^"UiProbe") as Control
	probe.size = Vector2.ZERO
	var zero := renderer.runtime_report(fixture)
	assert_false(bool(zero.get("ok", false)))
	assert_eq(
		StringName(zero.get("error", &"")),
		&"ACCESSIBILITY_ROOT_SIZE_INVALID"
	)
	assert_ne(
		zero.get("clipped_required_controls", null),
		[],
		"zero-size bounds must not masquerade as an empty clipping list"
	)

	probe.size = Vector2(1280, 720)
	assert_true(bool(renderer.apply(fixture, &"default", 100).get("ok")))
	var restored := renderer.runtime_report(fixture)
	assert_true(bool(restored.get("ok", false)))
	assert_eq(restored.get("clipped_required_controls"), [])


func _fixture(
	include_probe: bool,
	probe_size: Vector2
) -> Control:
	var root := Control.new()
	root.name = "OuterValidRoot"
	root.size = Vector2(1280, 720)
	add_child_autofree(root)
	if include_probe:
		var probe := Control.new()
		probe.name = "UiProbe"
		probe.size = probe_size
		root.add_child(probe)
	for cue_name: StringName in [
		&"AllyCue",
		&"EnemyCue",
		&"TraitCue",
		&"RarityCue",
		&"DangerCue",
	]:
		var cue := Label.new()
		cue.name = cue_name
		root.add_child(cue)
	for index: int in 3:
		var button := Button.new()
		button.name = [
			"StartAction",
			"SettingsAction",
			"ExitAction",
		][index]
		button.position = Vector2(64.0, 64.0 + 72.0 * index)
		button.size = Vector2(240.0, 56.0)
		root.add_child(button)
	return root
