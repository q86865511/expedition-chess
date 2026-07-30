class_name WorldViewportHost
extends RefCounted

var _policy := WorldViewportPolicy.new()
var _layout: Dictionary = {}


func configure(window_size: Vector2i) -> Dictionary:
	var candidate: Dictionary = _policy.layout_for_window(window_size)
	if not bool(candidate.get("ok", false)):
		_layout.clear()
		return candidate.duplicate(true)
	_layout = candidate.duplicate(true)
	return _layout.duplicate(true)


func world_size() -> Vector2i:
	return _policy.world_size()


func world_rect() -> Rect2:
	var value: Variant = _layout.get("world_rect", Rect2())
	return value as Rect2 if value is Rect2 else Rect2()


func texture_filter_mode() -> StringName:
	return _policy.texture_filter_mode()


func pixel_snap_enabled() -> bool:
	return _policy.pixel_snap_enabled()
