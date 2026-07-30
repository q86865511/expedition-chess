extends GutTest

const Support := preload(
	"res://tests/integration/presentation_ui_settings_runtime/settings_runtime_test_support.gd"
)


func test_concrete_adapters_apply_and_rebuild_all_runtime_settings() -> void:
	var cases: Array[SettingsSnapshot] = [
		Support.candidate(&"zh_TW", 100),
		Support.candidate(&"en", 125),
		Support.candidate(&"zh_TW", 150),
	]
	for candidate: SettingsSnapshot in cases:
		_assert_apply_then_restart_rebuild(candidate)


func _assert_apply_then_restart_rebuild(candidate: SettingsSnapshot) -> void:
	var journal: Array[StringName] = []
	var repository := Support.FakeRepository.new(journal)
	var consumer := Support.FakeRuntimeConsumer.new(journal)
	var audio_port := Support.FakeAudioBusPort.new(journal)
	var adapters := Support.build_adapters(self, consumer, audio_port)
	if adapters.size() != 4:
		return
	var coordinator := SettingsApplicationCoordinator.new(
		repository,
		adapters[0],
		adapters[1],
		adapters[2],
		adapters[3]
	)

	var applied := coordinator.apply(candidate.deep_clone())

	assert_true(applied.ok, applied.error.source_code if applied.error != null else &"")
	assert_true(applied.committed)
	assert_true(applied.presentation_ok)
	assert_eq(repository.save_count, 1)
	assert_eq(audio_port.apply_count, 1)
	Support.assert_consumer_matches(self, consumer, candidate)
	Support.assert_audio_matches(self, audio_port, candidate)
	assert_lt(
		journal.find(&"preflight:theme"),
		journal.find(&"repository:save"),
		"all preflight work must precede the repository commit"
	)
	assert_lt(
		journal.find(&"repository:save"),
		journal.find(&"activate:theme"),
		"runtime activation must happen only after the repository commit"
	)
	assert_lt(
		journal.find(&"repository:save"),
		journal.find(&"activate:audio"),
		"audio mutation must happen only after the repository commit"
	)

	var restart_journal: Array[StringName] = []
	var restart_repository := Support.FakeRepository.new(
		restart_journal,
		repository.committed
	)
	var restart_consumer := Support.FakeRuntimeConsumer.new(restart_journal)
	var restart_audio_port := Support.FakeAudioBusPort.new(restart_journal)
	var restart_adapters := Support.build_adapters(
		self,
		restart_consumer,
		restart_audio_port
	)
	if restart_adapters.size() != 4:
		return
	var restarted := SettingsApplicationCoordinator.new(
		restart_repository,
		restart_adapters[0],
		restart_adapters[1],
		restart_adapters[2],
		restart_adapters[3]
	)

	var rebuilt := restarted.rebuild_from_repository()

	assert_true(rebuilt.ok, rebuilt.error.source_code if rebuilt.error != null else &"")
	assert_eq(restart_repository.current_read_count, 1)
	assert_eq(restart_repository.save_count, 0)
	assert_eq(restart_audio_port.apply_count, 1)
	Support.assert_snapshot_matches(self, rebuilt.snapshot, candidate)
	Support.assert_consumer_matches(self, restart_consumer, candidate)
	Support.assert_audio_matches(self, restart_audio_port, candidate)
