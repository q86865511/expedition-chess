class_name UiScaleRoot
extends RefCounted

const REFERENCE_SIZE := Vector2i(1280, 720)
const SUPPORTED_UI_SCALES: Array[int] = [100, 125, 150]
const INVALID_WINDOW_SIZE: StringName = &"UI_SCALE_WINDOW_SIZE_INVALID"
const UNSUPPORTED_SCALE: StringName = &"UI_SCALE_UNSUPPORTED"

var _safe_rect_value := Rect2()
var _screen_rect_value := Rect2()
var _ui_scale_percent_value: int


func configure(
	window_size: Vector2i,
	ui_scale_percent: int
) -> Dictionary:
	if window_size.x <= 0 or window_size.y <= 0:
		_reset()
		return _failure(INVALID_WINDOW_SIZE, window_size, ui_scale_percent)
	if ui_scale_percent not in SUPPORTED_UI_SCALES:
		_reset()
		return _failure(UNSUPPORTED_SCALE, window_size, ui_scale_percent)

	var window := Vector2(window_size)
	var reference := Vector2(REFERENCE_SIZE)
	var fit_scale: float = minf(
		window.x / reference.x,
		window.y / reference.y
	)
	var screen_size := reference * fit_scale
	var screen_origin := (window - screen_size) * 0.5
	_screen_rect_value = Rect2(screen_origin, screen_size)

	# UI scale is a reflow token. It increases control/font metrics inside the
	# fixed reference canvas instead of scaling and clipping the entire tree.
	_ui_scale_percent_value = ui_scale_percent
	var safe_margin := Vector2(
		maxf(0.0, (reference.x - window.x / fit_scale) * 0.5),
		maxf(0.0, (reference.y - window.y / fit_scale) * 0.5)
	)
	_safe_rect_value = Rect2(
		safe_margin,
		reference - safe_margin * 2.0
	)
	return {
		"ok": true,
		"error": &"",
		"window_size": window_size,
		"reference_size": REFERENCE_SIZE,
		"screen_rect": _screen_rect_value,
		"safe_rect": _safe_rect_value,
		"ui_scale_percent": _ui_scale_percent_value,
		"layout_scale": float(_ui_scale_percent_value) / 100.0,
	}


func reference_size() -> Vector2i:
	return REFERENCE_SIZE


func safe_rect() -> Rect2:
	return _safe_rect_value


func screen_rect() -> Rect2:
	return _screen_rect_value


func ui_scale_percent() -> int:
	return _ui_scale_percent_value


func _failure(
	error: StringName,
	window_size: Vector2i,
	ui_scale_percent: int
) -> Dictionary:
	return {
		"ok": false,
		"error": error,
		"window_size": window_size,
		"reference_size": REFERENCE_SIZE,
		"screen_rect": Rect2(),
		"safe_rect": Rect2(),
		"ui_scale_percent": ui_scale_percent,
		"layout_scale": 0.0,
	}


func _reset() -> void:
	_safe_rect_value = Rect2()
	_screen_rect_value = Rect2()
	_ui_scale_percent_value = 0
