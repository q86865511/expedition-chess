class_name ProductionAssetValidator
extends RefCounted

const EXPECTED_UNIT_COUNT := 44
const EXPECTED_FRAMES_PER_UNIT := 240
const EXPECTED_SHARED_ATLASES := [
	"trait",
	"ability",
	"status_damage",
	"combat_vfx",
	"core_ui",
]


func validate(inventory_path: String) -> Dictionary:
	var issues: Array[String] = []
	var inventory := _read_json(inventory_path, issues)
	if inventory.is_empty():
		return _report(issues, 0, 0, 0, 0)
	var units: Array = inventory.get("units", [])
	var frames_per_unit := int(inventory.get("frames_per_unit", 0))
	if int(inventory.get("schema_version", 0)) != 1:
		issues.append("inventory schema_version must be 1")
	if units.size() != EXPECTED_UNIT_COUNT:
		issues.append("unit_count must be exactly %d" % EXPECTED_UNIT_COUNT)
	if int(inventory.get("unit_count", 0)) != units.size():
		issues.append("inventory unit_count does not match units")
	if frames_per_unit != EXPECTED_FRAMES_PER_UNIT:
		issues.append("frames_per_unit must be exactly %d" % EXPECTED_FRAMES_PER_UNIT)
	if String(inventory.get("imagegen_call_id", "")).is_empty():
		issues.append("inventory imagegen_call_id is required")
	if String(inventory.get("model_native_seed", "")) != "not_exposed_by_builtin_image_gen":
		issues.append("inventory must record the approved model-native seed exception")

	var unit_ids: Dictionary = {}
	var processing_seeds: Dictionary = {}
	var alpha_bounds: Dictionary = {}
	for raw_unit: Variant in units:
		if not raw_unit is Dictionary:
			issues.append("unit inventory entry must be an object")
			continue
		var unit: Dictionary = raw_unit
		var unit_id := String(unit.get("unit_id", ""))
		if unit_id.is_empty() or unit_ids.has(unit_id):
			issues.append("unit id must be present and unique: %s" % unit_id)
		unit_ids[unit_id] = true
		var seed := int(unit.get("local_processing_seed", -1))
		if seed < 0 or processing_seeds.has(seed):
			issues.append("%s local processing seed must be present and unique" % unit_id)
		processing_seeds[seed] = true
		_validate_unit(unit_id, unit, alpha_bounds, issues)

	var shared: Dictionary = inventory.get("shared_atlases", {})
	for shared_name: String in EXPECTED_SHARED_ATLASES:
		var path := "res://assets/production/shared/%s.png" % shared_name
		_validate_png(path, Vector2i(1024, 1024), true, issues)
		_validate_hash(path, String(shared.get(shared_name, "")), issues)
	if shared.size() != EXPECTED_SHARED_ATLASES.size():
		issues.append("shared atlas inventory must contain exactly five entries")

	var camp: Dictionary = inventory.get("camp", {})
	var camp_path := _res_path(String(camp.get("path", "")))
	_validate_png(camp_path, Vector2i(1280, 720), false, issues)
	_validate_hash(camp_path, String(camp.get("sha256", "")), issues)
	return _report(
		issues,
		units.size(),
		frames_per_unit,
		shared.size(),
		alpha_bounds.size()
	)


func validate_presentations(directory_path: String, inventory_path: String) -> Dictionary:
	var issues: Array[String] = []
	var inventory := _read_json(inventory_path, issues)
	var adopted_paths: Dictionary = {}
	for raw_unit: Variant in inventory.get("units", []):
		if not raw_unit is Dictionary:
			continue
		var outputs: Dictionary = raw_unit.get("outputs", {})
		for output_name: String in [
			"portrait", "board_icon", "ability_icon", "sprite_frames"
		]:
			adopted_paths[_res_path(String(outputs.get(output_name, "")))] = true
	var directory := DirAccess.open(directory_path)
	if directory == null:
		issues.append("presentation directory is missing: %s" % directory_path)
		return {
			"ok": false,
			"issues": issues,
			"presentation_count": 0,
		}
	var files: Array[String] = []
	directory.list_dir_begin()
	var file_name := directory.get_next()
	while not file_name.is_empty():
		if not directory.current_is_dir() and file_name.ends_with(".tres"):
			files.append(file_name)
		file_name = directory.get_next()
	directory.list_dir_end()
	files.sort()
	for presentation_file: String in files:
		var path := "%s/%s" % [directory_path, presentation_file]
		var presentation := load(path)
		if presentation == null:
			issues.append("could not load presentation: %s" % path)
			continue
		for property_name: String in [
			"portrait_path", "sprite_frames_path", "board_icon_path", "ability_icon_path"
		]:
			var asset_path := str(presentation.get(property_name))
			if not adopted_paths.has(asset_path):
				issues.append("%s is not in adopted inventory: %s" % [path, asset_path])
			if not FileAccess.file_exists(asset_path):
				issues.append("%s references missing asset: %s" % [path, asset_path])
		if presentation.combat_vfx_refs.is_empty():
			issues.append("%s must reference at least one committed-event VFX" % path)
		if presentation.audio_cue_refs.is_empty():
			issues.append("%s must reference at least one audio cue" % path)
	return {
		"ok": issues.is_empty(),
		"issues": issues,
		"presentation_count": files.size(),
	}


func validate_audio(inventory_path: String) -> Dictionary:
	var issues: Array[String] = []
	var inventory := _read_json(inventory_path, issues)
	var music: Array = inventory.get("music", [])
	var sfx: Array = inventory.get("sfx", [])
	if int(inventory.get("schema_version", 0)) != 1:
		issues.append("audio inventory schema_version must be 1")
	if str(inventory.get("status", "")) != "adopted":
		issues.append("audio inventory must be adopted")
	if int(inventory.get("sample_rate", 0)) != 44100:
		issues.append("audio inventory sample rate must be 44100")
	if str(inventory.get("container", "")) != "OGG":
		issues.append("audio inventory container must be OGG")
	if str(inventory.get("codec", "")) != "VORBIS":
		issues.append("audio inventory codec must be VORBIS")
	if music.size() != 5:
		issues.append("audio inventory must contain five music loops")
	if sfx.size() != 21:
		issues.append("audio inventory must contain 21 semantic SFX")
	var encoder: Dictionary = inventory.get("encoder", {})
	if str(encoder.get("soundfile_version", "")) != "0.13.1":
		issues.append("SoundFile version must be pinned to 0.13.1")
	if str(encoder.get("libsndfile_version", "")) != "1.2.2":
		issues.append("libsndfile version must be pinned to 1.2.2")
	if (
		str(encoder.get("wheel_sha256", ""))
		!= "1e70a05a0626524a69e9f0f4dd2ec174b4e9567f4d8b6c11d38b5c289be36ee9"
	):
		issues.append("SoundFile wheel SHA-256 does not match the locked encoder")
	var cue_ids: Dictionary = {}
	var stream_paths: Dictionary = {}
	for raw_entry: Variant in music:
		_validate_audio_entry(raw_entry, true, cue_ids, stream_paths, issues)
	for raw_entry: Variant in sfx:
		_validate_audio_entry(raw_entry, false, cue_ids, stream_paths, issues)
	return {
		"ok": issues.is_empty(),
		"issues": issues,
		"music_count": music.size(),
		"sfx_count": sfx.size(),
		"sample_rate": int(inventory.get("sample_rate", 0)),
		"container": str(inventory.get("container", "")),
		"codec": str(inventory.get("codec", "")),
	}


func _validate_audio_entry(
	raw_entry: Variant,
	is_music: bool,
	cue_ids: Dictionary,
	stream_paths: Dictionary,
	issues: Array[String]
) -> void:
	if not raw_entry is Dictionary:
		issues.append("audio entry must be an object")
		return
	var entry: Dictionary = raw_entry
	var cue_id := str(entry.get("cue_id", ""))
	var stream_path := _res_path(str(entry.get("path", "")))
	if cue_id.is_empty() or cue_ids.has(cue_id):
		issues.append("audio cue id must be present and unique: %s" % cue_id)
	cue_ids[cue_id] = true
	if stream_path.is_empty() or stream_paths.has(stream_path):
		issues.append("audio stream path must be present and unique: %s" % stream_path)
	stream_paths[stream_path] = true
	if not FileAccess.file_exists(stream_path):
		issues.append("%s stream is missing: %s" % [cue_id, stream_path])
		return
	_validate_hash(stream_path, str(entry.get("sha256", "")), issues)
	var stream_file := FileAccess.open(stream_path, FileAccess.READ)
	if stream_file == null or stream_file.get_buffer(4).get_string_from_ascii() != "OggS":
		issues.append("%s is not an Ogg bitstream" % stream_path)
	if int(entry.get("sample_rate", 0)) != 44100:
		issues.append("%s must use 44100 Hz" % cue_id)
	if str(entry.get("container", "")) != "OGG":
		issues.append("%s container must be OGG" % cue_id)
	if str(entry.get("codec", "")) != "VORBIS":
		issues.append("%s codec must be VORBIS" % cue_id)
	var peak_dbfs := float(entry.get("peak_dbfs", 0.0))
	if peak_dbfs > -1.0 or peak_dbfs < -24.0:
		issues.append("%s peak must remain between -24 and -1 dBFS" % cue_id)
	var expected_bus := "Music" if is_music else "SFX"
	if str(entry.get("bus", "")) != expected_bus:
		issues.append("%s must route to %s" % [cue_id, expected_bus])
	if bool(entry.get("loop", false)) != is_music:
		issues.append("%s loop flag does not match cue kind" % cue_id)
	if is_music:
		if int(entry.get("channels", 0)) != 2:
			issues.append("%s music must be stereo" % cue_id)
		if float(entry.get("loop_seam_peak", 1.0)) > 0.02:
			issues.append("%s loop seam value jump exceeds 0.02" % cue_id)
		if float(entry.get("loop_seam_derivative_peak", 1.0)) > 0.002:
			issues.append("%s loop seam derivative jump exceeds 0.002" % cue_id)
	else:
		if int(entry.get("channels", 0)) != 1:
			issues.append("%s SFX must be mono" % cue_id)
	var token := cue_id.trim_prefix("audio.")
	var cue_path := "res://content/packs/vertical_slice/audio_cues/%s.tres" % token
	if not FileAccess.file_exists(cue_path):
		issues.append("%s AudioCueDef is missing" % cue_id)
		return
	var cue := load(cue_path)
	if cue == null:
		issues.append("%s AudioCueDef cannot be loaded" % cue_id)
		return
	if str(cue.id) != cue_id:
		issues.append("%s AudioCueDef id mismatch" % cue_id)
	if str(cue.bus) != expected_bus:
		issues.append("%s AudioCueDef bus mismatch" % cue_id)
	if str(cue.stream_path) != stream_path:
		issues.append("%s AudioCueDef stream mismatch" % cue_id)
	if cue.loop != is_music:
		issues.append("%s AudioCueDef loop mismatch" % cue_id)
	var decoded_stream := load(stream_path)
	if decoded_stream == null:
		issues.append("%s cannot be decoded by runtime resource loading" % cue_id)


func _validate_unit(
	unit_id: String,
	unit: Dictionary,
	alpha_bounds: Dictionary,
	issues: Array[String]
) -> void:
	var outputs: Dictionary = unit.get("outputs", {})
	var hashes: Dictionary = unit.get("sha256", {})
	var required := {
		"source_sheet": Vector2i(1280, 1280),
		"portrait": Vector2i(256, 256),
		"board_icon": Vector2i(256, 256),
		"ability_icon": Vector2i(256, 256),
		"atlas": Vector2i(1024, 1024),
	}
	for output_name: String in required:
		var path := _res_path(String(outputs.get(output_name, "")))
		var require_alpha := output_name != "source_sheet"
		var image := _validate_png(path, required[output_name], require_alpha, issues)
		_validate_hash(path, String(hashes.get(output_name, "")), issues)
		if output_name == "source_sheet" and image != null:
			var chroma := image.get_pixel(0, 0)
			if chroma.r8 < 245 or chroma.g8 > 10 or chroma.b8 < 245:
				issues.append("%s source sheet must retain #ff00ff chroma" % unit_id)
		if output_name == "board_icon" and image != null:
			var used := image.get_used_rect()
			alpha_bounds["%dx%d" % [used.size.x, used.size.y]] = true
		if output_name == "atlas" and image != null:
			_validate_atlas(unit_id, image, issues)

	var frames_path := _res_path(String(outputs.get("sprite_frames", "")))
	_validate_hash(frames_path, String(hashes.get("sprite_frames", "")), issues)
	if not FileAccess.file_exists(frames_path):
		issues.append("%s SpriteFrames resource is missing: %s" % [unit_id, frames_path])
	else:
		var frames := load(frames_path) as SpriteFrames
		if frames == null:
			issues.append("%s SpriteFrames resource cannot be loaded" % unit_id)
		elif frames.get_animation_names().size() != EXPECTED_FRAMES_PER_UNIT:
			issues.append("%s SpriteFrames must expose 240 named animations" % unit_id)

	var provenance_path := _res_path(String(unit.get("provenance", "")))
	var provenance := _read_json(provenance_path, issues)
	if String(provenance.get("status", "")) != "adopted":
		issues.append("%s provenance must be adopted" % unit_id)
	if String(provenance.get("imagegen_call_id", "")).is_empty():
		issues.append("%s provenance lacks ImageGen call id" % unit_id)
	if int(provenance.get("local_processing_seed", -1)) != int(
		unit.get("local_processing_seed", -2)
	):
		issues.append("%s provenance seed does not match inventory" % unit_id)
	var provenance_hashes: Dictionary = provenance.get("outputs_sha256", {})
	for output_name: String in hashes:
		if String(provenance_hashes.get(output_name, "")) != String(hashes[output_name]):
			issues.append("%s provenance hash mismatch for %s" % [unit_id, output_name])


func _validate_atlas(unit_id: String, image: Image, issues: Array[String]) -> void:
	for frame_index in range(EXPECTED_FRAMES_PER_UNIT):
		var origin := Vector2i((frame_index % 16) * 64, (frame_index / 16) * 64)
		var frame := image.get_region(Rect2i(origin, Vector2i(64, 64)))
		if frame.get_used_rect().size == Vector2i.ZERO:
			issues.append("%s frame %d is empty" % [unit_id, frame_index])
			break
	var cue_counts: Array[int] = []
	for frame_index: int in [0, 80, 160]:
		var origin := Vector2i((frame_index % 16) * 64, (frame_index / 16) * 64)
		var count := 0
		for y in range(48, 62):
			for x in range(31, 61):
				var pixel := image.get_pixelv(origin + Vector2i(x, y))
				if (
					pixel.a8 > 0
					and pixel.r8 >= 225
					and pixel.g8 >= 215
					and pixel.b8 >= 195
				):
					count += 1
		cue_counts.append(count)
	if not (
		cue_counts.size() == 3
		and cue_counts[0] > 0
		and cue_counts[1] > cue_counts[0]
		and cue_counts[2] > cue_counts[1]
	):
		issues.append("%s star tiers lack increasing non-color diamond cues" % unit_id)


func _validate_png(
	path: String,
	expected_size: Vector2i,
	require_alpha: bool,
	issues: Array[String]
) -> Image:
	if path.is_empty() or not FileAccess.file_exists(path):
		issues.append("PNG asset is missing: %s" % path)
		return null
	var image := Image.new()
	var load_error := image.load(ProjectSettings.globalize_path(path))
	if load_error != OK or image.is_empty():
		issues.append("PNG asset cannot be decoded: %s" % path)
		return null
	if image.get_size() != expected_size:
		issues.append(
			"%s size must be %dx%d, got %dx%d" % [
				path,
				expected_size.x,
				expected_size.y,
				image.get_width(),
				image.get_height(),
			]
		)
	if require_alpha and not image.detect_alpha():
		issues.append("%s must contain transparency" % path)
	return image


func _validate_hash(path: String, expected: String, issues: Array[String]) -> void:
	if expected.length() != 64:
		issues.append("%s is missing a pinned SHA-256" % path)
		return
	if not FileAccess.file_exists(path):
		return
	var actual := FileAccess.get_sha256(path)
	if actual != expected:
		issues.append("%s SHA-256 mismatch" % path)


func _read_json(path: String, issues: Array[String]) -> Dictionary:
	if path.is_empty() or not FileAccess.file_exists(path):
		issues.append("JSON file is missing: %s" % path)
		return {}
	var handle := FileAccess.open(path, FileAccess.READ)
	if handle == null:
		issues.append("JSON file cannot be opened: %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(handle.get_as_text())
	if not parsed is Dictionary:
		issues.append("JSON root must be an object: %s" % path)
		return {}
	return parsed


func _res_path(path: String) -> String:
	if path.begins_with("res://") or path.is_empty():
		return path
	return "res://%s" % path


func _report(
	issues: Array[String],
	unit_count: int,
	frames_per_unit: int,
	shared_atlas_count: int,
	distinct_alpha_bounds: int
) -> Dictionary:
	return {
		"ok": issues.is_empty(),
		"issues": issues,
		"unit_count": unit_count,
		"frames_per_unit": frames_per_unit,
		"shared_atlas_count": shared_atlas_count,
		"distinct_alpha_bounds": distinct_alpha_bounds,
	}
