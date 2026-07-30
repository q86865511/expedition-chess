extends RefCounted

const COORDINATOR_PATH := "res://services/settings/settings_application_coordinator.gd"
const ADAPTER_PORT_PATH := "res://services/settings/settings_adapter_port.gd"
const ACTIVATION_TOKEN_PATH := "res://services/settings/settings_activation_token.gd"
const PREFLIGHT_RESULT_PATH := "res://services/settings/settings_adapter_preflight_result.gd"
const ADAPTER_ORDER: Array[StringName] = [
	&"theme",
	&"viewport",
	&"localization",
	&"audio",
]


class FakeError:
	extends RefCounted

	var code: StringName

	func _init(p_code: StringName) -> void:
		code = p_code


class FakeRepositoryResult:
	extends RefCounted

	var ok: bool
	var snapshot: SettingsSnapshot
	var error: FakeError

	func _init(
		p_ok: bool,
		p_snapshot: SettingsSnapshot,
		p_error_code: StringName = &""
	) -> void:
		ok = p_ok
		snapshot = p_snapshot.deep_clone() if p_snapshot != null else null
		error = FakeError.new(p_error_code) if not p_error_code.is_empty() else null


class FakeRepository:
	extends RefCounted

	var committed := SettingsSnapshot.new()
	var save_count: int = 0
	var current_read_count: int = 0
	var save_fault: bool = false
	var journal: Array[StringName]

	func _init(p_journal: Array[StringName]) -> void:
		journal = p_journal

	func save(candidate: SettingsSnapshot) -> FakeRepositoryResult:
		save_count += 1
		journal.append(&"repository:save")
		if save_fault:
			return FakeRepositoryResult.new(
				false,
				null,
				&"SETTINGS_STORAGE_FAULT"
			)
		committed = candidate.deep_clone()
		return FakeRepositoryResult.new(true, committed)

	func current_snapshot() -> SettingsSnapshot:
		current_read_count += 1
		journal.append(&"repository:fresh_read")
		return committed.deep_clone()


class FakeActivationToken:
	extends RefCounted

	var candidate_digest: String
	var adapter: Object
	var captured: SettingsSnapshot

	func _init(
		p_digest: String,
		p_adapter: Object,
		p_snapshot: SettingsSnapshot
	) -> void:
		candidate_digest = p_digest
		adapter = p_adapter
		captured = p_snapshot.deep_clone()

	func activate() -> StringName:
		adapter.journal.append(
			StringName("activate:%s" % String(adapter.adapter_id))
		)
		if adapter.activation_fault:
			return &"SETTINGS_ADAPTER_ACTIVATION_DIAGNOSTIC"
		adapter.runtime = captured.deep_clone()
		return &""


class FakeAdapter:
	extends RefCounted

	var adapter_id: StringName
	var journal: Array[StringName]
	var received_plans: Array[SettingsSnapshot] = []
	var runtime := SettingsSnapshot.new()
	var preflight_fault: bool = false
	var mutate_plan: bool = false
	var wrong_token_digest: bool = false
	var activation_fault: bool = false
	var coordinator: Object
	var reentrant_candidate: SettingsSnapshot
	var reentrant_result: Variant
	var safe_fallback_count: int = 0
	var rebuild_count: int = 0

	func _init(p_adapter_id: StringName, p_journal: Array[StringName]) -> void:
		adapter_id = p_adapter_id
		journal = p_journal

	func preflight(
		plan: SettingsSnapshot,
		candidate_digest: String
	) -> Dictionary:
		journal.append(StringName("preflight:%s" % String(adapter_id)))
		received_plans.append(plan)
		if coordinator != null and reentrant_candidate != null:
			reentrant_result = coordinator.call(
				"apply",
				reentrant_candidate.deep_clone()
			)
		if mutate_plan:
			plan.locale = &"mutated_by_adapter"
		if preflight_fault:
			return {
				"ok": false,
				"error_code": StringName(
					"SETTINGS_%s_PREFLIGHT_FAILED" % String(adapter_id).to_upper()
				),
			}
		var token_digest := (
			"wrong-digest" if wrong_token_digest else candidate_digest
		)
		return {
			"ok": true,
			"token": FakeActivationToken.new(token_digest, self, plan),
		}

	func activate_safe_fallback() -> void:
		safe_fallback_count += 1
		journal.append(StringName("fallback:%s" % String(adapter_id)))
		runtime = SettingsSnapshot.new()

	func rebuild_from_committed(snapshot: SettingsSnapshot) -> void:
		rebuild_count += 1
		journal.append(StringName("rebuild:%s" % String(adapter_id)))
		runtime = snapshot.deep_clone()


static func load_coordinator(test: Variant) -> GDScript:
	var required := {
		COORDINATOR_PATH: PackedStringArray([
			"class_name SettingsApplicationCoordinator",
			"extends SettingsApplicationPort",
			"func apply(",
			"func rebuild_from_repository(",
		]),
		ADAPTER_PORT_PATH: PackedStringArray([
			"class_name SettingsAdapterPort",
			"func preflight(",
			"func activate_safe_fallback(",
			"func rebuild_from_committed(",
		]),
		ACTIVATION_TOKEN_PATH: PackedStringArray([
			"class_name SettingsActivationToken",
			"candidate_digest",
			"func activate(",
		]),
		PREFLIGHT_RESULT_PATH: PackedStringArray([
			"class_name SettingsAdapterPreflightResult",
			"var ok",
			"var token",
			"var error",
		]),
	}
	for raw_path: Variant in required:
		var path := String(raw_path)
		if not FileAccess.file_exists(path):
			test.assert_true(false, "T12 production contract missing: %s" % path)
			return null
		var source := FileAccess.get_file_as_string(path)
		for token: String in required[raw_path]:
			if not source.contains(token):
				test.assert_true(
					false,
					"T12 production contract %s missing `%s`" % [path, token]
				)
				return null
	var coordinator_source := FileAccess.get_file_as_string(COORDINATOR_PATH)
	test.assert_false(
		coordinator_source.contains("await "),
		"settings apply/rebuild must remain process-local and synchronous"
	)
	var script := load(COORDINATOR_PATH) as GDScript
	test.assert_not_null(script)
	return script


static func fixture(test: Variant) -> Dictionary:
	var script := load_coordinator(test)
	if script == null:
		return {}
	var journal: Array[StringName] = []
	var repository := FakeRepository.new(journal)
	var adapters: Array[FakeAdapter] = []
	for adapter_id: StringName in ADAPTER_ORDER:
		adapters.append(FakeAdapter.new(adapter_id, journal))
	var coordinator: Object = script.new(
		repository,
		adapters[0],
		adapters[1],
		adapters[2],
		adapters[3]
	)
	test.assert_not_null(coordinator)
	if coordinator == null:
		return {}
	return {
		"coordinator": coordinator,
		"repository": repository,
		"adapters": adapters,
		"journal": journal,
	}


static func candidate(locale: StringName = &"en") -> SettingsSnapshot:
	var snapshot := SettingsSnapshot.new()
	snapshot.locale = locale
	snapshot.ui_scale_percent = 150
	snapshot.color_vision_mode = &"deuteranopia"
	snapshot.reduced_motion = true
	snapshot.reduced_flash = true
	snapshot.reduced_particles = true
	snapshot.damage_number_density = &"reduced"
	snapshot.master_volume_bps = 9100
	snapshot.master_muted = false
	snapshot.music_volume_bps = 7200
	snapshot.music_muted = true
	snapshot.sfx_volume_bps = 6300
	snapshot.sfx_muted = false
	snapshot.ui_volume_bps = 5400
	snapshot.ui_muted = true
	return snapshot


static func ok(result: Variant) -> bool:
	return bool(field(result, &"ok"))


static func field(value: Variant, key: StringName) -> Variant:
	if typeof(value) == TYPE_DICTIONARY:
		return (value as Dictionary).get(key)
	if value is Object:
		return (value as Object).get(key)
	return null


static func error_code(result: Variant) -> StringName:
	var error: Variant = field(result, &"error")
	if error == null:
		return &""
	var raw: Variant = field(error, &"source_code")
	if raw == null:
		raw = field(error, &"code")
	return &"" if raw == null else StringName(raw)


static func assert_runtime_equals(
	test: Variant,
	actual: SettingsSnapshot,
	expected: SettingsSnapshot
) -> void:
	test.assert_not_null(actual)
	if actual == null:
		return
	test.assert_eq(actual.locale, expected.locale)
	test.assert_eq(actual.ui_scale_percent, expected.ui_scale_percent)
	test.assert_eq(actual.color_vision_mode, expected.color_vision_mode)
	test.assert_eq(actual.reduced_motion, expected.reduced_motion)
	test.assert_eq(actual.reduced_flash, expected.reduced_flash)
	test.assert_eq(actual.reduced_particles, expected.reduced_particles)
	test.assert_eq(actual.damage_number_density, expected.damage_number_density)
	test.assert_eq(
		[
			actual.master_volume_bps, actual.master_muted,
			actual.music_volume_bps, actual.music_muted,
			actual.sfx_volume_bps, actual.sfx_muted,
			actual.ui_volume_bps, actual.ui_muted,
		],
		[
			expected.master_volume_bps, expected.master_muted,
			expected.music_volume_bps, expected.music_muted,
			expected.sfx_volume_bps, expected.sfx_muted,
			expected.ui_volume_bps, expected.ui_muted,
		]
	)
