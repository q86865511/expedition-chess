class_name ProductionAssetValidator
extends RefCounted

const EXPECTED_UNIT_COUNT := 44
const EXPECTED_FRAMES_PER_UNIT := 240
const EXPECTED_ANIMATIONS_PER_UNIT := 72
const MIN_ALPHA_COVERAGE := 0.15
const MAX_ALPHA_COVERAGE := 0.85
const MAX_CHROMA_LEAK := 0.001
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
		return _report(issues, 0, 0, 0, "", 1.0, 1.0)
	var units: Array = inventory.get("units", [])
	var frames_per_unit := int(inventory.get("frames_per_unit", 0))
	var inventory_status := String(inventory.get("status", ""))
	if int(inventory.get("schema_version", 0)) != 2:
		issues.append("inventory schema_version must be 2")
	if inventory_status != "adopted":
		issues.append("production asset inventory must be adopted")
	if units.size() != EXPECTED_UNIT_COUNT:
		issues.append("unit_count must be exactly %d" % EXPECTED_UNIT_COUNT)
	if int(inventory.get("unit_count", 0)) != units.size():
		issues.append("inventory unit_count does not match units")
	if frames_per_unit != EXPECTED_FRAMES_PER_UNIT:
		issues.append("frames_per_unit must be exactly %d" % EXPECTED_FRAMES_PER_UNIT)
	if int(inventory.get("animations_per_unit", 0)) != EXPECTED_ANIMATIONS_PER_UNIT:
		issues.append("animations_per_unit must be exactly %d" % EXPECTED_ANIMATIONS_PER_UNIT)
	_validate_evidence_file(inventory.get("attempt_ledger", {}), issues)
	var aggregate_review: Dictionary = inventory.get("review_record", {})
	_validate_evidence_file(aggregate_review, issues)
	var aggregate_review_sha := String(aggregate_review.get("sha256", ""))
	var processor: Dictionary = inventory.get("processor", {})
	for field: String in ["python", "python_implementation", "pillow", "numpy", "script"]:
		if String(processor.get(field, "")).is_empty():
			issues.append("inventory processor.%s is required" % field)
	_validate_hash(
		_res_path(String(processor.get("script", ""))),
		String(processor.get("script_sha256", "")),
		issues
	)

	var unit_ids: Dictionary = {}
	var processing_seeds: Dictionary = {}
	var adopted_attempt_ids: Dictionary = {}
	var player_portraits: Dictionary = {}
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
		if String(unit.get("status", "")) != "adopted":
			issues.append("%s inventory entry must be adopted" % unit_id)
		var attempt_id := String(unit.get("adopted_attempt_id", ""))
		if attempt_id.is_empty() or adopted_attempt_ids.has(attempt_id):
			issues.append("%s adopted attempt must be present and unique" % unit_id)
		adopted_attempt_ids[attempt_id] = true
		_validate_unit(unit_id, unit, player_portraits, issues)

	var shared: Dictionary = inventory.get("shared_atlases", {})
	for shared_name: String in EXPECTED_SHARED_ATLASES:
		var entry: Dictionary = shared.get(shared_name, {})
		if String(entry.get("status", "")) != "adopted":
			issues.append("shared atlas %s must be adopted" % shared_name)
		var path := _res_path(String(entry.get("path", "")))
		var source_path := _res_path(String(entry.get("source_path", "")))
		_validate_hash(source_path, String(entry.get("source_sha256", "")), issues)
		var shared_image := _validate_png(path, Vector2i(1024, 1024), true, true, issues)
		_validate_hash(path, String(entry.get("sha256", "")), issues)
		_validate_review_sha(entry, "shared atlas %s" % shared_name, aggregate_review_sha, issues)
		if shared_image == null:
			continue
	if shared.size() != EXPECTED_SHARED_ATLASES.size():
		issues.append("shared atlas inventory must contain exactly five entries")

	var camp: Dictionary = inventory.get("camp", {})
	if String(camp.get("status", "")) != "adopted":
		issues.append("camp inventory entry must be adopted")
	var camp_path := _res_path(String(camp.get("path", "")))
	_validate_png(camp_path, Vector2i(1280, 720), false, false, issues)
	_validate_hash(camp_path, String(camp.get("sha256", "")), issues)
	_validate_hash(
		_res_path(String(camp.get("source_path", ""))),
		String(camp.get("source_sha256", "")),
		issues
	)
	_validate_review_sha(camp, "camp", aggregate_review_sha, issues)
	var similarity := _validate_player_similarity(player_portraits, issues)
	return _report(
		issues,
		units.size(),
		frames_per_unit,
		shared.size(),
		inventory_status,
		float(similarity.get("max_iou", 1.0)),
		float(similarity.get("max_ssim", 1.0))
	)


func validate_attempt_ledger(ledger_path: String, inventory_path: String) -> Dictionary:
	var issues: Array[String] = []
	var ledger := _read_json(ledger_path, issues)
	var inventory := _read_json(inventory_path, issues)
	var attempts: Array = ledger.get("attempts", [])
	if int(ledger.get("schema_version", 0)) != 1:
		issues.append("attempt ledger schema_version must be 1")
	var adopted_by_unit: Dictionary = {}
	var output_ids: Dictionary = {}
	var adopted_count := 0
	var unreviewed_count := 0
	var duplicate_call_id_count := 0
	for raw_attempt: Variant in attempts:
		if not raw_attempt is Dictionary:
			issues.append("attempt ledger entry must be an object")
			continue
		var attempt: Dictionary = raw_attempt
		var attempt_id := String(attempt.get("attempt_id", ""))
		var unit_id := String(attempt.get("unit_id", ""))
		var status := String(attempt.get("status", ""))
		var generation: Dictionary = attempt.get("generation", {})
		var output_id := String(generation.get("imagegen_output_id", ""))
		if not bool(generation.get("independent_call", false)):
			issues.append("%s must be an independent ImageGen call" % attempt_id)
		if output_id.is_empty():
			issues.append("%s lacks imagegen_output_id" % attempt_id)
		elif output_ids.has(output_id):
			duplicate_call_id_count += 1
			issues.append("duplicate ImageGen output id: %s" % output_id)
		else:
			output_ids[output_id] = true
		if String(generation.get("model_native_seed", "")) != "not_exposed_by_builtin_image_gen":
			issues.append("%s must record the model-native seed exception" % attempt_id)
		var source: Dictionary = attempt.get("raw_source", {})
		_validate_hash(
			_res_path(String(source.get("path", ""))),
			String(source.get("sha256", "")),
			issues
		)
		var review: Dictionary = attempt.get("review", {})
		var decision := String(review.get("decision", "pending"))
		if decision == "pending" or String(review.get("reviewer", "")).is_empty():
			unreviewed_count += 1
		if status == "adopted":
			adopted_count += 1
			if decision != "adopted":
				issues.append("%s adopted status lacks adopted review" % attempt_id)
			if adopted_by_unit.has(unit_id):
				issues.append("%s has multiple adopted attempts" % unit_id)
			adopted_by_unit[unit_id] = attempt
		elif status == "rejected":
			if decision != "rejected":
				issues.append("%s rejected status lacks rejected review" % attempt_id)
		elif status == "generated":
			issues.append("%s remains generated after adoption closure" % attempt_id)
		else:
			issues.append("%s has invalid status %s" % [attempt_id, status])
		var review_sha: Variant = review.get("review_record_sha256", null)
		if status == "adopted":
			if not review_sha is String or str(review_sha).length() != 64:
				issues.append("%s adopted attempt lacks review SHA-256" % attempt_id)
		elif review_sha != null:
			if not review_sha is String or str(review_sha).length() != 64:
				issues.append("%s review SHA-256 is malformed" % attempt_id)
	if adopted_by_unit.size() != EXPECTED_UNIT_COUNT:
		issues.append("attempt ledger must have exactly 44 adopted units")
	for raw_unit: Variant in inventory.get("units", []):
		if not raw_unit is Dictionary:
			continue
		var unit: Dictionary = raw_unit
		var unit_id := String(unit.get("unit_id", ""))
		if not adopted_by_unit.has(unit_id):
			issues.append("inventory unit is not adopted in ledger: %s" % unit_id)
			continue
		var attempt: Dictionary = adopted_by_unit[unit_id]
		if String(unit.get("adopted_attempt_id", "")) != String(attempt.get("attempt_id", "")):
			issues.append("%s inventory attempt link mismatch" % unit_id)
		var inventory_source: Dictionary = unit.get("source", {})
		var attempt_source: Dictionary = attempt.get("raw_source", {})
		if (
			String(inventory_source.get("path", "")) != String(attempt_source.get("path", ""))
			or String(inventory_source.get("sha256", "")) != String(attempt_source.get("sha256", ""))
		):
			issues.append("%s inventory source does not match adopted attempt" % unit_id)
	return {
		"ok": issues.is_empty(),
		"issues": issues,
		"attempt_count": attempts.size(),
		"unit_count": adopted_by_unit.size(),
		"adopted_count": adopted_count,
		"unreviewed_count": unreviewed_count,
		"duplicate_call_id_count": duplicate_call_id_count,
	}


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
	if int(inventory.get("sample_rate", 0)) != 48000:
		issues.append("audio inventory sample rate must be 48000")
	if int(inventory.get("channels", 0)) != 2:
		issues.append("audio inventory channels must be stereo")
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
	if not is_equal_approx(float(encoder.get("vorbis_quality", -1.0)), 0.5):
		issues.append("Vorbis quality must be pinned to 0.5")
	var synthesis: Dictionary = inventory.get("synthesis", {})
	if int(synthesis.get("music_seconds", 0)) != 24:
		issues.append("music synthesis duration must be 24 seconds")
	var cue_ids: Dictionary = {}
	var stream_paths: Dictionary = {}
	for raw_entry: Variant in music:
		_validate_audio_entry(raw_entry, true, cue_ids, stream_paths, issues)
	for raw_entry: Variant in sfx:
		_validate_audio_entry(raw_entry, false, cue_ids, stream_paths, issues)
	var max_true_peak_dbfs := -1000.0
	var max_loop_seam_rms_dbfs := -1000.0
	for raw_entry: Variant in music + sfx:
		if raw_entry is Dictionary:
			max_true_peak_dbfs = maxf(
				max_true_peak_dbfs,
				float((raw_entry as Dictionary).get("true_peak_dbfs", 0.0))
			)
	for raw_entry: Variant in music:
		if raw_entry is Dictionary:
			max_loop_seam_rms_dbfs = maxf(
				max_loop_seam_rms_dbfs,
				float((raw_entry as Dictionary).get("loop_seam_rms_dbfs", 0.0))
			)
	return {
		"ok": issues.is_empty(),
		"issues": issues,
		"music_count": music.size(),
		"sfx_count": sfx.size(),
		"sample_rate": int(inventory.get("sample_rate", 0)),
		"channels": int(inventory.get("channels", 0)),
		"vorbis_quality": float(encoder.get("vorbis_quality", -1.0)),
		"music_seconds": int(synthesis.get("music_seconds", 0)),
		"max_true_peak_dbfs": max_true_peak_dbfs,
		"max_loop_seam_rms_dbfs": max_loop_seam_rms_dbfs,
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
	if int(entry.get("sample_rate", 0)) != 48000:
		issues.append("%s must use 48000 Hz" % cue_id)
	if str(entry.get("container", "")) != "OGG":
		issues.append("%s container must be OGG" % cue_id)
	if str(entry.get("codec", "")) != "VORBIS":
		issues.append("%s codec must be VORBIS" % cue_id)
	var true_peak_dbfs := float(entry.get("true_peak_dbfs", 0.0))
	if true_peak_dbfs > -1.0:
		issues.append("%s decoded true peak must be at most -1 dBFS" % cue_id)
	var expected_bus := "Music" if is_music else ("UI" if cue_id.begins_with("audio.ui_") else "SFX")
	if str(entry.get("bus", "")) != expected_bus:
		issues.append("%s must route to %s" % [cue_id, expected_bus])
	if bool(entry.get("loop", false)) != is_music:
		issues.append("%s loop flag does not match cue kind" % cue_id)
	if int(entry.get("channels", 0)) != 2:
		issues.append("%s must be stereo" % cue_id)
	var duration := float(entry.get("duration_seconds", 0.0))
	if is_music:
		if duration < 20.0 or duration > 40.0:
			issues.append("%s music duration must be between 20 and 40 seconds" % cue_id)
		if float(entry.get("loop_seam_rms_dbfs", 0.0)) > -45.0:
			issues.append("%s 50ms loop seam RMS must be at most -45 dBFS" % cue_id)
	elif duration < 0.08 or duration > 2.0:
		issues.append("%s SFX duration must be between 0.08 and 2.0 seconds" % cue_id)
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
	player_portraits: Dictionary,
	issues: Array[String]
) -> void:
	var outputs: Dictionary = unit.get("outputs", {})
	var hashes: Dictionary = unit.get("sha256", {})
	var source: Dictionary = unit.get("source", {})
	_validate_hash(
		_res_path(String(source.get("path", ""))),
		String(source.get("sha256", "")),
		issues
	)
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
		var image := _validate_png(
			path,
			required[output_name],
			require_alpha,
			require_alpha,
			issues
		)
		_validate_hash(path, String(hashes.get(output_name, "")), issues)
		if output_name == "source_sheet" and image != null:
			var chroma := image.get_pixel(0, 0)
			if chroma.r8 < 245 or chroma.g8 > 10 or chroma.b8 < 245:
				issues.append("%s source sheet must retain #ff00ff chroma" % unit_id)
		if output_name == "atlas" and image != null:
			_validate_atlas(unit_id, image, issues)
		if output_name == "portrait" and image != null and unit_id.begins_with("unit.slice_player_"):
			player_portraits[unit_id] = _portrait_similarity_data(image)

	var frames_path := _res_path(String(outputs.get("sprite_frames", "")))
	_validate_hash(frames_path, String(hashes.get("sprite_frames", "")), issues)
	if not FileAccess.file_exists(frames_path):
		issues.append("%s SpriteFrames resource is missing: %s" % [unit_id, frames_path])
	else:
		var frames := load(frames_path) as SpriteFrames
		if frames == null:
			issues.append("%s SpriteFrames resource cannot be loaded" % unit_id)
		else:
			_validate_sprite_frames(unit_id, frames, issues)

	var provenance_path := _res_path(String(unit.get("provenance", "")))
	var provenance := _read_json(provenance_path, issues)
	if int(provenance.get("schema_version", 0)) != 2:
		issues.append("%s provenance schema_version must be 2" % unit_id)
	if String(provenance.get("status", "")) != "adopted":
		issues.append("%s provenance must be adopted" % unit_id)
	if String(provenance.get("unit_id", "")) != unit_id:
		issues.append("%s provenance unit id mismatch" % unit_id)
	if String(provenance.get("adopted_attempt_id", "")) != String(
		unit.get("adopted_attempt_id", "")
	):
		issues.append("%s provenance adopted attempt mismatch" % unit_id)
	var provenance_source: Dictionary = provenance.get("source_attempt", {})
	if (
		String(provenance_source.get("path", "")) != String(source.get("path", ""))
		or String(provenance_source.get("sha256", "")) != String(source.get("sha256", ""))
	):
		issues.append("%s provenance source mismatch" % unit_id)
	if String(provenance_source.get("imagegen_output_id", "")).is_empty():
		issues.append("%s provenance lacks ImageGen output id" % unit_id)
	if String(provenance_source.get("model_native_seed", "")) != "not_exposed_by_builtin_image_gen":
		issues.append("%s provenance seed exception mismatch" % unit_id)
	var review: Dictionary = provenance.get("review", {})
	_validate_evidence_file(review, issues)
	if String(review.get("decision", "")) != "adopted":
		issues.append("%s provenance review must be adopted" % unit_id)
	if int(provenance.get("local_processing_seed", -1)) != int(
		unit.get("local_processing_seed", -2)
	):
		issues.append("%s provenance seed does not match inventory" % unit_id)
	var provenance_hashes: Dictionary = provenance.get("outputs_sha256", {})
	for output_name: String in hashes:
		if String(provenance_hashes.get(output_name, "")) != String(hashes[output_name]):
			issues.append("%s provenance hash mismatch for %s" % [unit_id, output_name])


func _validate_sprite_frames(
	unit_id: String,
	frames: SpriteFrames,
	issues: Array[String]
) -> void:
	if frames.get_animation_names().size() != EXPECTED_ANIMATIONS_PER_UNIT:
		issues.append("%s SpriteFrames must expose exactly 72 animations" % unit_id)
	var actions := [
		{"name": "idle", "frames": 2, "speed": 4.0, "loop": true},
		{"name": "move", "frames": 4, "speed": 8.0, "loop": true},
		{"name": "attack", "frames": 4, "speed": 10.0, "loop": false},
		{"name": "cast", "frames": 4, "speed": 10.0, "loop": false},
		{"name": "hit", "frames": 2, "speed": 8.0, "loop": false},
		{"name": "death", "frames": 4, "speed": 8.0, "loop": false},
	]
	var total_frames := 0
	for star in range(1, 4):
		for direction: String in ["n", "e", "s", "w"]:
			for action: Dictionary in actions:
				var animation := StringName(
					"%s_%s_star%d" % [action.name, direction, star]
				)
				if not frames.has_animation(animation):
					issues.append("%s missing animation %s" % [unit_id, animation])
					continue
				var frame_count := frames.get_frame_count(animation)
				total_frames += frame_count
				if frame_count != int(action.frames):
					issues.append("%s %s frame count mismatch" % [unit_id, animation])
				if not is_equal_approx(frames.get_animation_speed(animation), float(action.speed)):
					issues.append("%s %s speed mismatch" % [unit_id, animation])
				if frames.get_animation_loop(animation) != bool(action.loop):
					issues.append("%s %s loop mismatch" % [unit_id, animation])
	if total_frames != EXPECTED_FRAMES_PER_UNIT:
		issues.append("%s SpriteFrames must reference exactly 240 frames" % unit_id)


func _validate_atlas(unit_id: String, image: Image, issues: Array[String]) -> void:
	var base_hashes: Dictionary = {}
	for frame_index in range(EXPECTED_FRAMES_PER_UNIT):
		var origin := Vector2i((frame_index % 16) * 64, (frame_index / 16) * 64)
		var frame := image.get_region(Rect2i(origin, Vector2i(64, 64)))
		if frame.get_used_rect().size == Vector2i.ZERO:
			issues.append("%s frame %d is empty" % [unit_id, frame_index])
			break
		if frame_index < 80:
			var hash_context := HashingContext.new()
			hash_context.start(HashingContext.HASH_SHA256)
			hash_context.update(frame.get_data())
			var digest: String = hash_context.finish().hex_encode()
			if base_hashes.has(digest):
				issues.append("%s duplicates a base action/direction frame" % unit_id)
				break
			base_hashes[digest] = true
	for frame_index in range(EXPECTED_FRAMES_PER_UNIT, 256):
		var origin := Vector2i((frame_index % 16) * 64, (frame_index / 16) * 64)
		if image.get_region(Rect2i(origin, Vector2i(64, 64))).get_used_rect().size != Vector2i.ZERO:
			issues.append("%s atlas cells 240-255 must remain transparent" % unit_id)
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
	enforce_pixel_contract: bool,
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
	if enforce_pixel_contract:
		var opaque_count := 0
		var chroma_count := 0
		for y in range(image.get_height()):
			for x in range(image.get_width()):
				var pixel := image.get_pixel(x, y)
				if pixel.a8 == 0:
					continue
				opaque_count += 1
				if pixel.r8 >= 220 and pixel.g8 <= 90 and pixel.b8 >= 220:
					chroma_count += 1
		var coverage := float(opaque_count) / float(maxi(1, image.get_width() * image.get_height()))
		if coverage < MIN_ALPHA_COVERAGE or coverage > MAX_ALPHA_COVERAGE:
			issues.append(
				"%s alpha coverage %.6f must be within %.2f-%.2f" % [
					path, coverage, MIN_ALPHA_COVERAGE, MAX_ALPHA_COVERAGE
				]
			)
		var chroma_leak := float(chroma_count) / float(maxi(1, opaque_count))
		if chroma_leak > MAX_CHROMA_LEAK:
			issues.append(
				"%s opaque chroma leak %.6f exceeds %.4f" % [
					path, chroma_leak, MAX_CHROMA_LEAK
				]
			)
	return image


func _portrait_similarity_data(image: Image) -> Dictionary:
	var mask := PackedByteArray()
	var grayscale := PackedFloat32Array()
	mask.resize(image.get_width() * image.get_height())
	grayscale.resize(mask.size())
	var index := 0
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var pixel := image.get_pixel(x, y)
			mask[index] = 1 if pixel.a8 > 0 else 0
			grayscale[index] = (
				(0.2126 * pixel.r + 0.7152 * pixel.g + 0.0722 * pixel.b) * pixel.a
			)
			index += 1
	return {"mask": mask, "grayscale": grayscale}


func _validate_player_similarity(
	portraits: Dictionary,
	issues: Array[String]
) -> Dictionary:
	if portraits.size() != 32:
		issues.append("player portrait similarity gate requires exactly 32 portraits")
		return {"max_iou": 1.0, "max_ssim": 1.0}
	var ids: Array = portraits.keys()
	ids.sort()
	var max_iou := 0.0
	var max_ssim := -1.0
	for left_index in range(ids.size()):
		for right_index in range(left_index + 1, ids.size()):
			var left: Dictionary = portraits[ids[left_index]]
			var right: Dictionary = portraits[ids[right_index]]
			var mask_left: PackedByteArray = left.mask
			var mask_right: PackedByteArray = right.mask
			var gray_left: PackedFloat32Array = left.grayscale
			var gray_right: PackedFloat32Array = right.grayscale
			var intersection := 0
			var union := 0
			var sum_left := 0.0
			var sum_right := 0.0
			var sum_left_sq := 0.0
			var sum_right_sq := 0.0
			var sum_cross := 0.0
			for pixel_index in range(mask_left.size()):
				if mask_left[pixel_index] > 0 and mask_right[pixel_index] > 0:
					intersection += 1
				if mask_left[pixel_index] > 0 or mask_right[pixel_index] > 0:
					union += 1
				var left_value := float(gray_left[pixel_index])
				var right_value := float(gray_right[pixel_index])
				sum_left += left_value
				sum_right += right_value
				sum_left_sq += left_value * left_value
				sum_right_sq += right_value * right_value
				sum_cross += left_value * right_value
			var iou := float(intersection) / float(maxi(1, union))
			max_iou = maxf(max_iou, iou)
			var count := float(mask_left.size())
			var mean_left := sum_left / count
			var mean_right := sum_right / count
			var variance_left := maxf(0.0, sum_left_sq / count - mean_left * mean_left)
			var variance_right := maxf(0.0, sum_right_sq / count - mean_right * mean_right)
			var covariance := sum_cross / count - mean_left * mean_right
			var ssim := (
				((2.0 * mean_left * mean_right + 0.0001) * (2.0 * covariance + 0.0009))
				/ (
					(mean_left * mean_left + mean_right * mean_right + 0.0001)
					* (variance_left + variance_right + 0.0009)
				)
			)
			max_ssim = maxf(max_ssim, ssim)
	if max_iou >= 0.92:
		issues.append("player silhouette IoU %.6f must be below 0.92" % max_iou)
	if max_ssim >= 0.95:
		issues.append("player portrait SSIM %.6f must be below 0.95" % max_ssim)
	return {"max_iou": max_iou, "max_ssim": max_ssim}


func _validate_evidence_file(raw_entry: Variant, issues: Array[String]) -> void:
	if not raw_entry is Dictionary:
		issues.append("evidence file entry must be an object")
		return
	var entry: Dictionary = raw_entry
	_validate_hash(
		_res_path(String(entry.get("path", ""))),
		String(entry.get("sha256", "")),
		issues
	)


func _validate_review_sha(
	entry: Dictionary,
	label: String,
	expected_sha: String,
	issues: Array[String]
) -> void:
	var review_sha := String(entry.get("review_record_sha256", ""))
	if review_sha.length() != 64 or review_sha != expected_sha:
		issues.append("%s review SHA-256 does not match aggregate review" % label)


func _validate_hash(path: String, expected: String, issues: Array[String]) -> void:
	if expected.length() != 64:
		issues.append("%s is missing a pinned SHA-256" % path)
		return
	if path.is_empty() or not FileAccess.file_exists(path):
		issues.append("hash-pinned file is missing: %s" % path)
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
	inventory_status: String,
	max_player_silhouette_iou: float,
	max_player_ssim: float
) -> Dictionary:
	return {
		"ok": issues.is_empty(),
		"issues": issues,
		"unit_count": unit_count,
		"frames_per_unit": frames_per_unit,
		"shared_atlas_count": shared_atlas_count,
		"animation_count_per_unit": EXPECTED_ANIMATIONS_PER_UNIT,
		"inventory_status": inventory_status,
		"max_player_silhouette_iou": max_player_silhouette_iou,
		"max_player_ssim": max_player_ssim,
	}
