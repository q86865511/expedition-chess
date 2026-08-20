class_name SettingsRepository
extends Node

signal settings_changed
signal settings_committed(snapshot: SettingsSnapshot)

const MAIN_PATH: StringName = &"settings-v1.json"
const TMP_PATH: StringName = &"settings-v1.tmp"
const BACKUP_PATH: StringName = &"settings-v1.backup"

const INVALID_ENUM: StringName = &"SETTINGS_INVALID_ENUM"
const FIELD_OUT_OF_RANGE: StringName = &"SETTINGS_FIELD_OUT_OF_RANGE"
const INVALID_FIELD_TYPE: StringName = &"SETTINGS_INVALID_FIELD_TYPE"
const UNSUPPORTED_FUTURE_VERSION: StringName = &"UNSUPPORTED_FUTURE_VERSION"
const FUTURE_VERSION_PRESERVED: StringName = &"SETTINGS_FUTURE_VERSION_PRESERVED"
const EXPECTED_DIGEST_MISMATCH: StringName = &"SETTINGS_EXPECTED_DIGEST_MISMATCH"
const STORAGE_FAULT: StringName = &"SETTINGS_STORAGE_FAULT"
const CORRUPT_ARCHIVED: StringName = &"SETTINGS_CORRUPT_ARCHIVED"

const MIN_VOLUME_DB: float = -80.0
const MAX_VOLUME_DB: float = 6.0
const _VALID_LOCALES: Array[StringName] = [&"zh_TW", &"en"]
const _VALID_UI_SCALES: Array[int] = [100, 125, 150]
const _VALID_COLOR_VISION_MODES: Array[StringName] = [
	&"default",
	&"protanopia",
	&"deuteranopia",
	&"tritanopia",
]
const _VALID_DAMAGE_DENSITIES: Array[StringName] = [&"off", &"reduced", &"full"]

var _storage: SettingsStoragePort
var _os_locale_provider: Callable
var _committed: SettingsSnapshot = SettingsSnapshot.new()
var _future_bytes: PackedByteArray = PackedByteArray()
var _future_digest: String = ""
var _main_exists: bool = false

# Kept until all foundation consumers have migrated from the pre-G2 facade.
var _master_volume_db: float = 0.0
var _pixel_scale: int = 1


class SettingsDiagnostic:
	extends RefCounted

	var code: StringName


	func _init(p_code: StringName) -> void:
		code = p_code


class SettingsRepositoryResult:
	extends RefCounted

	var ok: bool
	var snapshot: SettingsSnapshot
	var error: SettingsDiagnostic
	var warning: SettingsDiagnostic
	var warnings: Array[SettingsDiagnostic] = []


	func _init(
		p_ok: bool,
		p_snapshot: SettingsSnapshot,
		p_error_code: StringName = &"",
		p_warning_code: StringName = &""
	) -> void:
		ok = p_ok
		snapshot = p_snapshot.deep_clone() if p_snapshot != null else null
		error = SettingsDiagnostic.new(p_error_code) if not p_error_code.is_empty() else null
		warning = (
			SettingsDiagnostic.new(p_warning_code)
			if not p_warning_code.is_empty()
			else null
		)
		if warning != null:
			warnings.append(SettingsDiagnostic.new(warning.code))


class FileSettingsStorage:
	extends SettingsStoragePort

	const BASE_PATH := "user://"


	func read_bytes(path: StringName) -> SettingsStorageResult:
		var resolved := _resolve(path)
		if not FileAccess.file_exists(resolved):
			return SettingsStorageResult.success(false)
		var file := FileAccess.open(resolved, FileAccess.READ)
		if file == null:
			return _failure()
		var bytes := file.get_buffer(file.get_length())
		var read_error := file.get_error()
		file.close()
		if read_error != OK and read_error != ERR_FILE_EOF:
			return _failure()
		return SettingsStorageResult.success(true, bytes)


	func write_bytes(path: StringName, bytes: PackedByteArray) -> SettingsStorageResult:
		if not _ensure_parent(path):
			return _failure()
		var file := FileAccess.open(_resolve(path), FileAccess.WRITE)
		if file == null:
			return _failure()
		file.store_buffer(bytes)
		var write_error := file.get_error()
		file.close()
		return SettingsStorageResult.success() if write_error == OK else _failure()


	func promote_bytes(source: StringName, destination: StringName) -> SettingsStorageResult:
		var source_path := _resolve(source)
		var destination_path := _resolve(destination)
		if not FileAccess.file_exists(source_path) or not _ensure_parent(destination):
			return _failure()
		var had_destination := FileAccess.file_exists(destination_path)
		if had_destination:
			var backup_result := copy_bytes(destination, BACKUP_PATH)
			if not backup_result.ok:
				return _failure()
			var remove_error := DirAccess.remove_absolute(
				ProjectSettings.globalize_path(destination_path)
			)
			if remove_error != OK:
				return _failure()
		var rename_error := DirAccess.rename_absolute(
			ProjectSettings.globalize_path(source_path),
			ProjectSettings.globalize_path(destination_path)
		)
		if rename_error != OK:
			if had_destination:
				restore_bytes(BACKUP_PATH, destination)
			return _failure()
		return SettingsStorageResult.success()


	func copy_bytes(source: StringName, destination: StringName) -> SettingsStorageResult:
		var read_result := read_bytes(source)
		if not read_result.ok or not read_result.exists:
			return _failure()
		return write_bytes(destination, read_result.bytes_value())


	func restore_bytes(source: StringName, destination: StringName) -> SettingsStorageResult:
		return copy_bytes(source, destination)


	func remove_bytes(path: StringName) -> SettingsStorageResult:
		var resolved := _resolve(path)
		if not FileAccess.file_exists(resolved):
			return SettingsStorageResult.success()
		var remove_error := DirAccess.remove_absolute(
			ProjectSettings.globalize_path(resolved)
		)
		return SettingsStorageResult.success() if remove_error == OK else _failure()


	func _resolve(path: StringName) -> String:
		return "%s%s" % [BASE_PATH, String(path)]


	func _ensure_parent(path: StringName) -> bool:
		var resolved := _resolve(path)
		var absolute_parent := ProjectSettings.globalize_path(resolved.get_base_dir())
		return DirAccess.make_dir_recursive_absolute(absolute_parent) == OK


	func _failure() -> SettingsStorageResult:
		return SettingsStorageResult.failure(STORAGE_FAULT)


func _init(storage: SettingsStoragePort = null) -> void:
	_storage = storage if storage != null else FileSettingsStorage.new()


func bind_os_locale_provider(provider: Callable) -> void:
	_os_locale_provider = provider


func load() -> SettingsRepositoryResult:
	var read_result: SettingsStorageResult = _storage.read_bytes(MAIN_PATH)
	if not _storage_ok(read_result):
		return _failure(STORAGE_FAULT)
	if not read_result.exists:
		_commit_in_memory(_first_launch_snapshot(), false)
		_clear_future_lock()
		return _success(_committed)

	var source_bytes: PackedByteArray = read_result.bytes_value()
	_main_exists = true
	var parser := JSON.new()
	var parse_error := parser.parse(source_bytes.get_string_from_utf8())
	if parse_error != OK:
		return _load_corrupt(source_bytes, CORRUPT_ARCHIVED)
	var parsed: Variant = parser.data
	if not parsed is Dictionary:
		return _load_corrupt(source_bytes, CORRUPT_ARCHIVED)
	var wire := parsed as Dictionary
	if not wire.has("schema_version") or not _is_wire_integer(wire["schema_version"]):
		return _load_corrupt(source_bytes, INVALID_FIELD_TYPE)
	var schema_version := int(wire["schema_version"])
	if schema_version > SettingsSnapshot.new().schema_version:
		_commit_in_memory(SettingsSnapshot.new(), true)
		_future_bytes = source_bytes.duplicate()
		_future_digest = _sha256(source_bytes)
		return _success(_committed, UNSUPPORTED_FUTURE_VERSION)
	if schema_version != 1:
		return _load_corrupt(source_bytes, INVALID_FIELD_TYPE)

	var decoded := _decode_schema_one(wire)
	if not bool(decoded.get("ok", false)):
		return _load_corrupt(
			source_bytes,
			StringName(decoded.get("code", CORRUPT_ARCHIVED))
		)
	_commit_in_memory(decoded.get("snapshot") as SettingsSnapshot, true)
	_clear_future_lock()
	return _success(_committed)


static func locale_for_os(os_locale: String) -> StringName:
	var normalized := os_locale.strip_edges().replace("-", "_").to_lower()
	if normalized == "zh_tw" or normalized.begins_with("zh_hant"):
		return &"zh_TW"
	return &"en"


func _first_launch_snapshot() -> SettingsSnapshot:
	var snapshot := SettingsSnapshot.new()
	var os_locale := (
		String(_os_locale_provider.call())
		if _os_locale_provider.is_valid()
		else OS.get_locale()
	)
	snapshot.locale = locale_for_os(os_locale)
	return snapshot


func current_snapshot() -> SettingsSnapshot:
	return _committed.deep_clone()


func save(candidate: SettingsSnapshot) -> SettingsRepositoryResult:
	if not _future_digest.is_empty():
		return _failure(FUTURE_VERSION_PRESERVED)
	if candidate == null:
		return _failure(INVALID_FIELD_TYPE)
	var clone := candidate.deep_clone()
	var validation_code := _validate_snapshot(clone)
	if not validation_code.is_empty():
		return _failure(validation_code)
	return _atomic_save(clone)


func reset_incompatible_settings(expected_digest: String) -> SettingsRepositoryResult:
	var digest := expected_digest
	if _future_digest.is_empty() or digest != _future_digest:
		return _failure(EXPECTED_DIGEST_MISMATCH)
	var fresh_result: SettingsStorageResult = _storage.read_bytes(MAIN_PATH)
	if (
		not _storage_ok(fresh_result)
		or not fresh_result.exists
	):
		return _failure(STORAGE_FAULT)
	var fresh_bytes: PackedByteArray = fresh_result.bytes_value()
	if _sha256(fresh_bytes) != digest:
		return _failure(EXPECTED_DIGEST_MISMATCH)
	if not _archive_future_bytes(fresh_bytes, digest):
		return _failure(STORAGE_FAULT)

	_clear_future_lock()
	var reset_result := _atomic_save(SettingsSnapshot.new())
	if not reset_result.ok:
		_future_bytes = fresh_bytes.duplicate()
		_future_digest = digest
	return reset_result


# Legacy foundation compatibility. New presentation code must use typed snapshots.
func master_volume_db() -> float:
	return _master_volume_db


func set_master_volume_db(value: float) -> bool:
	if is_nan(value) or is_inf(value):
		return false
	_master_volume_db = clampf(value, MIN_VOLUME_DB, MAX_VOLUME_DB)
	settings_changed.emit()
	return true


func pixel_scale() -> int:
	return _pixel_scale


func set_pixel_scale(value: int) -> bool:
	if value < 1 or value > 4:
		return false
	_pixel_scale = value
	settings_changed.emit()
	return true


func _atomic_save(candidate: SettingsSnapshot) -> SettingsRepositoryResult:
	var bytes := JSON.stringify(_encode_schema_one(candidate)).to_utf8_buffer()
	var write_result: SettingsStorageResult = _storage.write_bytes(TMP_PATH, bytes)
	if not _storage_ok(write_result):
		return _failure(STORAGE_FAULT)
	var tmp_read: SettingsStorageResult = _storage.read_bytes(TMP_PATH)
	if not _read_matches(tmp_read, bytes):
		_storage.remove_bytes(TMP_PATH)
		return _failure(STORAGE_FAULT)
	var promote_result: SettingsStorageResult = _storage.promote_bytes(TMP_PATH, MAIN_PATH)
	if not _storage_ok(promote_result):
		_storage.remove_bytes(TMP_PATH)
		return _failure(STORAGE_FAULT)
	var final_read: SettingsStorageResult = _storage.read_bytes(MAIN_PATH)
	if not _read_matches(final_read, bytes):
		if _main_exists:
			_storage.restore_bytes(BACKUP_PATH, MAIN_PATH)
		else:
			_storage.remove_bytes(MAIN_PATH)
		return _failure(STORAGE_FAULT)

	_commit_in_memory(candidate, true)
	var result := _success(_committed)
	settings_committed.emit(_committed.deep_clone())
	settings_changed.emit()
	return result


func _load_corrupt(
	source_bytes: PackedByteArray,
	warning_code: StringName
) -> SettingsRepositoryResult:
	var archive_path := StringName(
		"settings-archive/corrupt-%s.json" % _sha256(source_bytes)
	)
	var copy_result: SettingsStorageResult = _storage.copy_bytes(MAIN_PATH, archive_path)
	if not _storage_ok(copy_result):
		return _failure(STORAGE_FAULT)
	var archive_read: SettingsStorageResult = _storage.read_bytes(archive_path)
	if not _read_matches(archive_read, source_bytes):
		return _failure(STORAGE_FAULT)
	_commit_in_memory(SettingsSnapshot.new(), true)
	_clear_future_lock()
	return _success(_committed, warning_code)


func _archive_future_bytes(bytes: PackedByteArray, digest: String) -> bool:
	var temporary_path := StringName("settings-archive/.future-%s.tmp" % digest)
	var archive_path := StringName("settings-archive/future-%s.json" % digest)
	var copy_result: SettingsStorageResult = _storage.copy_bytes(MAIN_PATH, temporary_path)
	if not _storage_ok(copy_result):
		return false
	var temporary_read: SettingsStorageResult = _storage.read_bytes(temporary_path)
	if not _read_matches(temporary_read, bytes):
		return false
	var promote_result: SettingsStorageResult = _storage.promote_bytes(temporary_path, archive_path)
	if not _storage_ok(promote_result):
		return false
	var archive_read: SettingsStorageResult = _storage.read_bytes(archive_path)
	return _read_matches(archive_read, bytes)


func _decode_schema_one(wire: Dictionary) -> Dictionary:
	var required_string_fields := PackedStringArray([
		"locale",
		"color_vision_mode",
		"damage_number_density",
	])
	var required_integer_fields := PackedStringArray([
		"schema_version",
		"ui_scale_percent",
		"master_volume_bps",
		"music_volume_bps",
		"sfx_volume_bps",
		"ui_volume_bps",
	])
	var required_boolean_fields := PackedStringArray([
		"reduced_motion",
		"reduced_flash",
		"reduced_particles",
		"master_muted",
		"music_muted",
		"sfx_muted",
		"ui_muted",
	])
	for field: String in required_string_fields:
		if not wire.has(field) or typeof(wire[field]) != TYPE_STRING:
			return {"ok": false, "code": INVALID_FIELD_TYPE}
	for field: String in required_integer_fields:
		if not wire.has(field) or not _is_wire_integer(wire[field]):
			return {"ok": false, "code": INVALID_FIELD_TYPE}
	for field: String in required_boolean_fields:
		if not wire.has(field) or typeof(wire[field]) != TYPE_BOOL:
			return {"ok": false, "code": INVALID_FIELD_TYPE}

	var snapshot := SettingsSnapshot.new()
	snapshot.schema_version = int(wire["schema_version"])
	snapshot.locale = StringName(wire["locale"])
	snapshot.ui_scale_percent = int(wire["ui_scale_percent"])
	snapshot.color_vision_mode = StringName(wire["color_vision_mode"])
	snapshot.reduced_motion = bool(wire["reduced_motion"])
	snapshot.reduced_flash = bool(wire["reduced_flash"])
	snapshot.reduced_particles = bool(wire["reduced_particles"])
	snapshot.damage_number_density = StringName(wire["damage_number_density"])
	snapshot.master_volume_bps = int(wire["master_volume_bps"])
	snapshot.master_muted = bool(wire["master_muted"])
	snapshot.music_volume_bps = int(wire["music_volume_bps"])
	snapshot.music_muted = bool(wire["music_muted"])
	snapshot.sfx_volume_bps = int(wire["sfx_volume_bps"])
	snapshot.sfx_muted = bool(wire["sfx_muted"])
	snapshot.ui_volume_bps = int(wire["ui_volume_bps"])
	snapshot.ui_muted = bool(wire["ui_muted"])
	var validation_code := _validate_snapshot(snapshot)
	if not validation_code.is_empty():
		return {"ok": false, "code": validation_code}
	return {"ok": true, "snapshot": snapshot}


func _encode_schema_one(snapshot: SettingsSnapshot) -> Dictionary:
	return {
		"schema_version": snapshot.schema_version,
		"locale": String(snapshot.locale),
		"ui_scale_percent": snapshot.ui_scale_percent,
		"color_vision_mode": String(snapshot.color_vision_mode),
		"reduced_motion": snapshot.reduced_motion,
		"reduced_flash": snapshot.reduced_flash,
		"reduced_particles": snapshot.reduced_particles,
		"damage_number_density": String(snapshot.damage_number_density),
		"master_volume_bps": snapshot.master_volume_bps,
		"master_muted": snapshot.master_muted,
		"music_volume_bps": snapshot.music_volume_bps,
		"music_muted": snapshot.music_muted,
		"sfx_volume_bps": snapshot.sfx_volume_bps,
		"sfx_muted": snapshot.sfx_muted,
		"ui_volume_bps": snapshot.ui_volume_bps,
		"ui_muted": snapshot.ui_muted,
	}


func _validate_snapshot(snapshot: SettingsSnapshot) -> StringName:
	if snapshot.schema_version != 1:
		return INVALID_FIELD_TYPE
	if snapshot.locale not in _VALID_LOCALES:
		return INVALID_ENUM
	if snapshot.ui_scale_percent not in _VALID_UI_SCALES:
		return FIELD_OUT_OF_RANGE
	if snapshot.color_vision_mode not in _VALID_COLOR_VISION_MODES:
		return INVALID_ENUM
	if snapshot.damage_number_density not in _VALID_DAMAGE_DENSITIES:
		return INVALID_ENUM
	var volumes: Array[int] = [
		snapshot.master_volume_bps,
		snapshot.music_volume_bps,
		snapshot.sfx_volume_bps,
		snapshot.ui_volume_bps,
	]
	for volume: int in volumes:
		if volume < 0 or volume > 10000:
			return FIELD_OUT_OF_RANGE
	return &""


func _commit_in_memory(snapshot: SettingsSnapshot, main_exists: bool) -> void:
	_committed = snapshot.deep_clone()
	_main_exists = main_exists


func _clear_future_lock() -> void:
	_future_bytes = PackedByteArray()
	_future_digest = ""


func _success(
	snapshot: SettingsSnapshot,
	warning_code: StringName = &""
) -> SettingsRepositoryResult:
	return SettingsRepositoryResult.new(true, snapshot, &"", warning_code)


func _failure(error_code: StringName) -> SettingsRepositoryResult:
	return SettingsRepositoryResult.new(false, null, error_code)


func _storage_ok(result: SettingsStorageResult) -> bool:
	return result != null and result.ok


func _read_matches(result: SettingsStorageResult, expected: PackedByteArray) -> bool:
	return (
		_storage_ok(result)
		and result.exists
		and result.bytes_value() == expected
	)


func _is_wire_integer(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return true
	if typeof(value) != TYPE_FLOAT:
		return false
	var number := value as float
	return is_finite(number) and number == floorf(number)


func _sha256(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	if context.update(bytes) != OK:
		return ""
	return context.finish().hex_encode()
