class_name ProductionEnvironmentVisualCatalog
extends RefCounted

const MANIFEST_PATH := \
	"res://assets/production/environment/inventory.json"
const MANIFEST_INVALID: StringName = &"ENVIRONMENT_VISUAL_MANIFEST_INVALID"

var _texture_paths: Dictionary = {}
var _texture_cache: Dictionary = {}
var _load_error: StringName = &""


func _init() -> void:
	_load_manifest()


func load_error() -> StringName:
	return _load_error


func visual_ids() -> Array[StringName]:
	var result: Array[StringName] = []
	for visual_id: StringName in _texture_paths:
		result.append(visual_id)
	result.sort()
	return result


func try_texture(visual_id: StringName) -> Texture2D:
	if _load_error != &"" or visual_id.is_empty():
		return null
	if _texture_cache.has(visual_id):
		return _texture_cache[visual_id] as Texture2D
	var relative_path := String(_texture_paths.get(visual_id, ""))
	if relative_path.is_empty():
		return null
	var resource_path := relative_path
	if not resource_path.begins_with("res://"):
		resource_path = "res://%s" % resource_path
	var texture := ResourceLoader.load(resource_path, "Texture2D") as Texture2D
	if texture != null:
		_texture_cache[visual_id] = texture
	return texture


func _load_manifest() -> void:
	var source := FileAccess.get_file_as_string(MANIFEST_PATH)
	var parsed: Variant = JSON.parse_string(source)
	if not parsed is Dictionary:
		_load_error = MANIFEST_INVALID
		return
	var root := parsed as Dictionary
	if int(root.get("schema_version", 0)) != 1:
		_load_error = MANIFEST_INVALID
		return
	var visuals: Variant = root.get("visuals", [])
	if not visuals is Array:
		_load_error = MANIFEST_INVALID
		return
	for entry_value: Variant in visuals:
		if not entry_value is Dictionary:
			continue
		var entry := entry_value as Dictionary
		if String(entry.get("status", "")) != "adopted":
			continue
		var visual_id := StringName(String(entry.get("visual_id", "")))
		var texture_path := String(entry.get("path", ""))
		if not visual_id.is_empty() and not texture_path.is_empty():
			_texture_paths[visual_id] = texture_path
	if _texture_paths.is_empty():
		_load_error = MANIFEST_INVALID
