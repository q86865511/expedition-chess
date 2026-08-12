class_name ProductionUnitVisualCatalog
extends RefCounted

## Presentation-only lookup over the adopted, versioned visual manifest. It is
## deliberately independent from gameplay content lookup and never asks the
## ContentRegistry for a latest generation.

const MANIFEST_PATH := "res://assets/production/inventory.json"
const MANIFEST_INVALID: StringName = &"PRODUCTION_VISUAL_MANIFEST_INVALID"

var _sprite_paths: Dictionary = {}
var _portrait_paths: Dictionary = {}
var _sprite_cache: Dictionary = {}
var _portrait_cache: Dictionary = {}
var _load_error: StringName = &""


func _init() -> void:
	_load_manifest()


func load_error() -> StringName:
	return _load_error


func try_sprite_frames(unit_def_id: StringName) -> SpriteFrames:
	if _load_error != &"" or unit_def_id.is_empty():
		return null
	if _sprite_cache.has(unit_def_id):
		return _sprite_cache[unit_def_id] as SpriteFrames
	var relative_path := String(_sprite_paths.get(unit_def_id, ""))
	if relative_path.is_empty():
		return null
	var resource_path := relative_path
	if not resource_path.begins_with("res://"):
		resource_path = "res://%s" % resource_path
	var frames := ResourceLoader.load(resource_path, "SpriteFrames") as SpriteFrames
	if frames != null:
		_sprite_cache[unit_def_id] = frames
	return frames


func idle_animation(frames: SpriteFrames, star: int) -> StringName:
	if frames == null:
		return &""
	var desired := StringName("idle_s_star%d" % clampi(star, 1, 3))
	if frames.has_animation(desired):
		return desired
	return &"idle_s_star1" if frames.has_animation(&"idle_s_star1") else &""


func try_portrait(unit_def_id: StringName) -> Texture2D:
	if _load_error != &"" or unit_def_id.is_empty():
		return null
	if _portrait_cache.has(unit_def_id):
		return _portrait_cache[unit_def_id] as Texture2D
	var relative_path := String(_portrait_paths.get(unit_def_id, ""))
	if relative_path.is_empty():
		return null
	var resource_path := relative_path
	if not resource_path.begins_with("res://"):
		resource_path = "res://%s" % resource_path
	var portrait := ResourceLoader.load(resource_path, "Texture2D") as Texture2D
	if portrait != null:
		_portrait_cache[unit_def_id] = portrait
	return portrait


func _load_manifest() -> void:
	var source := FileAccess.get_file_as_string(MANIFEST_PATH)
	var parsed: Variant = JSON.parse_string(source)
	if not parsed is Dictionary:
		_load_error = MANIFEST_INVALID
		return
	var root := parsed as Dictionary
	var units: Variant = root.get("units", [])
	if not units is Array:
		_load_error = MANIFEST_INVALID
		return
	for entry_value: Variant in units:
		if not entry_value is Dictionary:
			continue
		var entry := entry_value as Dictionary
		var outputs: Variant = entry.get("outputs", {})
		if not outputs is Dictionary:
			continue
		var unit_id := StringName(String(entry.get("unit_id", "")))
		var sprite_path := String((outputs as Dictionary).get("sprite_frames", ""))
		var portrait_path := String((outputs as Dictionary).get("portrait", ""))
		if not unit_id.is_empty() and not sprite_path.is_empty():
			_sprite_paths[unit_id] = sprite_path
		if not unit_id.is_empty() and not portrait_path.is_empty():
			_portrait_paths[unit_id] = portrait_path
	if _sprite_paths.is_empty():
		_load_error = MANIFEST_INVALID
