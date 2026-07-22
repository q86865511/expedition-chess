class_name MapGenerationResult
extends RefCounted

var ok: bool
var map_state: MapState
var next_map_rng_snapshot: RngSnapshot
var error: MapGenerationError

static func success(map: MapState, snapshot: RngSnapshot) -> MapGenerationResult:
	return MapGenerationResult.new(true, map, snapshot, null)

static func failure(code: StringName, path: StringName) -> MapGenerationResult:
	return MapGenerationResult.new(false, null, null, MapGenerationError.new(code, path))

func _init(p_ok: bool, p_map: MapState, p_snapshot: RngSnapshot, p_error: MapGenerationError) -> void:
	ResultInvariant.require(p_ok, p_error, p_map != null and p_snapshot != null, p_map == null and p_snapshot == null)
	ok = p_ok
	map_state = p_map.deep_clone() if p_map != null else null
	next_map_rng_snapshot = p_snapshot.deep_clone() if p_snapshot != null else null
	error = p_error.deep_clone() if p_error != null else null
