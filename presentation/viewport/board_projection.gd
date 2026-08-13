class_name BoardProjection
extends RefCounted

const WORLD_SIZE := Vector2i(640, 360)
const BOARD_SIZE := Vector2i(
	BoardPreparationValidator.BOARD_WIDTH,
	BoardPreparationValidator.BOARD_HEIGHT
)
const ORIGIN := Vector2(180.0, 258.0)
const BASIS_X := Vector2(36.0, 0.0)
const BASIS_Y := Vector2(4.0, -20.0)
const INVALID_CELL := Vector2i(-1, -1)

var _board_transform := Transform2D(BASIS_X, BASIS_Y, ORIGIN)
var _inverse_transform := _board_transform.affine_inverse()


func logical_to_world(logical_position: Vector2) -> Vector2:
	return _board_transform * logical_position


func project_cell(logical_cell: Vector2i) -> Vector2:
	return logical_to_world(Vector2(logical_cell))


func world_to_fractional(world_position: Vector2) -> Vector2:
	return _inverse_transform * world_position


func try_world_to_cell(
	world_position: Vector2,
	cell_validator: Callable
) -> Vector2i:
	if not cell_validator.is_valid():
		return INVALID_CELL
	var fractional := world_to_fractional(world_position)
	if not _fractional_in_footprint(fractional):
		return INVALID_CELL
	# Centers are the integer lattice. Adding 0.5 then flooring makes each
	# cell half-open: [center - 0.5, center + 0.5).
	var cell := Vector2i(
		floori(fractional.x + 0.5),
		floori(fractional.y + 0.5)
	)
	return cell if bool(cell_validator.call(cell)) else INVALID_CELL


func try_screen_to_cell(
	screen_position: Vector2,
	coordinate_mapper: Object,
	cell_validator: Callable
) -> Vector2i:
	if (
		coordinate_mapper == null
		or not coordinate_mapper.has_method(&"screen_to_world")
	):
		return INVALID_CELL
	var mapped: Variant = coordinate_mapper.call(
		&"screen_to_world",
		screen_position
	)
	if not mapped is Vector2:
		return INVALID_CELL
	# The existing WindowCoordinateMapper is the sole screen -> world step.
	# Only then is the same affine inverse above used for board hit testing.
	return try_world_to_cell(mapped, cell_validator)


func cell_polygon(logical_cell: Vector2i) -> PackedVector2Array:
	var center := Vector2(logical_cell)
	return PackedVector2Array([
		logical_to_world(center + Vector2(-0.5, -0.5)),
		logical_to_world(center + Vector2(0.5, -0.5)),
		logical_to_world(center + Vector2(0.5, 0.5)),
		logical_to_world(center + Vector2(-0.5, 0.5)),
	])


func _fractional_in_footprint(fractional: Vector2) -> bool:
	return (
		fractional.x >= -0.5
		and fractional.x < float(BOARD_SIZE.x) - 0.5
		and fractional.y >= -0.5
		and fractional.y < float(BOARD_SIZE.y) - 0.5
	)
