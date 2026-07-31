extends GutTest

## G2 H3：錯誤呈現面。PresentationErrorMapper／DiagnosticError 這條鏈以前只有測試在讀，
## 玩家操作失敗時畫面零變化。這裡驗的是「畫面上真的出現在地化訊息，且 pre/post-commit
## 是兩句不同的話」。

const Support = preload(
	"res://tests/integration/presentation_ui_g2_findings/"
	+ "g2_findings_test_support.gd"
)


func test_failed_camp_action_renders_localized_precommit_status() -> void:
	var harness: Variant = Support.boot(self)
	assert_true(Support.press(self, Support.active_screen(harness), &"menu.start"))
	var camp := Support.active_screen(harness)
	assert_eq(camp.route_kind, &"CAMP_WORLD")

	assert_eq(
		camp.status_message_text(),
		"",
		"a freshly staged screen must not show a stale error"
	)
	assert_true(Support.press(self, camp, &"camp.start"))

	var report := camp.status_report()
	assert_eq(
		StringName(report.get("source_code", &"")),
		&"CAMP_EXPEDITION_SELECTION_REQUIRED"
	)
	assert_eq(report.get("committed"), false)
	assert_eq(report.get("fallback_active"), false)
	assert_eq(report.get("retryable"), false)

	var expected := (
		camp.localized_ui_text(&"error.status.pre_commit")
		+ camp.localized_ui_text(&"error.presentation.camp_selection_required")
	)
	assert_eq(camp.status_message_text(), expected)
	assert_false(camp.status_message_text().is_empty())
	assert_false(
		camp.status_message_text().contains("error."),
		"the surface must render localized text, not the raw message key"
	)


func test_successful_action_clears_the_status_surface() -> void:
	var harness: Variant = Support.boot(self)
	assert_true(Support.press(self, Support.active_screen(harness), &"menu.start"))
	var camp := Support.active_screen(harness)
	assert_true(Support.press(self, camp, &"camp.start"))
	assert_false(camp.status_message_text().is_empty())

	var composition := camp.get_node_or_null("Composition") as CampWorldScreen
	assert_not_null(composition)
	if composition == null:
		return
	var commanders: Array[StringName] = (
		(harness.root as ApplicationRoot)
			.try_camp_view_model()
			.commander_hall_unlocked_commander_ids()
	)
	assert_false(commanders.is_empty())
	if commanders.is_empty():
		return
	assert_eq(
		StringName(composition.select_expedition(commanders[0], 0)),
		&""
	)
	assert_true(Support.press(self, camp, &"camp.start"))
	assert_eq(
		camp.status_message_text(),
		"",
		"a successful action must clear the error surface"
	)
	assert_true(camp.status_report().is_empty())


func test_precommit_and_postcommit_failures_read_differently() -> void:
	var host := Control.new()
	add_child_autofree(host)
	var catalog := LocalizationCatalog.restricted_emergency_catalog()
	var resolver := func(key: StringName) -> String:
		var resolved := catalog.resolve(&"zh_TW", key)
		return resolved.value if resolved.ok else String(key)

	var view := PresentationStatusView.new()
	assert_not_null(view.attach(host))

	view.show_failure(&"ROUTE_BIND_FAILED", false, &"", resolver)
	var precommit := view.message_text()
	assert_eq(view.report().get("fallback_active"), false)
	assert_eq(view.report().get("retryable"), false)

	view.show_failure(&"ROUTE_BIND_FAILED", true, &"", resolver)
	var postcommit := view.message_text()
	assert_eq(view.report().get("fallback_active"), true)
	assert_eq(view.report().get("retryable"), true)

	assert_false(precommit.is_empty())
	assert_false(postcommit.is_empty())
	assert_ne(
		precommit,
		postcommit,
		"the player must be able to tell 'nothing changed' from 'already applied'"
	)
	assert_false(precommit.contains("error."))
	assert_false(postcommit.contains("error."))

	view.clear(resolver)
	assert_eq(view.message_text(), "")
	assert_true(view.report().is_empty())


func test_settings_draft_rejection_is_visible_on_the_settings_screen() -> void:
	var harness: Variant = Support.boot(self)
	assert_true(Support.press(self, Support.active_screen(harness), &"menu.start"))
	assert_true(Support.press(self, Support.active_screen(harness), &"camp.settings"))
	var settings := Support.active_screen(harness)
	assert_eq(settings.route_kind, &"SETTINGS")
	var composition := (
		settings.get_node_or_null("Composition") as SettingsScreenComposition
	)
	assert_not_null(composition)
	if composition == null:
		return
	assert_eq(composition.visible_error_key(), &"")
	assert_eq(composition.status_message_text(), "")

	var draft := composition.settings_draft()
	assert_not_null(draft)
	if draft == null:
		return
	draft.locale = &"xx_YY"
	assert_eq(
		StringName(composition.replace_settings_draft(draft)),
		SettingsScreenPresenter.SETTINGS_INVALID_ENUM
	)
	assert_eq(composition.visible_error_key(), &"error.settings.invalid_enum")
	assert_false(
		composition.status_message_text().is_empty(),
		"a rejected settings draft must be visible, not only stored as a code"
	)
	assert_false(composition.status_message_text().contains("error."))

	var valid := composition.settings_draft()
	valid.locale = &"en"
	assert_eq(StringName(composition.replace_settings_draft(valid)), &"")
	assert_eq(composition.visible_error_key(), &"")
	assert_eq(composition.status_message_text(), "")
