extends GutTest

const Support = preload(
	"res://tests/integration/presentation_ui_r14_functional_controls/"
	+ "r14_functional_controls_test_support.gd"
)


func test_real_menu_start_and_default_camp_selection_start_a_run() -> void:
	var harness: Variant = Support.boot(self)
	var menu := Support.active_screen(harness)
	assert_true(Support.press(self, menu, &"menu.start"))
	assert_eq(harness.root.app_state(), AppStateMachine.State.CAMP)
	var camp := Support.active_screen(harness)
	assert_eq(camp.route_kind, &"CAMP_WORLD")

	var commander := camp.find_child(
		"CommanderSelector", true, false
	) as OptionButton
	var challenge := camp.find_child(
		"ChallengeSelector", true, false
	) as SpinBox
	assert_not_null(commander)
	assert_not_null(challenge)
	if commander == null or challenge == null:
		return
	assert_eq(commander.selected, 0)
	assert_eq(challenge.value, 0.0)
	commander.item_selected.emit(0)
	challenge.value_changed.emit(0.0)
	assert_true(Support.press(self, camp, &"camp.start"))
	assert_eq(harness.root.app_state(), AppStateMachine.State.RUN)
	assert_eq(Support.active_screen(harness).route_kind, &"RUN_MAP")


func test_camp_settings_opens_typed_draft_and_commits_locale() -> void:
	var harness: Variant = Support.boot(self)
	assert_true(Support.press(
		self,
		Support.active_screen(harness),
		&"menu.start"
	))
	var camp := Support.active_screen(harness)
	assert_true(Support.press(self, camp, &"camp.settings"))
	var settings := Support.active_screen(harness)
	assert_eq(
		settings.route_kind,
		&"SETTINGS",
		"Camp Settings must be reachable instead of a fixed unavailable callback"
	)
	assert_eq(
		harness.root.app_state(),
		AppStateMachine.State.CAMP,
		"settings is a presentation subroute and must preserve its CAMP parent"
	)
	var composition := Support.composition(settings)
	var draft_api := (
		composition != null
		and composition.has_method(&"settings_draft")
		and composition.has_method(&"replace_settings_draft")
		and composition.has_method(&"committed_settings_snapshot")
	)
	assert_true(draft_api, "Settings requires a clone-only typed SettingsSnapshot draft")
	if not draft_api:
		return
	var draft := composition.call(&"settings_draft") as SettingsSnapshot
	assert_not_null(draft)
	if draft == null:
		return
	draft.locale = &"en"
	draft.reduced_flash = not draft.reduced_flash
	assert_eq(
		StringName(composition.call(&"replace_settings_draft", draft)),
		&""
	)
	assert_true(Support.press(self, settings, &"settings.apply"))
	var applied: Variant = Support.last_control_result(self, settings)
	assert_not_null(applied)
	assert_true(bool(applied.get("ok")) if applied != null else false)
	assert_eq(
		settings.status_message_text(),
		"",
		"successful settings apply must clear the production status surface"
	)
	assert_eq(
		String(composition.call(&"status_message_text")),
		"",
		"successful settings apply must not leave a composition failure"
	)
	var committed := (
		composition.call(&"committed_settings_snapshot") as SettingsSnapshot
	)
	assert_not_null(committed)
	if committed != null:
		assert_eq(committed.locale, &"en")
		assert_eq(committed.reduced_flash, draft.reduced_flash)
	assert_true(Support.press(self, settings, &"settings.back"))
	assert_eq(Support.active_screen(harness).route_kind, &"CAMP_WORLD")
	assert_eq(harness.root.app_state(), AppStateMachine.State.CAMP)
