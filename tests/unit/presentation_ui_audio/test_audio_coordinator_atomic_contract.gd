extends GutTest

## G2 presentation-ui T03 behavioral red.
##
## T00 did not declare AudioBusPort/AudioApplicationResult, so the production
## contracts are loaded dynamically. Missing T03 contracts therefore become
## ordinary GUT assertion failures instead of parser/import aborts.
##
## Test-author API decision:
## - AudioCoordinator.new(AudioBusPort)
## - apply_committed(SettingsSnapshot) -> typed AudioApplicationResult
## - current_snapshot() -> clone-only SettingsSnapshot
## - AudioBusPort.apply_batch(AudioBusBatch) -> AudioBusBatchResult receives
##   exactly one typed batch. Every AudioBusAssignment contains bus,
##   volume_bps, volume_db, and muted.
## - Adapter failures expose DiagnosticError.source_code.

const COORDINATOR_PATH := "res://services/audio/audio_coordinator.gd"
const PORT_PATH := "res://services/audio/audio_bus_port.gd"
const RESULT_PATH := "res://services/audio/audio_application_result.gd"

const MASTER: StringName = &"Master"
const MUSIC: StringName = &"Music"
const SFX: StringName = &"SFX"
const UI: StringName = &"UI"
const BUS_ORDER: Array[StringName] = [MASTER, MUSIC, SFX, UI]

const AUDIO_BUS_MISSING: StringName = &"AUDIO_BUS_MISSING"
const AUDIO_BUS_APPLY_PRECOMMIT_FAULT: StringName = \
	&"AUDIO_BUS_APPLY_PRECOMMIT_FAULT"

const FAKE_AUDIO_BUS_PORT_SOURCE := """
extends "res://services/audio/audio_bus_port.gd"

const BUS_ORDER: Array[StringName] = [&"Master", &"Music", &"SFX", &"UI"]

var state: Dictionary = {}
var available_buses: Dictionary = {}
var batches: Array = []
var journal: Array[StringName] = []
var commit_count: int = 0
var before_commit_fault: bool = false


func _init() -> void:
	for bus: StringName in BUS_ORDER:
		available_buses[bus] = true
		state[bus] = {
			"volume_bps": 7777,
			"volume_db": linear_to_db(0.7777),
			"muted": false,
		}


func remove_bus(bus: StringName) -> void:
	available_buses.erase(bus)


func inject_before_commit_fault() -> void:
	before_commit_fault = true


func reset_journal() -> void:
	journal.clear()


func state_copy() -> Dictionary:
	return state.duplicate(true)


func state_for(bus: StringName) -> Dictionary:
	return (state.get(bus, {}) as Dictionary).duplicate(true)


func apply_batch(batch: AudioBusBatch) -> AudioBusBatchResult:
	var assignments: Array[Dictionary] = []
	for typed_assignment: AudioBusAssignment in batch.assignments:
		assignments.append({
			"bus": typed_assignment.bus,
			"volume_bps": typed_assignment.volume_bps,
			"volume_db": typed_assignment.volume_db,
			"muted": typed_assignment.muted,
		})
	batches.append(assignments.duplicate(true))
	var seen: Dictionary = {}
	if assignments.size() != BUS_ORDER.size():
		return AudioBusBatchResult.failure(&"AUDIO_BUS_BATCH_INVALID")
	for assignment: Dictionary in assignments:
		var bus := StringName(assignment.get("bus", &""))
		journal.append(StringName("preflight:%s" % bus))
		if not BUS_ORDER.has(bus) or seen.has(bus):
			return AudioBusBatchResult.failure(&"AUDIO_BUS_BATCH_INVALID")
		seen[bus] = true
		if not available_buses.has(bus):
			return AudioBusBatchResult.failure(&"AUDIO_BUS_MISSING")
		var volume: Variant = assignment.get("volume_bps")
		var volume_db: Variant = assignment.get("volume_db")
		var muted: Variant = assignment.get("muted")
		if typeof(volume) != TYPE_INT or volume < 0 or volume > 10000:
			return AudioBusBatchResult.failure(&"AUDIO_BUS_VALUE_INVALID")
		if typeof(volume_db) != TYPE_FLOAT:
			return AudioBusBatchResult.failure(&"AUDIO_BUS_VALUE_INVALID")
		if typeof(muted) != TYPE_BOOL:
			return AudioBusBatchResult.failure(&"AUDIO_BUS_VALUE_INVALID")
	journal.append(&"before_commit")
	if before_commit_fault:
		return AudioBusBatchResult.failure(
			&"AUDIO_BUS_APPLY_PRECOMMIT_FAULT"
		)
	for assignment: Dictionary in assignments:
		var bus := StringName(assignment.bus)
		state[bus] = assignment.duplicate(true)
		journal.append(StringName("commit:%s" % bus))
	commit_count += 1
	return AudioBusBatchResult.success()
"""


func test_audio_coordinator_applies_four_buses_atomically() -> void:
	var fixture := _new_fixture()
	if fixture.is_empty():
		return
	var coordinator: Object = fixture.coordinator
	var port: Object = fixture.port
	var committed := _committed_snapshot()

	var applied: Variant = coordinator.call("apply_committed", committed)

	assert_true(_ok(applied), _error_text(applied))
	assert_true(applied is Object, "public apply result must be typed, not Dictionary")
	assert_null(_field(applied, &"error"))
	assert_eq(port.get("batches").size(), 1, "all buses must use one atomic batch")
	assert_eq(port.get("commit_count"), 1)
	var batch: Array = port.get("batches")[0]
	assert_eq(batch.size(), 4)
	assert_eq(_batch_bus_order(batch), BUS_ORDER)
	_assert_bus(port, MASTER, 0, true)
	_assert_bus(port, MUSIC, 2500, false)
	_assert_bus(port, SFX, 5000, true)
	_assert_bus(port, UI, 10000, false)
	assert_almost_eq(
		float(port.call("state_for", MUSIC).volume_db),
		linear_to_db(0.25),
		0.0001
	)
	assert_almost_eq(float(port.call("state_for", UI).volume_db), 0.0, 0.0001)
	assert_eq(
		port.get("journal"),
		[
			&"preflight:Master",
			&"preflight:Music",
			&"preflight:SFX",
			&"preflight:UI",
			&"before_commit",
			&"commit:Master",
			&"commit:Music",
			&"commit:SFX",
			&"commit:UI",
		],
		"the no-fail commit segment must begin only after all four preflights"
	)

	var before: Dictionary = port.call("state_copy")
	var music_only_change := committed.deep_clone()
	music_only_change.music_volume_bps = 3333
	music_only_change.music_muted = true
	var reapplied: Variant = coordinator.call(
		"apply_committed", music_only_change
	)
	assert_true(_ok(reapplied), _error_text(reapplied))
	assert_eq(port.call("state_for", MASTER), before[MASTER])
	assert_eq(port.call("state_for", SFX), before[SFX])
	assert_eq(port.call("state_for", UI), before[UI])
	_assert_bus(port, MUSIC, 3333, true)


func test_missing_bus_preflight_is_named_and_leaves_all_four_buses_unchanged() -> void:
	var fixture := _new_fixture()
	if fixture.is_empty():
		return
	var coordinator: Object = fixture.coordinator
	var port: Object = fixture.port
	assert_true(_ok(coordinator.call("apply_committed", _committed_snapshot())))
	var before: Dictionary = port.call("state_copy")
	var commits_before: int = int(port.get("commit_count"))
	port.call("remove_bus", SFX)
	port.call("reset_journal")

	var candidate := _committed_snapshot()
	candidate.master_volume_bps = 1111
	candidate.music_volume_bps = 2222
	candidate.sfx_volume_bps = 3333
	candidate.ui_volume_bps = 4444
	var rejected: Variant = coordinator.call("apply_committed", candidate)

	assert_false(_ok(rejected))
	assert_true(rejected is Object, "failure must use the typed result")
	assert_eq(_error_code(rejected), AUDIO_BUS_MISSING)
	assert_false(_error_message_key(rejected).is_empty())
	assert_null(_field(rejected, &"snapshot"))
	assert_eq(port.call("state_copy"), before)
	assert_eq(port.get("commit_count"), commits_before)
	assert_false(
		_has_commit_after_last_before_commit(port.get("journal")),
		"missing bus must fail during preflight before any assignment"
	)
	_assert_snapshot_equal(
		coordinator.call("current_snapshot"),
		_committed_snapshot()
	)


func test_before_commit_adapter_fault_is_named_and_zero_mutation() -> void:
	var fixture := _new_fixture()
	if fixture.is_empty():
		return
	var coordinator: Object = fixture.coordinator
	var port: Object = fixture.port
	assert_true(_ok(coordinator.call("apply_committed", _committed_snapshot())))
	var before: Dictionary = port.call("state_copy")
	var commits_before: int = int(port.get("commit_count"))
	port.call("inject_before_commit_fault")
	port.call("reset_journal")

	var candidate := _committed_snapshot()
	candidate.master_muted = true
	candidate.music_muted = true
	candidate.sfx_muted = false
	candidate.ui_muted = true
	var rejected: Variant = coordinator.call("apply_committed", candidate)

	assert_false(_ok(rejected))
	assert_eq(_error_code(rejected), AUDIO_BUS_APPLY_PRECOMMIT_FAULT)
	assert_false(_error_message_key(rejected).is_empty())
	assert_eq(port.call("state_copy"), before)
	assert_eq(port.get("commit_count"), commits_before)
	_assert_snapshot_equal(
		coordinator.call("current_snapshot"),
		_committed_snapshot()
	)


func test_snapshot_result_and_consumer_boundaries_are_clone_only() -> void:
	var fixture := _new_fixture()
	if fixture.is_empty():
		return
	var coordinator: Object = fixture.coordinator
	var committed := _committed_snapshot()
	var applied: Variant = coordinator.call("apply_committed", committed)
	assert_true(_ok(applied), _error_text(applied))
	var result_snapshot := _field(applied, &"snapshot") as SettingsSnapshot
	assert_not_null(result_snapshot)
	if result_snapshot == null:
		return

	committed.music_volume_bps = 1
	committed.ui_muted = true
	result_snapshot.master_volume_bps = 2
	result_snapshot.sfx_muted = false
	var consumer_a := coordinator.call("current_snapshot") as SettingsSnapshot
	var consumer_b := coordinator.call("current_snapshot") as SettingsSnapshot

	assert_not_null(consumer_a)
	assert_not_null(consumer_b)
	assert_ne(consumer_a, consumer_b)
	_assert_snapshot_equal(consumer_a, _committed_snapshot())
	consumer_a.ui_volume_bps = 3
	assert_eq(consumer_b.ui_volume_bps, 10000)
	assert_eq(
		(coordinator.call("current_snapshot") as SettingsSnapshot).ui_volume_bps,
		10000
	)


func _new_fixture() -> Dictionary:
	var coordinator_script := _load_contracts()
	if coordinator_script == null:
		return {}
	var fake_script := GDScript.new()
	fake_script.source_code = FAKE_AUDIO_BUS_PORT_SOURCE
	var reload_error := fake_script.reload()
	assert_eq(
		reload_error,
		OK,
		"headless FakeAudioBusPort must compile without AudioServer/user://"
	)
	if reload_error != OK:
		return {}
	var port: Object = fake_script.new()
	var coordinator: Object = coordinator_script.new(port)
	assert_not_null(coordinator)
	if coordinator == null:
		return {}
	if coordinator is Node:
		add_child_autofree(coordinator as Node)
	return {"coordinator": coordinator, "port": port}


func _load_contracts() -> GDScript:
	var required := {
		PORT_PATH: PackedStringArray([
			"class_name AudioBusPort",
			"func apply_batch(",
		]),
		RESULT_PATH: PackedStringArray([
			"class_name AudioApplicationResult",
			"var ok",
			"var snapshot",
			"var error",
		]),
		COORDINATOR_PATH: PackedStringArray([
			"class_name AudioCoordinator",
			"func _init(",
			"func apply_committed(",
			"func current_snapshot(",
			"apply_batch(",
		]),
	}
	for raw_path: Variant in required:
		var path := String(raw_path)
		if not FileAccess.file_exists(path):
			assert_true(false, "T03 production contract missing: %s" % path)
			return null
		var source := FileAccess.get_file_as_string(path)
		for token: String in required[raw_path]:
			if not source.contains(token):
				assert_true(
					false,
					"T03 production contract %s missing `%s`" % [path, token]
				)
				return null
	var coordinator_source := FileAccess.get_file_as_string(COORDINATOR_PATH)
	assert_false(
		coordinator_source.contains("AudioServer"),
		"AudioCoordinator must use the injected AudioBusPort in headless tests"
	)
	assert_false(
		coordinator_source.contains("user://"),
		"T03 audio application must not touch persistent storage"
	)
	var coordinator_script := load(COORDINATOR_PATH) as GDScript
	assert_not_null(coordinator_script)
	return coordinator_script


func _committed_snapshot() -> SettingsSnapshot:
	var snapshot := SettingsSnapshot.new()
	snapshot.master_volume_bps = 0
	snapshot.master_muted = false
	snapshot.music_volume_bps = 2500
	snapshot.music_muted = false
	snapshot.sfx_volume_bps = 5000
	snapshot.sfx_muted = true
	snapshot.ui_volume_bps = 10000
	snapshot.ui_muted = false
	return snapshot


func _batch_bus_order(batch: Array) -> Array[StringName]:
	var order: Array[StringName] = []
	for assignment: Dictionary in batch:
		order.append(StringName(assignment.get("bus", &"")))
	return order


func _assert_bus(
	port: Object,
	bus: StringName,
	expected_bps: int,
	expected_muted: bool
) -> void:
	var actual: Dictionary = port.call("state_for", bus)
	assert_eq(actual.get("volume_bps"), expected_bps, String(bus))
	assert_eq(actual.get("muted"), expected_muted, String(bus))


func _has_commit_after_last_before_commit(journal: Array) -> bool:
	var last_before_commit := journal.rfind(&"before_commit")
	if last_before_commit < 0:
		return false
	for index: int in range(last_before_commit + 1, journal.size()):
		if String(journal[index]).begins_with("commit:"):
			return true
	return false


func _assert_snapshot_equal(
	actual: SettingsSnapshot,
	expected: SettingsSnapshot
) -> void:
	assert_not_null(actual)
	if actual == null:
		return
	assert_eq(actual.master_volume_bps, expected.master_volume_bps)
	assert_eq(actual.master_muted, expected.master_muted)
	assert_eq(actual.music_volume_bps, expected.music_volume_bps)
	assert_eq(actual.music_muted, expected.music_muted)
	assert_eq(actual.sfx_volume_bps, expected.sfx_volume_bps)
	assert_eq(actual.sfx_muted, expected.sfx_muted)
	assert_eq(actual.ui_volume_bps, expected.ui_volume_bps)
	assert_eq(actual.ui_muted, expected.ui_muted)


func _ok(result: Variant) -> bool:
	return bool(_field(result, &"ok"))


func _field(value: Variant, key: StringName) -> Variant:
	if typeof(value) == TYPE_DICTIONARY:
		return (value as Dictionary).get(key)
	if value is Object:
		return (value as Object).get(key)
	return null


func _error_code(result: Variant) -> StringName:
	var error: Variant = _field(result, &"error")
	var raw_code: Variant = _field(error, &"source_code")
	return &"" if raw_code == null else StringName(raw_code)


func _error_message_key(result: Variant) -> String:
	var error: Variant = _field(result, &"error")
	return String(_field(error, &"message_key"))


func _error_text(result: Variant) -> String:
	return String(_error_code(result))
