extends GutTest

const Support = preload(
	"res://tests/integration/presentation_ui_r14_accessibility_joint/"
	+ "r14_accessibility_joint_test_support.gd"
)


func test_app_root_settings_port_applies_to_replaced_run_combat_scene() -> void:
	var gameplay_storage := FakeSaveStorage.new()
	var settings_storage := Support.FakeSettingsStorage.new()
	var setup := Support.boot(self, gameplay_storage, settings_storage)
	assert_eq(
		setup.settings_bind_error,
		&"",
		"AppRoot must construct its consumer from injectable real settings services"
	)
	if not setup.settings_bind_error.is_empty():
		return
	assert_eq(setup.boot_error, &"")
	assert_true(setup.root.is_booted())
	var driven := Support.drive_to_run_prepare(setup)
	assert_true(
		bool(driven.get("ok", false)),
		"production intent flow must reach RUN_PREPARE: %s"
		% String(driven.get("error", &""))
	)
	if not bool(driven.get("ok", false)):
		return
	assert_eq(Support.seed_committed_combat_phase(setup), &"")
	setup.dispose()
	await wait_process_frames(3)
	var harness := Support.boot(self, gameplay_storage, settings_storage)
	assert_eq(harness.settings_bind_error, &"")
	if not harness.settings_bind_error.is_empty():
		return
	var continued := Support.continue_to_run_combat(harness)
	assert_true(
		bool(continued.get("ok", false)),
		"fresh AppRoot must Continue the fake-storage COMBAT save through SceneRouter: %s"
		% String(continued.get("error", &""))
	)
	if not bool(continued.get("ok", false)):
		return
	await wait_process_frames(3)

	var port := harness.root.settings_application_port()
	assert_not_null(port, "joint evidence must obtain the typed port from AppRoot")
	if port == null:
		return
	var candidate := Support.candidate(150, &"deuteranopia")
	candidate.locale = &"en"
	var applied: SettingsApplicationResult = port.apply(candidate)
	assert_true(applied.ok, "only AppRoot's settings port may apply the candidate")
	assert_true(applied.committed)
	assert_true(applied.presentation_ok)
	assert_null(applied.error)
	assert_true(
		Support.snapshots_equal(
			harness.settings_repository.current_snapshot(),
			candidate
		),
		"the real SettingsRepository must own the committed clone"
	)
	await wait_process_frames(3)
	var before := Support.accessibility_host(harness)
	assert_not_null(before)
	if before == null:
		return
	var before_report := before.runtime_accessibility_report()
	assert_true(before_report.ok)
	assert_false(before_report.motion_effects_enabled)
	assert_false(before_report.flash_effects_enabled)
	assert_false(before_report.particle_effects_enabled)
	assert_eq(before_report.damage_number_density, &"reduced")
	assert_true(before_report.rule_information_visible)
	assert_true(before_report.cjk_ok)
	assert_true(before_report.cjk_readable)
	assert_eq(before_report.cjk_locale, &"en")
	assert_eq(
		before_report.cjk_font_source,
		LocalizedTypographyPolicy.FONT_SOURCE_BUNDLED
	)
	assert_false(before_report.cjk_fallback_used)
	assert_eq(before_report.cjk_missing_glyphs, [])
	var old_screen_id := Support.active_screen(harness).get_instance_id()

	var reload_error := Support.reload_current_route(harness)
	assert_eq(
		reload_error,
		&"",
		"same-state RUN_COMBAT reload must still go through SceneRouter"
	)
	await wait_process_frames(4)
	var reloaded := Support.active_screen(harness)
	assert_not_null(reloaded)
	if reloaded == null:
		return
	assert_eq(reloaded.route_kind, &"RUN_COMBAT")
	assert_ne(
		reloaded.get_instance_id(),
		old_screen_id,
		"evidence must observe a real route replacement, not the old scene"
	)
	var after := Support.accessibility_host(harness)
	assert_not_null(after)
	if after == null:
		return
	var after_report := after.runtime_accessibility_report()
	assert_true(
		after_report.ok,
		"consumer child-entered callback must reapply the last committed theme"
	)
	assert_false(after_report.motion_effects_enabled)
	assert_false(after_report.flash_effects_enabled)
	assert_false(after_report.particle_effects_enabled)
	assert_eq(after_report.damage_number_density, &"reduced")
	assert_true(after_report.rule_information_visible)
	assert_true(after_report.cjk_readable)
	assert_eq(after_report.cjk_missing_glyphs, [])


func test_real_settings_repository_rebuilds_run_combat_after_app_restart() -> void:
	var gameplay_storage := FakeSaveStorage.new()
	var settings_storage := Support.FakeSettingsStorage.new()
	var first := Support.boot(self, gameplay_storage, settings_storage)
	assert_eq(first.settings_bind_error, &"")
	if not first.settings_bind_error.is_empty():
		return
	assert_true(first.root.is_booted())
	var driven := Support.drive_to_run_prepare(first)
	assert_true(bool(driven.get("ok", false)))
	if not bool(driven.get("ok", false)):
		return
	assert_eq(Support.seed_committed_combat_phase(first), &"")
	first.dispose()
	await wait_process_frames(3)

	var combat_root := Support.boot(self, gameplay_storage, settings_storage)
	assert_eq(combat_root.settings_bind_error, &"")
	if not combat_root.settings_bind_error.is_empty():
		return
	var entered_combat := Support.continue_to_run_combat(combat_root)
	assert_true(
		bool(entered_combat.get("ok", false)),
		"COMBAT restart must use the production route composition: %s"
		% String(entered_combat.get("error", &""))
	)
	if not bool(entered_combat.get("ok", false)):
		return
	var candidate := Support.candidate(125, &"tritanopia")
	var port := combat_root.root.settings_application_port()
	assert_not_null(port)
	if port == null:
		return
	assert_true(port.apply(candidate).ok)
	await wait_process_frames(3)
	combat_root.dispose()
	await wait_process_frames(3)

	var restarted := Support.boot(self, gameplay_storage, settings_storage)
	assert_eq(restarted.settings_bind_error, &"")
	if not restarted.settings_bind_error.is_empty():
		return
	assert_true(restarted.root.is_booted())
	assert_true(
		Support.snapshots_equal(
			restarted.settings_repository.current_snapshot(),
			candidate
		),
		"fresh real SettingsRepository must decode the committed schema-1 bytes"
	)
	var continued := Support.continue_to_run_combat(restarted)
	assert_true(
		bool(continued.get("ok", false)),
		"restart Continue must route the committed COMBAT run: %s"
		% String(continued.get("error", &""))
	)
	if not bool(continued.get("ok", false)):
		return
	await wait_process_frames(4)
	var runtime := Support.accessibility_host(restarted)
	assert_not_null(runtime)
	if runtime == null:
		return
	var report := runtime.runtime_accessibility_report()
	assert_true(report.ok)
	assert_false(report.motion_effects_enabled)
	assert_false(report.flash_effects_enabled)
	assert_false(report.particle_effects_enabled)
	assert_eq(report.damage_number_density, &"reduced")
	assert_eq(report.cjk_locale, &"zh_TW")
	assert_true(report.cjk_readable)
	assert_eq(report.cjk_missing_glyphs, [])
