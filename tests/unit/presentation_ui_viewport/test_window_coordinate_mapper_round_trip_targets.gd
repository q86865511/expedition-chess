extends GutTest

const Support = preload(
	"res://tests/unit/presentation_ui_viewport/viewport_test_support.gd"
)

const WINDOW_SIZES: Array[Vector2i] = [
	Vector2i(1280, 720),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440),
	Vector2i(1024, 768),
	Vector2i(1280, 800),
]
const UI_SCALES: Array[int] = [100, 125, 150]
const TILE_SIZE := Vector2i(16, 16)
const BOARD_TILE := Vector2i(17, 11)
const CAMP_HOTSPOT := Rect2(412.0, 196.0, 48.0, 32.0)
const UI_CONTROL := Rect2(930.0, 520.0, 210.0, 72.0)


func test_world_tile_and_camp_hotspot_round_trip_across_resolution_matrix() -> void:
	var values := _new_contracts()
	if values.is_empty():
		return
	var policy: Object = values[0]
	var mapper: Object = values[1]

	for window_size: Vector2i in WINDOW_SIZES:
		var layout: Dictionary = policy.call("layout_for_window", window_size)
		for ui_scale: int in UI_SCALES:
			var configured: Variant = mapper.call("configure", layout, ui_scale)
			assert_eq(
				configured,
				&"",
				"%s at %d%% must configure" % [window_size, ui_scale]
			)

			var tile_world_point := Vector2(
				(BOARD_TILE.x + 0.5) * TILE_SIZE.x,
				(BOARD_TILE.y + 0.5) * TILE_SIZE.y
			)
			var tile_screen: Vector2 = mapper.call("world_to_screen", tile_world_point)
			var tile_round_trip: Vector2 = mapper.call("screen_to_world", tile_screen)
			Support.assert_vector2_near(
				self,
				tile_round_trip,
				tile_world_point,
				"%s %d%% board world round-trip" % [window_size, ui_scale]
			)
			assert_eq(
				Vector2i(
					floori(tile_round_trip.x / TILE_SIZE.x),
					floori(tile_round_trip.y / TILE_SIZE.y)
				),
				BOARD_TILE,
				"%s %d%% must hit the same board tile" % [window_size, ui_scale]
			)

			var hotspot_world_point := CAMP_HOTSPOT.get_center()
			var hotspot_screen: Vector2 = mapper.call("world_to_screen", hotspot_world_point)
			var hotspot_round_trip: Vector2 = mapper.call(
				"screen_to_world",
				hotspot_screen
			)
			assert_true(
				CAMP_HOTSPOT.has_point(hotspot_round_trip),
				"%s %d%% must hit the same Camp hotspot" % [window_size, ui_scale]
			)


func test_ui_control_round_trip_uses_reference_space_at_all_supported_scales() -> void:
	var values := _new_contracts()
	if values.is_empty():
		return
	var policy: Object = values[0]
	var mapper: Object = values[1]

	for window_size: Vector2i in WINDOW_SIZES:
		var layout: Dictionary = policy.call("layout_for_window", window_size)
		for ui_scale: int in UI_SCALES:
			var configured: Variant = mapper.call("configure", layout, ui_scale)
			assert_eq(configured, &"")
			assert_eq(mapper.call("ui_scale_percent"), ui_scale)

			var control_reference_point := UI_CONTROL.get_center()
			var control_screen: Vector2 = mapper.call(
				"ui_to_screen",
				control_reference_point
			)
			var control_round_trip: Vector2 = mapper.call(
				"screen_to_ui",
				control_screen
			)
			Support.assert_vector2_near(
				self,
				control_round_trip,
				control_reference_point,
				"%s %d%% UI reference round-trip" % [window_size, ui_scale]
			)
			assert_true(
				UI_CONTROL.has_point(control_round_trip),
				"%s %d%% must hit the same UI control" % [window_size, ui_scale]
			)


func _new_contracts() -> Array[Object]:
	var policy_script := Support.load_script(self, Support.POLICY_PATH)
	var mapper_script := Support.load_script(self, Support.MAPPER_PATH)
	if policy_script == null or mapper_script == null:
		return []
	var policy: Object = policy_script.new()
	var mapper: Object = mapper_script.new()
	if not Support.require_methods(self, policy, [&"layout_for_window"]):
		return []
	if not Support.require_methods(
		self,
		mapper,
		[
			&"configure",
			&"world_to_screen",
			&"screen_to_world",
			&"ui_to_screen",
			&"screen_to_ui",
			&"ui_scale_percent",
		]
	):
		return []
	return [policy, mapper]
