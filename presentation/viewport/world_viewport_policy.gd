class_name WorldViewportPolicy
extends RefCounted

const WORLD_SIZE := Vector2i(640, 360)
const UI_REFERENCE_SIZE := Vector2i(1280, 720)
const INVALID_WINDOW_SIZE: StringName = &"VIEWPORT_WINDOW_SIZE_INVALID"


func world_size() -> Vector2i:
	return WORLD_SIZE


func ui_reference_size() -> Vector2i:
	return UI_REFERENCE_SIZE


func texture_filter_mode() -> StringName:
	return &"nearest"


func pixel_snap_enabled() -> bool:
	return true


func layout_for_window(window_size: Vector2i) -> Dictionary:
	if window_size.x <= 0 or window_size.y <= 0:
		return {
			"ok": false,
			"error": INVALID_WINDOW_SIZE,
			"window_size": window_size,
			"world_size": WORLD_SIZE,
			"ui_reference_size": UI_REFERENCE_SIZE,
			"integer_scale": 0,
			"world_rect": Rect2(),
			"letterboxed": true,
			"texture_filter": &"nearest",
			"pixel_snap": true,
		}

	var width_scale: int = floori(float(window_size.x) / float(WORLD_SIZE.x))
	var height_scale: int = floori(float(window_size.y) / float(WORLD_SIZE.y))
	var integer_scale: int = maxi(1, mini(width_scale, height_scale))
	var scaled_size := WORLD_SIZE * integer_scale
	var remaining := window_size - scaled_size
	var world_origin := Vector2(
		floori(float(remaining.x) * 0.5),
		floori(float(remaining.y) * 0.5)
	)
	var world_rect := Rect2(world_origin, Vector2(scaled_size))

	return {
		"ok": true,
		"error": &"",
		"window_size": window_size,
		"world_size": WORLD_SIZE,
		"ui_reference_size": UI_REFERENCE_SIZE,
		"integer_scale": integer_scale,
		"world_rect": world_rect,
		"letterboxed": (
			world_rect.position != Vector2.ZERO
			or world_rect.size != Vector2(window_size)
		),
		"texture_filter": &"nearest",
		"pixel_snap": true,
	}
