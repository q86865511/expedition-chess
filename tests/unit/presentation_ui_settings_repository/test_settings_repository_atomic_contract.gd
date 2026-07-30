extends GutTest

## G2 presentation-ui T02 behavioral red.
##
## The legacy SettingsRepository is intentionally guarded by source/API
## assertions before construction. Missing production support therefore fails
## as a GUT assertion instead of a parser/import/runtime-engine error.

const REPOSITORY_PATH := "res://services/settings/settings_repository.gd"
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

var _signal_payloads: Array[SettingsSnapshot] = []


class FakeSettingsStorage:
	extends SettingsStoragePort

	var files: Dictionary = {}
	var journal: Array[Dictionary] = []
	var _faults: Dictionary = {}
	var _occurrences: Dictionary = {}

	func seed_file(path: StringName, bytes: PackedByteArray) -> void:
		files[path] = bytes.duplicate()

	func file_bytes(path: StringName) -> PackedByteArray:
		if not files.has(path):
			return PackedByteArray()
		return (files[path] as PackedByteArray).duplicate()

	func has_file(path: StringName) -> bool:
		return files.has(path)

	func archive_paths() -> Array[StringName]:
		var paths: Array[StringName] = []
		for raw_path: Variant in files.keys():
			var path := StringName(raw_path)
			if String(path).begins_with("settings-archive/"):
				paths.append(path)
		return paths

	func reset_journal() -> void:
		journal.clear()
		_occurrences.clear()

	func inject_fault(operation: StringName, path: StringName, occurrence: int = 1) -> void:
		_faults[_fault_key(operation, path, occurrence)] = true

	func read_bytes(path: StringName) -> SettingsStorageResult:
		var occurrence := _record(&"read", path)
		if _should_fail(&"read", path, occurrence):
			return _failure()
		if not files.has(path):
			return SettingsStorageResult.success(false)
		return SettingsStorageResult.success(
			true, (files[path] as PackedByteArray).duplicate()
		)

	func write_bytes(path: StringName, bytes: PackedByteArray) -> SettingsStorageResult:
		var occurrence := _record(&"write", path)
		if _should_fail(&"write", path, occurrence):
			return _failure()
		files[path] = bytes.duplicate()
		return SettingsStorageResult.success()

	func promote_bytes(source: StringName, destination: StringName) -> SettingsStorageResult:
		var occurrence := _record(&"promote", destination)
		if _should_fail(&"promote", destination, occurrence):
			return _failure()
		if not files.has(source):
			return _failure()
		if files.has(destination):
			files[BACKUP_PATH] = (files[destination] as PackedByteArray).duplicate()
		files[destination] = (files[source] as PackedByteArray).duplicate()
		files.erase(source)
		return SettingsStorageResult.success()

	func copy_bytes(source: StringName, destination: StringName) -> SettingsStorageResult:
		var occurrence := _record(&"copy", destination)
		if _should_fail(&"copy", destination, occurrence):
			return _failure()
		if not files.has(source):
			return _failure()
		files[destination] = (files[source] as PackedByteArray).duplicate()
		return SettingsStorageResult.success()

	func restore_bytes(source: StringName, destination: StringName) -> SettingsStorageResult:
		var occurrence := _record(&"restore", destination)
		if _should_fail(&"restore", destination, occurrence):
			return _failure()
		if not files.has(source):
			return _failure()
		files[destination] = (files[source] as PackedByteArray).duplicate()
		return SettingsStorageResult.success()

	func remove_bytes(path: StringName) -> SettingsStorageResult:
		var occurrence := _record(&"remove", path)
		if _should_fail(&"remove", path, occurrence):
			return _failure()
		files.erase(path)
		return SettingsStorageResult.success()

	func duplicate_storage() -> FakeSettingsStorage:
		var clone := FakeSettingsStorage.new()
		for raw_path: Variant in files.keys():
			var path := StringName(raw_path)
			clone.seed_file(path, files[path])
		return clone

	func _record(operation: StringName, path: StringName) -> int:
		var counter_key := "%s|%s" % [operation, path]
		var occurrence: int = int(_occurrences.get(counter_key, 0)) + 1
		_occurrences[counter_key] = occurrence
		journal.append({
			"operation": operation,
			"path": path,
			"occurrence": occurrence,
		})
		return occurrence

	func _should_fail(operation: StringName, path: StringName, occurrence: int) -> bool:
		return _faults.has(_fault_key(operation, path, occurrence))

	func _fault_key(operation: StringName, path: StringName, occurrence: int) -> String:
		return "%s|%s|%d" % [operation, path, occurrence]

	func _failure() -> SettingsStorageResult:
		return SettingsStorageResult.failure(STORAGE_FAULT)


func before_each() -> void:
	_signal_payloads.clear()


func test_settings_repository_atomic_round_trip_and_faults() -> void:
	var storage := FakeSettingsStorage.new()
	var repository: Variant = _new_repository(storage)
	if repository == null:
		return
	var candidate := _non_default_snapshot()
	var saved: Variant = repository.call("save", candidate)
	assert_true(_ok(saved), "complete schema-1 snapshot must save")
	assert_eq(_code(saved), &"")
	_assert_snapshot_equal(_snapshot(saved), candidate)
	_assert_snapshot_equal(repository.call("current_snapshot"), candidate)

	var restarted: Variant = _new_repository(storage)
	if restarted == null:
		return
	var loaded: Variant = restarted.call("load")
	assert_true(_ok(loaded), "restart must load the last committed settings")
	_assert_snapshot_equal(_snapshot(loaded), candidate)

	var newer := candidate.deep_clone()
	newer.locale = &"zh_TW"
	newer.master_volume_bps = 4321
	var successful_probe := storage.duplicate_storage()
	var probe_repository: Variant = _new_repository(successful_probe)
	if probe_repository == null:
		return
	assert_true(_ok(probe_repository.call("load")))
	successful_probe.reset_journal()
	assert_true(_ok(probe_repository.call("save", newer)))
	var required_stages: Array[Dictionary] = [
		{"operation": &"write", "path": TMP_PATH},
		{"operation": &"read", "path": TMP_PATH},
		{"operation": &"promote", "path": MAIN_PATH},
		{"operation": &"read", "path": MAIN_PATH},
	]
	for stage: Dictionary in required_stages:
		assert_true(
			_journal_contains(successful_probe.journal, stage.operation, stage.path),
			"atomic protocol must execute %s/%s" % [stage.operation, stage.path]
		)
		var fault_storage := storage.duplicate_storage()
		var fault_repository: Variant = _new_repository(fault_storage)
		if fault_repository == null:
			return
		assert_true(_ok(fault_repository.call("load")))
		fault_storage.reset_journal()
		fault_storage.inject_fault(stage.operation, stage.path)
		var failed: Variant = fault_repository.call("save", newer)
		assert_false(_ok(failed), "%s/%s fault must reject save" % [stage.operation, stage.path])
		assert_eq(_code(failed), STORAGE_FAULT)
		_assert_snapshot_equal(fault_repository.call("current_snapshot"), candidate)
		var after_restart: Variant = _new_repository(fault_storage)
		if after_restart == null:
			return
		var recovered: Variant = after_restart.call("load")
		assert_true(_ok(recovered), "restart must recover old committed settings after fault")
		_assert_snapshot_equal(_snapshot(recovered), candidate)


func test_schema_one_defaults_wire_values_and_exact_validation_rejections() -> void:
	var defaults := SettingsSnapshot.new()
	assert_eq(defaults.schema_version, 1)
	assert_eq(defaults.locale, &"zh_TW")
	assert_eq(defaults.ui_scale_percent, 100)
	assert_eq(defaults.color_vision_mode, &"default")
	assert_false(defaults.reduced_motion)
	assert_false(defaults.reduced_flash)
	assert_false(defaults.reduced_particles)
	assert_eq(defaults.damage_number_density, &"full")
	for pair: Array in _bus_pairs(defaults):
		assert_eq(pair[0], 10000)
		assert_false(pair[1])
	assert_eq(SaveSchemaContract.CURRENT, 3, "T02 must not change gameplay save schema")

	var repository: Variant = _new_repository(FakeSettingsStorage.new())
	if repository == null:
		return
	var invalid_enum := defaults.deep_clone()
	invalid_enum.locale = &"fr"
	var rejected_enum: Variant = repository.call("save", invalid_enum)
	assert_false(_ok(rejected_enum))
	assert_eq(_code(rejected_enum), INVALID_ENUM)
	var invalid_range := defaults.deep_clone()
	invalid_range.ui_scale_percent = 124
	var rejected_scale: Variant = repository.call("save", invalid_range)
	assert_false(_ok(rejected_scale))
	assert_eq(_code(rejected_scale), FIELD_OUT_OF_RANGE)
	invalid_range = defaults.deep_clone()
	invalid_range.sfx_volume_bps = 10001
	var rejected_volume: Variant = repository.call("save", invalid_range)
	assert_false(_ok(rejected_volume))
	assert_eq(_code(rejected_volume), FIELD_OUT_OF_RANGE)
	_assert_snapshot_equal(repository.call("current_snapshot"), defaults)

	var wrong_type_storage := FakeSettingsStorage.new()
	var wrong_type_wire := _valid_wire(defaults)
	wrong_type_wire["locale"] = 17
	wrong_type_storage.seed_file(MAIN_PATH, JSON.stringify(wrong_type_wire).to_utf8_buffer())
	var wrong_type_repository: Variant = _new_repository(wrong_type_storage)
	if wrong_type_repository == null:
		return
	var wrong_type_load: Variant = wrong_type_repository.call("load")
	assert_true(_ok(wrong_type_load), "corrupt v1 must fall back to defaults")
	assert_eq(_code(wrong_type_load), INVALID_FIELD_TYPE)
	_assert_snapshot_equal(_snapshot(wrong_type_load), defaults)


func test_corrupt_v1_is_archived_and_future_schema_is_preserved_until_digest_reset() -> void:
	var corrupt_bytes := "{\"schema_version\":1,\"locale\":".to_utf8_buffer()
	var corrupt_storage := FakeSettingsStorage.new()
	corrupt_storage.seed_file(MAIN_PATH, corrupt_bytes)
	var corrupt_repository: Variant = _new_repository(corrupt_storage)
	if corrupt_repository == null:
		return
	var corrupt_load: Variant = corrupt_repository.call("load")
	assert_true(_ok(corrupt_load))
	assert_eq(_code(corrupt_load), CORRUPT_ARCHIVED)
	_assert_snapshot_equal(_snapshot(corrupt_load), SettingsSnapshot.new())
	assert_eq(corrupt_storage.file_bytes(MAIN_PATH), corrupt_bytes)
	assert_true(_archive_contains(corrupt_storage, corrupt_bytes))

	var future_wire := _valid_wire(_non_default_snapshot())
	future_wire["schema_version"] = 2
	future_wire["future_only"] = {"opaque": [1, 2, 3]}
	var future_bytes := JSON.stringify(future_wire).to_utf8_buffer()
	var future_storage := FakeSettingsStorage.new()
	future_storage.seed_file(MAIN_PATH, future_bytes)
	var future_repository: Variant = _new_repository(future_storage)
	if future_repository == null:
		return
	var future_load: Variant = future_repository.call("load")
	assert_true(_ok(future_load))
	assert_eq(_code(future_load), UNSUPPORTED_FUTURE_VERSION)
	_assert_snapshot_equal(_snapshot(future_load), SettingsSnapshot.new())
	assert_eq(future_storage.file_bytes(MAIN_PATH), future_bytes)
	assert_eq(future_storage.archive_paths().size(), 0)
	var blocked_save: Variant = future_repository.call("save", _non_default_snapshot())
	assert_false(_ok(blocked_save))
	assert_eq(_code(blocked_save), FUTURE_VERSION_PRESERVED)
	assert_eq(future_storage.file_bytes(MAIN_PATH), future_bytes)
	var wrong_reset: Variant = future_repository.call(
		"reset_incompatible_settings",
		"0".repeat(64)
	)
	assert_false(_ok(wrong_reset))
	assert_eq(_code(wrong_reset), EXPECTED_DIGEST_MISMATCH)
	assert_eq(future_storage.file_bytes(MAIN_PATH), future_bytes)
	var reset: Variant = future_repository.call(
		"reset_incompatible_settings",
		_sha256(future_bytes)
	)
	assert_true(_ok(reset))
	_assert_snapshot_equal(_snapshot(reset), SettingsSnapshot.new())
	assert_true(_archive_contains(future_storage, future_bytes))
	assert_ne(future_storage.file_bytes(MAIN_PATH), future_bytes)
	var reset_restart: Variant = _new_repository(future_storage)
	if reset_restart == null:
		return
	var reset_loaded: Variant = reset_restart.call("load")
	assert_true(_ok(reset_loaded))
	_assert_snapshot_equal(_snapshot(reset_loaded), SettingsSnapshot.new())


func test_public_snapshot_results_signals_and_consumers_never_alias_repository_state() -> void:
	var repository: Variant = _new_repository(FakeSettingsStorage.new())
	if repository == null:
		return
	assert_true(repository.has_signal("settings_committed"))
	repository.connect("settings_committed", Callable(self, "_capture_signal"))
	var caller := _non_default_snapshot()
	var saved: Variant = repository.call("save", caller)
	assert_true(_ok(saved))
	assert_eq(_signal_payloads.size(), 1)
	caller.locale = &"zh_TW"
	caller.master_volume_bps = 1
	var result_snapshot := _snapshot(saved)
	result_snapshot.music_volume_bps = 2
	_signal_payloads[0].sfx_volume_bps = 3
	var consumer_a: SettingsSnapshot = repository.call("current_snapshot")
	var consumer_b: SettingsSnapshot = repository.call("current_snapshot")
	assert_ne(consumer_a, consumer_b)
	assert_eq(consumer_a.locale, &"en")
	assert_eq(consumer_a.master_volume_bps, 8765)
	assert_eq(consumer_a.music_volume_bps, 7654)
	assert_eq(consumer_a.sfx_volume_bps, 6543)
	consumer_a.ui_volume_bps = 4
	assert_eq(consumer_b.ui_volume_bps, 5432)
	assert_eq((repository.call("current_snapshot") as SettingsSnapshot).ui_volume_bps, 5432)


func _new_repository(storage: FakeSettingsStorage) -> Variant:
	var source := FileAccess.get_file_as_string(REPOSITORY_PATH)
	var required_tokens := PackedStringArray([
		"signal settings_committed",
		"func _init(",
		"func load(",
		"func current_snapshot(",
		"func save(",
		"func reset_incompatible_settings(",
		"read_bytes(",
		"write_bytes(",
		"promote_bytes(",
		"copy_bytes(",
		"restore_bytes(",
	])
	for token: String in required_tokens:
		if not source.contains(token):
			assert_true(
				false,
				"T02 SettingsRepository production contract missing `%s`" % token
			)
			return null
	var script_resource := load(REPOSITORY_PATH)
	assert_not_null(script_resource)
	if script_resource == null:
		return null
	var repository: Variant = script_resource.new(storage)
	assert_not_null(repository)
	if repository is Node:
		add_child_autofree(repository as Node)
	return repository


func _capture_signal(snapshot: SettingsSnapshot) -> void:
	_signal_payloads.append(snapshot)


func _non_default_snapshot() -> SettingsSnapshot:
	var snapshot := SettingsSnapshot.new()
	snapshot.locale = &"en"
	snapshot.ui_scale_percent = 150
	snapshot.color_vision_mode = &"tritanopia"
	snapshot.reduced_motion = true
	snapshot.reduced_flash = true
	snapshot.reduced_particles = true
	snapshot.damage_number_density = &"reduced"
	snapshot.master_volume_bps = 8765
	snapshot.master_muted = true
	snapshot.music_volume_bps = 7654
	snapshot.music_muted = false
	snapshot.sfx_volume_bps = 6543
	snapshot.sfx_muted = true
	snapshot.ui_volume_bps = 5432
	snapshot.ui_muted = false
	return snapshot


func _valid_wire(snapshot: SettingsSnapshot) -> Dictionary:
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


func _assert_snapshot_equal(actual: SettingsSnapshot, expected: SettingsSnapshot) -> void:
	assert_not_null(actual)
	if actual == null:
		return
	assert_eq(actual.schema_version, expected.schema_version)
	assert_eq(actual.locale, expected.locale)
	assert_eq(actual.ui_scale_percent, expected.ui_scale_percent)
	assert_eq(actual.color_vision_mode, expected.color_vision_mode)
	assert_eq(actual.reduced_motion, expected.reduced_motion)
	assert_eq(actual.reduced_flash, expected.reduced_flash)
	assert_eq(actual.reduced_particles, expected.reduced_particles)
	assert_eq(actual.damage_number_density, expected.damage_number_density)
	assert_eq(actual.master_volume_bps, expected.master_volume_bps)
	assert_eq(actual.master_muted, expected.master_muted)
	assert_eq(actual.music_volume_bps, expected.music_volume_bps)
	assert_eq(actual.music_muted, expected.music_muted)
	assert_eq(actual.sfx_volume_bps, expected.sfx_volume_bps)
	assert_eq(actual.sfx_muted, expected.sfx_muted)
	assert_eq(actual.ui_volume_bps, expected.ui_volume_bps)
	assert_eq(actual.ui_muted, expected.ui_muted)


func _bus_pairs(snapshot: SettingsSnapshot) -> Array[Array]:
	return [
		[snapshot.master_volume_bps, snapshot.master_muted],
		[snapshot.music_volume_bps, snapshot.music_muted],
		[snapshot.sfx_volume_bps, snapshot.sfx_muted],
		[snapshot.ui_volume_bps, snapshot.ui_muted],
	]


func _ok(result: Variant) -> bool:
	return result != null and bool(result.get("ok"))


func _snapshot(result: Variant) -> SettingsSnapshot:
	if result is SettingsSnapshot:
		return result
	return result.get("snapshot") as SettingsSnapshot


func _code(result: Variant) -> StringName:
	if result == null:
		return &""
	var error: Variant = result.get("error")
	if error != null:
		return StringName(error.get("code"))
	var warning: Variant = result.get("warning")
	if warning != null:
		return StringName(warning.get("code"))
	var warnings: Variant = result.get("warnings")
	if warnings is Array and not warnings.is_empty():
		return StringName(warnings[0].get("code"))
	return &""


func _journal_contains(
	journal: Array[Dictionary],
	operation: StringName,
	path: StringName
) -> bool:
	for entry: Dictionary in journal:
		if entry.operation == operation and entry.path == path:
			return true
	return false


func _archive_contains(storage: FakeSettingsStorage, expected: PackedByteArray) -> bool:
	for path: StringName in storage.archive_paths():
		if storage.file_bytes(path) == expected:
			return true
	return false


func _sha256(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	assert_eq(context.start(HashingContext.HASH_SHA256), OK)
	assert_eq(context.update(bytes), OK)
	return context.finish().hex_encode()
