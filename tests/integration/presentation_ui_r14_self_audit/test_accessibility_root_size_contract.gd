extends GutTest


func test_detached_zero_size_accessibility_root_fails_closed() -> void:
	var scene := load("res://scenes/production/run_combat.tscn") as PackedScene
	assert_not_null(scene)
	if scene == null:
		return
	var screen := scene.instantiate() as ProductionScreen
	assert_not_null(screen)
	if screen == null:
		return
	screen.size = Vector2.ZERO
	var host := (
		screen.get_node_or_null(^"AccessibilityRuntime")
		as ProductionAccessibilityHost
	)
	assert_not_null(host)
	if host == null:
		screen.free()
		return
	assert_eq(host.size, Vector2.ZERO, "detached full-rect host has no viewport")

	var report := host.apply_committed_settings(SettingsSnapshot.new())

	assert_not_null(report)
	assert_false(report.ok)
	assert_eq(report.error, &"ACCESSIBILITY_ROOT_SIZE_INVALID")
	screen.free()
