class_name FoundationRunnerSupport
extends RefCounted

const APP_VERSION: String = "0.2.0"
const SCHEMA_VERSION: int = SaveSchemaContract.CURRENT
const CONTENT_CODEC_VERSION: int = ContentCanonicalCodecV3.CONTENT_CODEC_VERSION_V3
const RNG_VERSION: int = 1
const HASH_VERSION: int = 1


static func utc_now() -> String:
	return Time.get_datetime_string_from_system(true, false).split(".")[0] + "Z"


static func version_properties() -> Dictionary:
	var engine_info: Dictionary = Engine.get_version_info()
	return {
		"engine_version": str(engine_info.get("string", "unknown")),
		"app_version": APP_VERSION,
		"schema_version": SCHEMA_VERSION,
		"content_codec_version": CONTENT_CODEC_VERSION,
		"rng_version": RNG_VERSION,
		"hash_version": HASH_VERSION,
		"simulation_version": 1,
		"battle_event_codec_version": 1,
		"battle_result_codec_version": 1,
	}


static func base_report(
	runner_name: String,
	started_at_utc: String,
	completed_scopes: Array[String],
	deferred_scopes: Array[String]
) -> Dictionary:
	return {
		"artifact_schema_version": 1,
		"runner": runner_name,
		"started_at_utc": started_at_utc,
		"finished_at_utc": utc_now(),
		"versions": version_properties(),
		"completed_scopes": completed_scopes,
		"deferred_scopes": deferred_scopes,
		"case_count": 0,
		"failures": [],
	}


static func write_json_artifact(path: String, payload: Dictionary) -> int:
	var absolute_path: String = ProjectSettings.globalize_path(path)
	var directory_error: int = DirAccess.make_dir_recursive_absolute(absolute_path.get_base_dir())
	if directory_error != OK:
		return directory_error
	var temporary_path: String = absolute_path + ".tmp"
	var file: FileAccess = FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	var encoded: String = JSON.stringify(payload, "\t", false, true)
	file.store_string(encoded)
	file.flush()
	var write_error: int = file.get_error()
	file = null
	if write_error != OK:
		return write_error
	var read_back: String = FileAccess.get_file_as_string(temporary_path)
	var parsed: Variant = JSON.parse_string(read_back)
	if not parsed is Dictionary:
		return ERR_PARSE_ERROR
	if FileAccess.file_exists(absolute_path):
		var remove_error: int = DirAccess.remove_absolute(absolute_path)
		if remove_error != OK:
			return remove_error
	var rename_error: int = DirAccess.rename_absolute(temporary_path, absolute_path)
	if rename_error != OK:
		return rename_error
	var final_text: String = FileAccess.get_file_as_string(absolute_path)
	if final_text != read_back:
		return ERR_FILE_CORRUPT
	return OK


static func xml_escape(value: String) -> String:
	return value.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("\"", "&quot;").replace("'", "&apos;")
