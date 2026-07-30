extends GutTest

const Support = preload(
	"res://tests/unit/presentation_ui_viewport/viewport_test_support.gd"
)

const WINDOW_CASES: Array[Dictionary] = [
	{
		"window_size": Vector2i(1280, 720),
		"integer_scale": 2,
		"world_rect": Rect2(0.0, 0.0, 1280.0, 720.0),
		"letterboxed": false,
	},
	{
		"window_size": Vector2i(1920, 1080),
		"integer_scale": 3,
		"world_rect": Rect2(0.0, 0.0, 1920.0, 1080.0),
		"letterboxed": false,
	},
	{
		"window_size": Vector2i(2560, 1440),
		"integer_scale": 4,
		"world_rect": Rect2(0.0, 0.0, 2560.0, 1440.0),
		"letterboxed": false,
	},
	{
		"window_size": Vector2i(1024, 768),
		"integer_scale": 1,
		"world_rect": Rect2(192.0, 204.0, 640.0, 360.0),
		"letterboxed": true,
	},
	{
		"window_size": Vector2i(1280, 800),
		"integer_scale": 2,
		"world_rect": Rect2(0.0, 40.0, 1280.0, 720.0),
		"letterboxed": true,
	},
]


func test_world_and_ui_reference_contract_is_fixed_and_pixel_safe() -> void:
	var script := Support.load_script(self, Support.POLICY_PATH)
	if script == null:
		return
	var policy: Object = script.new()
	if not Support.require_methods(
		self,
		policy,
		[
			&"world_size",
			&"ui_reference_size",
			&"texture_filter_mode",
			&"pixel_snap_enabled",
		]
	):
		return

	assert_eq(policy.call("world_size"), Vector2i(640, 360))
	assert_eq(policy.call("ui_reference_size"), Vector2i(1280, 720))
	assert_eq(policy.call("texture_filter_mode"), &"nearest")
	assert_true(bool(policy.call("pixel_snap_enabled")))


func test_layout_uses_largest_integer_world_scale_and_centered_letterbox() -> void:
	var script := Support.load_script(self, Support.POLICY_PATH)
	if script == null:
		return
	var policy: Object = script.new()
	if not Support.require_methods(self, policy, [&"layout_for_window"]):
		return

	for case: Dictionary in WINDOW_CASES:
		var window_size: Vector2i = case["window_size"]
		var layout: Variant = policy.call("layout_for_window", window_size)
		assert_true(layout is Dictionary, "%s must produce a layout" % window_size)
		if not layout is Dictionary:
			continue
		assert_eq(
			layout.get("world_size"),
			Vector2i(640, 360),
			"%s must preserve the fixed world viewport" % window_size
		)
		assert_eq(
			layout.get("ui_reference_size"),
			Vector2i(1280, 720),
			"%s must preserve the independent UI reference" % window_size
		)
		assert_eq(
			layout.get("integer_scale"),
			case["integer_scale"],
			"%s must choose the largest fitting integer scale" % window_size
		)
		assert_eq(
			layout.get("world_rect"),
			case["world_rect"],
			"%s must center the un-stretched world texture" % window_size
		)
		assert_eq(
			layout.get("letterboxed"),
			case["letterboxed"],
			"%s letterbox status" % window_size
		)
		assert_eq(layout.get("texture_filter"), &"nearest")
		assert_eq(layout.get("pixel_snap"), true)
