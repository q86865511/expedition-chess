extends RefCounted

const ADAPTER_PATHS := {
	&"theme": "res://services/settings/adapters/theme_settings_adapter.gd",
	&"viewport": "res://services/settings/adapters/viewport_settings_adapter.gd",
	&"localization": (
		"res://services/settings/adapters/localization_settings_adapter.gd"
	),
	&"audio": "res://services/settings/adapters/audio_settings_adapter.gd",
}


class FakeRepositoryResult:
	extends RefCounted

	var ok: bool
	var snapshot: SettingsSnapshot
	var error: DiagnosticError

	func _init(
		p_ok: bool,
		p_snapshot: SettingsSnapshot,
		p_error: DiagnosticError = null
	) -> void:
		ok = p_ok
		snapshot = p_snapshot.deep_clone() if p_snapshot != null else null
		error = p_error.deep_clone() if p_error != null else null


class FakeRepository:
	extends RefCounted

	var committed := SettingsSnapshot.new()
	var save_count: int = 0
	var current_read_count: int = 0
	var save_fault: bool = false
	var read_fault: bool = false
	var journal: Array[StringName]

	func _init(
		p_journal: Array[StringName],
		p_committed: SettingsSnapshot = null
	) -> void:
		journal = p_journal
		if p_committed != null:
			committed = p_committed.deep_clone()

	func save(candidate: SettingsSnapshot) -> FakeRepositoryResult:
		save_count += 1
		journal.append(&"repository:save")
		if save_fault:
			return FakeRepositoryResult.new(
				false,
				null,
				DiagnosticError.new(
					&"SETTINGS_STORAGE_FAULT",
					&"error.settings.storage_fault"
				)
			)
		committed = candidate.deep_clone()
		return FakeRepositoryResult.new(true, committed)

	func current_snapshot() -> SettingsSnapshot:
		current_read_count += 1
		journal.append(&"repository:fresh_read")
		return null if read_fault else committed.deep_clone()


class FakeRuntimeConsumer:
	extends RefCounted

	var journal: Array[StringName]
	var runtime_by_kind: Dictionary = {}
	var preflight_fault_kind: StringName = &""

	func _init(p_journal: Array[StringName]) -> void:
		journal = p_journal

	func preflight(
		kind: StringName,
		plan: SettingsSnapshot
	) -> StringName:
		journal.append(StringName("preflight:%s" % String(kind)))
		if plan == null or kind == preflight_fault_kind:
			return StringName(
				"SETTINGS_%s_PREFLIGHT_FAILED" % String(kind).to_upper()
			)
		return &""

	func activate(
		kind: StringName,
		snapshot: SettingsSnapshot
	) -> void:
		journal.append(StringName("activate:%s" % String(kind)))
		runtime_by_kind[kind] = snapshot.deep_clone()

	func activate_safe_fallback(kind: StringName) -> void:
		journal.append(StringName("fallback:%s" % String(kind)))
		runtime_by_kind[kind] = SettingsSnapshot.new()


class FakeAudioBusPort:
	extends AudioBusPort

	var journal: Array[StringName]
	var apply_count: int = 0
	var assignments: Dictionary = {}

	func _init(p_journal: Array[StringName]) -> void:
		journal = p_journal

	func apply_batch(batch: AudioBusBatch) -> AudioBusBatchResult:
		apply_count += 1
		journal.append(&"activate:audio")
		if batch == null or batch.assignments.size() != 4:
			return AudioBusBatchResult.failure(AUDIO_BUS_BATCH_INVALID)
		var next_assignments: Dictionary = {}
		for assignment: AudioBusAssignment in batch.assignments:
			next_assignments[assignment.bus] = assignment.deep_clone()
		assignments = next_assignments
		return AudioBusBatchResult.success()


static func require_adapter_scripts(test: Variant) -> bool:
	var complete := true
	for kind: StringName in ADAPTER_PATHS:
		var path := String(ADAPTER_PATHS[kind])
		var exists := FileAccess.file_exists(path)
		test.assert_true(
			exists,
			"T12 concrete %s adapter missing: %s" % [String(kind), path]
		)
		if not exists:
			complete = false
			continue
		var source := FileAccess.get_file_as_string(path)
		for token: String in [
			"extends SettingsAdapterPort",
			"func preflight(",
			"func activate_safe_fallback(",
			"func rebuild_from_committed(",
		]:
			var has_token := source.contains(token)
			test.assert_true(
				has_token,
				"T12 concrete %s adapter missing `%s`" % [String(kind), token]
			)
			complete = complete and has_token
	if not complete:
		return false
	var viewport_source := FileAccess.get_file_as_string(
		String(ADAPTER_PATHS[&"viewport"])
	)
	test.assert_true(viewport_source.contains("WorldViewportPolicy"))
	test.assert_true(viewport_source.contains("WindowCoordinateMapper"))
	var localization_source := FileAccess.get_file_as_string(
		String(ADAPTER_PATHS[&"localization"])
	)
	test.assert_true(localization_source.contains("LocalizationCatalog"))
	var audio_source := FileAccess.get_file_as_string(
		String(ADAPTER_PATHS[&"audio"])
	)
	test.assert_true(audio_source.contains("AudioCoordinator"))
	return true


static func build_adapters(
	test: Variant,
	consumer: FakeRuntimeConsumer,
	audio_port: FakeAudioBusPort,
	window_size: Vector2i = Vector2i(1920, 1080)
) -> Array[Object]:
	if not require_adapter_scripts(test):
		return []
	var theme_script := load(String(ADAPTER_PATHS[&"theme"])) as GDScript
	var viewport_script := load(String(ADAPTER_PATHS[&"viewport"])) as GDScript
	var localization_script := load(
		String(ADAPTER_PATHS[&"localization"])
	) as GDScript
	var audio_script := load(String(ADAPTER_PATHS[&"audio"])) as GDScript
	test.assert_not_null(theme_script)
	test.assert_not_null(viewport_script)
	test.assert_not_null(localization_script)
	test.assert_not_null(audio_script)
	if (
		theme_script == null
		or viewport_script == null
		or localization_script == null
		or audio_script == null
	):
		return []
	var adapters: Array[Object] = [
		theme_script.new(consumer),
		viewport_script.new(
			consumer,
			WorldViewportPolicy.new(),
			WindowCoordinateMapper.new(),
			window_size
		),
		localization_script.new(consumer, LocalizationCatalog.new()),
		audio_script.new(test.autofree(AudioCoordinator.new(audio_port))),
	]
	for adapter: Object in adapters:
		test.assert_not_null(adapter)
	return adapters


static func candidate(
	locale: StringName,
	ui_scale_percent: int
) -> SettingsSnapshot:
	var snapshot := SettingsSnapshot.new()
	snapshot.locale = locale
	snapshot.ui_scale_percent = ui_scale_percent
	snapshot.color_vision_mode = &"tritanopia"
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


static func assert_consumer_matches(
	test: Variant,
	consumer: FakeRuntimeConsumer,
	expected: SettingsSnapshot
) -> void:
	for kind: StringName in [&"theme", &"viewport", &"localization"]:
		test.assert_true(
			consumer.runtime_by_kind.has(kind),
			"runtime consumer did not activate %s" % String(kind)
		)
		if consumer.runtime_by_kind.has(kind):
			assert_snapshot_matches(
				test,
				consumer.runtime_by_kind[kind] as SettingsSnapshot,
				expected
			)


static func assert_audio_matches(
	test: Variant,
	audio_port: FakeAudioBusPort,
	expected: SettingsSnapshot
) -> void:
	var expected_values := {
		&"Master": [expected.master_volume_bps, expected.master_muted],
		&"Music": [expected.music_volume_bps, expected.music_muted],
		&"SFX": [expected.sfx_volume_bps, expected.sfx_muted],
		&"UI": [expected.ui_volume_bps, expected.ui_muted],
	}
	test.assert_eq(audio_port.assignments.size(), 4)
	for bus: StringName in expected_values:
		test.assert_true(
			audio_port.assignments.has(bus),
			"audio runtime missing %s bus" % String(bus)
		)
		if not audio_port.assignments.has(bus):
			continue
		var assignment := audio_port.assignments[bus] as AudioBusAssignment
		var values: Array = expected_values[bus]
		test.assert_eq(assignment.volume_bps, values[0])
		test.assert_eq(assignment.muted, values[1])


static func assert_snapshot_matches(
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
	test.assert_eq(actual.master_volume_bps, expected.master_volume_bps)
	test.assert_eq(actual.master_muted, expected.master_muted)
	test.assert_eq(actual.music_volume_bps, expected.music_volume_bps)
	test.assert_eq(actual.music_muted, expected.music_muted)
	test.assert_eq(actual.sfx_volume_bps, expected.sfx_volume_bps)
	test.assert_eq(actual.sfx_muted, expected.sfx_muted)
	test.assert_eq(actual.ui_volume_bps, expected.ui_volume_bps)
	test.assert_eq(actual.ui_muted, expected.ui_muted)
