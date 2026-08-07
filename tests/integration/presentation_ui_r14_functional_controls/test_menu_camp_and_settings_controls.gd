extends GutTest

const Support = preload(
	"res://tests/integration/presentation_ui_r14_functional_controls/"
	+ "r14_functional_controls_test_support.gd"
)


func test_real_menu_start_and_typed_camp_selection_start_a_run() -> void:
	var harness: Variant = Support.boot(self)
	var menu := Support.active_screen(harness)
	assert_true(Support.press(self, menu, &"menu.start"))
	assert_eq(harness.root.app_state(), AppStateMachine.State.CAMP)
	var camp := Support.active_screen(harness)
	assert_eq(camp.route_kind, &"CAMP_WORLD")

	assert_true(Support.press(self, camp, &"camp.start"))
	var missing_selection: Variant = Support.last_control_result(self, camp)
	if missing_selection == null:
		return
	assert_eq(
		Support.error_code(missing_selection),
		&"CAMP_EXPEDITION_SELECTION_REQUIRED",
		"missing typed commander/challenge selection needs an exact precondition"
	)
	assert_ne(
		Support.error_code(missing_selection),
		ApplicationRoot.ERROR_ACTION_NOT_AVAILABLE
	)

	var composition := Support.composition(camp)
	var selectable := (
		composition != null
		and composition.has_method(&"select_expedition")
	)
	assert_true(
		selectable,
		"CAMP_WORLD must own a consumer draft for commander/challenge selection"
	)
	if not selectable:
		return
	var commander_id := Support.first_commander(harness.root)
	assert_ne(commander_id, &"")
	assert_eq(
		StringName(composition.call(&"select_expedition", commander_id, 0)),
		&""
	)
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
	assert_true(Support.press(self, settings, &"settings.back"))
	assert_eq(Support.active_screen(harness).route_kind, &"CAMP_WORLD")
	assert_eq(harness.root.app_state(), AppStateMachine.State.CAMP)
