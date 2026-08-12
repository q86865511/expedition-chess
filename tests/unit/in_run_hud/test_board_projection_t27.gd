extends GutTest

const ProjectionScript = preload("res://presentation/viewport/board_projection.gd")
const PolicyScript = preload(
	"res://presentation/viewport/world_viewport_policy.gd"
)
const MapperScript = preload(
	"res://presentation/viewport/window_coordinate_mapper.gd"
)

const OUTPUT_SIZES: Array[Vector2i] = [
	Vector2i(1280, 720),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440),
]
const EPSILON := 0.000001


func test_all_sixty_four_cell_centers_round_trip_through_one_affine_inverse() -> void:
	var projection := ProjectionScript.new()
	assert_eq(projection.WORLD_SIZE, Vector2i(640, 360))
	assert_eq(projection.ORIGIN, Vector2(180.0, 258.0))
	assert_eq(projection.BASIS_X, Vector2(36.0, 0.0))
	assert_eq(projection.BASIS_Y, Vector2(4.0, -20.0))

	for logical_y: int in range(8):
		for logical_x: int in range(8):
			var cell := Vector2i(logical_x, logical_y)
			var fractional: Vector2 = projection.world_to_fractional(
				projection.project_cell(cell)
			)
			assert_almost_eq(fractional.x, float(logical_x), EPSILON)
			assert_almost_eq(fractional.y, float(logical_y), EPSILON)


func test_half_open_boundaries_round_to_nearest_center_and_fail_closed() -> void:
	var projection := ProjectionScript.new()
	var allow_all := func(_cell: Vector2i) -> bool: return true
	assert_eq(
		projection.try_world_to_cell(
			projection.logical_to_world(Vector2(-0.5, 0.0)),
			allow_all
		),
		Vector2i(0, 0),
		"lower footprint edge is included"
	)
	assert_eq(
		projection.try_world_to_cell(
			projection.logical_to_world(Vector2(0.5, 0.0)),
			allow_all
		),
		Vector2i(1, 0),
		"shared cell edge belongs to the cell on its positive side"
	)
	assert_eq(
		projection.try_world_to_cell(
			projection.logical_to_world(Vector2(0.0, -0.5)),
			allow_all
		),
		Vector2i(0, 0),
		"lower y footprint edge is included"
	)
	assert_eq(
		projection.try_world_to_cell(
			projection.logical_to_world(Vector2(0.0, 0.5)),
			allow_all
		),
		Vector2i(0, 1),
		"shared y edge belongs to the cell on its positive side"
	)
	assert_eq(
		projection.try_world_to_cell(
			projection.logical_to_world(Vector2(7.5, 0.0)),
			allow_all
		),
		projection.INVALID_CELL,
		"upper footprint edge is excluded"
	)
	assert_eq(
		projection.try_world_to_cell(
			projection.logical_to_world(Vector2(0.0, 7.5)),
			allow_all
		),
		projection.INVALID_CELL,
		"upper y footprint edge is excluded"
	)
	assert_eq(
		projection.try_world_to_cell(
			projection.project_cell(Vector2i(2, 3)),
			func(_cell: Vector2i) -> bool: return false
		),
		projection.INVALID_CELL,
		"the caller's domain validator remains authoritative"
	)
	assert_eq(
		projection.try_world_to_cell(
			projection.project_cell(Vector2i(2, 3)),
			Callable()
		),
		projection.INVALID_CELL,
		"missing validator fails closed"
	)


func test_screen_hit_uses_window_mapper_and_centers_land_on_integer_output_pixels() -> void:
	var projection := ProjectionScript.new()
	var policy := PolicyScript.new()
	var mapper := MapperScript.new()

	for output_size: Vector2i in OUTPUT_SIZES:
		var layout: Dictionary = policy.layout_for_window(output_size)
		assert_eq(mapper.configure(layout, 100), &"")
		for logical_y: int in range(8):
			for logical_x: int in range(8):
				var cell := Vector2i(logical_x, logical_y)
				var screen_point: Vector2 = mapper.world_to_screen(
					projection.project_cell(cell)
				)
				assert_eq(
					screen_point,
					screen_point.round(),
					"%s cell %s must land on an integer pixel" % [
						output_size,
						cell,
					]
				)
				assert_eq(
					projection.try_screen_to_cell(
						screen_point,
						mapper,
						func(candidate: Vector2i) -> bool: return candidate == cell
					),
					cell,
					"%s cell %s screen round-trip" % [output_size, cell]
				)
