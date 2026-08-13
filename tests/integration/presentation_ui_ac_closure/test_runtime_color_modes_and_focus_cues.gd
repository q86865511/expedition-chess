extends GutTest

const Support := preload(
	"res://tests/integration/presentation_ui_ac_closure/ac_closure_test_support.gd"
)

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
const REQUIRED_CUES: Array[StringName] = [
	&"ally",
	&"enemy",
	&"trait",
	&"rarity",
	&"danger",
]


func test_runtime_world_and_ui_hosts_cover_the_screenshot_matrix() -> void:
	var fixture_exists := ResourceLoader.exists(Support.RUNTIME_FIXTURE_PATH, "PackedScene")
	assert_true(fixture_exists, "runtime screenshot fixture must be importable")
	assert_true(
		FileAccess.file_exists(Support.RUNTIME_RUNNER_PATH),
		"runtime screenshot runner contract must exist"
	)
	var world_script := Support.load_script(
		self, Support.WORLD_HOST_PATH, "AC-028 WorldViewportHost"
	)
	var ui_script := Support.load_script(
		self, Support.UI_SCALE_ROOT_PATH, "AC-028 UiScaleRoot"
	)
	if not fixture_exists or world_script == null or ui_script == null:
		return
	var world: Variant = world_script.new()
	var ui: Variant = ui_script.new()
	_autofree_if_node(world)
	_autofree_if_node(ui)
	if not Support.require_methods(
		self,
		world,
		[
			&"configure",
			&"world_size",
			&"world_rect",
			&"texture_filter_mode",
			&"pixel_snap_enabled",
		],
		"WorldViewportHost"
	) or not Support.require_methods(
		self,
		ui,
		[&"configure", &"reference_size", &"safe_rect"],
		"UiScaleRoot"
	):
		return
	for resolution: Vector2i in RESOLUTIONS:
		var world_report: Variant = world.call(&"configure", resolution)
		var ui_report: Variant = ui.call(&"configure", resolution, 150)
		assert_true(Support.report_ok(world_report), "world configure %s" % resolution)
		assert_true(Support.report_ok(ui_report), "UI configure %s" % resolution)
		assert_eq(world.call(&"world_size"), Vector2i(640, 360))
		assert_eq(world.call(&"texture_filter_mode"), &"nearest")
		assert_true(bool(world.call(&"pixel_snap_enabled")))
		assert_eq(ui.call(&"reference_size"), Vector2i(1920, 1080))
		var safe_rect: Variant = ui.call(&"safe_rect")
		assert_true(safe_rect is Rect2 and (safe_rect as Rect2).size.x > 0.0)


func test_runtime_four_color_modes_keep_non_color_cues_and_visible_focus_at_150() -> void:
	var renderer_script := Support.load_script(
		self,
		Support.ACCESSIBILITY_RENDERER_PATH,
		"AC-029 accessibility runtime renderer"
	)
	if renderer_script == null:
		return
	var packed := load(Support.RUNTIME_FIXTURE_PATH) as PackedScene
	assert_not_null(packed)
	if packed == null:
		return
	var fixture := autofree(packed.instantiate()) as Control
	var renderer: Variant = renderer_script.new()
	_autofree_if_node(renderer)
	if not Support.require_methods(
		self,
		renderer,
		[&"apply", &"runtime_report"],
		"AccessibilityRuntimeRenderer"
	):
		return
	for color_mode: StringName in COLOR_MODES:
		var applied: Variant = renderer.call(&"apply", fixture, color_mode, 150)
		assert_true(Support.report_ok(applied), "apply %s at 150%%" % color_mode)
		var report: Variant = renderer.call(&"runtime_report", fixture)
		assert_true(report is Dictionary)
		if not report is Dictionary:
			continue
		assert_eq(report.get("color_mode"), color_mode)
		assert_eq(report.get("ui_scale_percent"), 150)
		assert_true(report.get("focus_visible", false))
		assert_true(report.get("required_actions_reachable", false))
		assert_eq(report.get("clipped_required_controls", []), [])
		var cues: Dictionary = report.get("semantic_cues", {})
		for semantic: StringName in REQUIRED_CUES:
			assert_true(cues.has(semantic), "%s cue missing in %s" % [semantic, color_mode])
			var cue: Dictionary = cues.get(semantic, {})
			assert_false(String(cue.get("icon", "")).is_empty())
			assert_false(String(cue.get("pattern", "")).is_empty())
			assert_false(String(cue.get("text", "")).is_empty())


func _autofree_if_node(value: Variant) -> void:
	if value is Node:
		autofree(value as Node)
