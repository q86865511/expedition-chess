class_name WindowCoordinateMapper
extends RefCounted

const WORLD_SIZE := Vector2i(640, 360)
const UI_REFERENCE_SIZE := Vector2i(1280, 720)
const SUPPORTED_UI_SCALES: Array[int] = [100, 125, 150]

const LAYOUT_INVALID: StringName = &"VIEWPORT_LAYOUT_INVALID"
const LAYOUT_WORLD_SIZE_INVALID: StringName = &"VIEWPORT_LAYOUT_WORLD_SIZE_INVALID"
const LAYOUT_UI_REFERENCE_SIZE_INVALID: StringName = (
	&"VIEWPORT_LAYOUT_UI_REFERENCE_SIZE_INVALID"
)
const LAYOUT_INTEGER_SCALE_INVALID: StringName = (
	&"VIEWPORT_LAYOUT_INTEGER_SCALE_INVALID"
)
const LAYOUT_WORLD_RECT_INVALID: StringName = &"VIEWPORT_LAYOUT_WORLD_RECT_INVALID"
const LAYOUT_WINDOW_SIZE_INVALID: StringName = &"VIEWPORT_LAYOUT_WINDOW_SIZE_INVALID"
const UI_SCALE_UNSUPPORTED: StringName = &"VIEWPORT_UI_SCALE_UNSUPPORTED"
const NOT_CONFIGURED: StringName = &"VIEWPORT_MAPPER_NOT_CONFIGURED"

var _configured: bool
var _configuration_error: StringName = NOT_CONFIGURED
var _world_origin := Vector2.ZERO
var _world_scale: float = 1.0
var _ui_origin := Vector2.ZERO
var _ui_scale: float = 1.0
var _ui_scale_percent_value: int


func configure(layout: Dictionary, ui_scale_percent_value: int) -> StringName:
	_reset_configuration()
	if ui_scale_percent_value not in SUPPORTED_UI_SCALES:
		return _reject(UI_SCALE_UNSUPPORTED)
	if layout.is_empty() or not bool(layout.get("ok", true)):
		return _reject(LAYOUT_INVALID)

	var world_size_value: Variant = layout.get("world_size")
	if not world_size_value is Vector2i or world_size_value != WORLD_SIZE:
		return _reject(LAYOUT_WORLD_SIZE_INVALID)

	var ui_reference_size_value: Variant = layout.get("ui_reference_size")
	if (
		not ui_reference_size_value is Vector2i
		or ui_reference_size_value != UI_REFERENCE_SIZE
	):
		return _reject(LAYOUT_UI_REFERENCE_SIZE_INVALID)

	var integer_scale_value: Variant = layout.get("integer_scale")
	if not integer_scale_value is int or integer_scale_value <= 0:
		return _reject(LAYOUT_INTEGER_SCALE_INVALID)

	var world_rect_value: Variant = layout.get("world_rect")
	if not world_rect_value is Rect2:
		return _reject(LAYOUT_WORLD_RECT_INVALID)
	var world_rect: Rect2 = world_rect_value
	var expected_world_rect_size := Vector2(WORLD_SIZE * int(integer_scale_value))
	if world_rect.size != expected_world_rect_size:
		return _reject(LAYOUT_WORLD_RECT_INVALID)

	var window_size_value: Variant = layout.get("window_size")
	if (
		not window_size_value is Vector2i
		or window_size_value.x <= 0
		or window_size_value.y <= 0
	):
		return _reject(LAYOUT_WINDOW_SIZE_INVALID)

	var window_size_i: Vector2i = window_size_value
	var window_size := Vector2(window_size_i)
	var reference_size := Vector2(UI_REFERENCE_SIZE)
	var reference_fit_scale: float = minf(
		window_size.x / reference_size.x,
		window_size.y / reference_size.y
	)
	if reference_fit_scale <= 0.0:
		return _reject(LAYOUT_WINDOW_SIZE_INVALID)

	# Copy only scalar/value fields from the caller's layout. No mutable layout
	# object remains reachable after configuration.
	_world_origin = world_rect.position
	_world_scale = float(integer_scale_value)
	_ui_scale_percent_value = ui_scale_percent_value
	# UI scale is a reflow token applied inside the fixed reference canvas. It
	# must not be multiplied into the CanvasLayer transform.
	_ui_scale = reference_fit_scale
	var scaled_reference_size := reference_size * _ui_scale
	_ui_origin = (window_size - scaled_reference_size) * 0.5
	_configured = true
	_configuration_error = &""
	return &""


func world_to_screen(world_position: Vector2) -> Vector2:
	if not _configured:
		return Vector2.ZERO
	return _world_origin + world_position * _world_scale


func screen_to_world(screen_position: Vector2) -> Vector2:
	if not _configured:
		return Vector2.ZERO
	return (screen_position - _world_origin) / _world_scale


func ui_to_screen(ui_reference_position: Vector2) -> Vector2:
	if not _configured:
		return Vector2.ZERO
	return _ui_origin + ui_reference_position * _ui_scale


func screen_to_ui(screen_position: Vector2) -> Vector2:
	if not _configured:
		return Vector2.ZERO
	return (screen_position - _ui_origin) / _ui_scale


func ui_scale_percent() -> int:
	return _ui_scale_percent_value


func configuration_error() -> StringName:
	return _configuration_error


func _reject(error: StringName) -> StringName:
	_configuration_error = error
	return error


func _reset_configuration() -> void:
	_configured = false
	_configuration_error = NOT_CONFIGURED
	_world_origin = Vector2.ZERO
	_world_scale = 1.0
	_ui_origin = Vector2.ZERO
	_ui_scale = 1.0
	_ui_scale_percent_value = 0
