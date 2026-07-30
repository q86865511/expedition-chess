extends GutTest

const Support = preload(
	"res://tests/integration/presentation_ui_r15_behavior/"
	+ "r15_behavior_test_support.gd"
)


func test_recovery_modal_traps_focus_blocks_background_and_restores_trigger() -> void:
	var snapshot := MainMenuSnapshot.new()
	snapshot.can_start = true
	snapshot.has_recovery = true
	var localized: Dictionary = {}
	for action_id: StringName in [
		&"menu.start",
		&"menu.recovery",
		&"menu.recovery.confirm",
		&"menu.recovery.cancel",
		&"menu.settings",
		&"menu.exit",
	]:
		localized[action_id] = String(action_id)
	var screen := ProductionSceneCatalog.new().instantiate(&"MENU_MAIN")
	assert_not_null(screen)
	if screen == null:
		return
	assert_eq(
		screen.bind(
			StagedScreenContext.new(
				&"MENU_MAIN",
				snapshot,
				null,
				&"en",
				localized
			)
		),
		&""
	)
	var counts := {
		"recovery": 0,
		"confirm": 0,
		"cancel": 0,
		"settings": 0,
	}
	var callbacks: Dictionary = {
		&"menu.recovery": func() -> AppActionResult:
			counts["recovery"] += 1
			return AppActionResult.success(false),
		&"menu.recovery.confirm": func() -> AppActionResult:
			counts["confirm"] += 1
			return AppActionResult.success(false),
		&"menu.recovery.cancel": func() -> AppActionResult:
			counts["cancel"] += 1
			return AppActionResult.success(false),
		&"menu.settings": func() -> AppActionResult:
			counts["settings"] += 1
			return AppActionResult.success(false),
	}
	var registry := LiveScreenLeaseRegistry.new()
	var lease := registry.activate(AppStateMachine.State.MENU, 153)
	assert_eq(
		screen.prepare_live_binding(
			ProductionLiveScreenContext.new(
				&"MENU_MAIN",
				snapshot,
				null,
				ProductionScreenActionPort.new(
					lease,
					registry,
					callbacks
				),
				LiveScreenNavigationPort.new()
			)
		),
		&""
	)
	add_child_autofree(screen)
	screen.activate_live()
	await wait_process_frames(2)
	var trigger := Support.action_button(screen, &"menu.recovery")
	var settings := Support.action_button(screen, &"menu.settings")
	assert_not_null(trigger)
	assert_not_null(settings)
	if trigger == null or settings == null:
		return
	trigger.grab_focus()
	assert_eq(get_viewport().gui_get_focus_owner(), trigger)
	trigger.pressed.emit()
	await wait_process_frames(2)
	assert_eq(int(counts["recovery"]), 1)
	var dialog := screen.get_node_or_null(^"RecoveryConfirmation") as Control
	assert_not_null(dialog)
	if dialog == null:
		return

	for node: Node in screen.get_node(^"Actions").find_children(
		"*",
		"Button",
		true,
		false
	):
		var background := node as Button
		assert_true(
			background.disabled or background.focus_mode == Control.FOCUS_NONE,
			"modal must remove every background action from focus/input"
		)
	settings.pressed.emit()
	assert_eq(
		int(counts["settings"]),
		0,
		"even a queued background signal must be rejected while modal"
	)
	var focused := get_viewport().gui_get_focus_owner()
	assert_true(
		focused != null and dialog.is_ancestor_of(focused),
		"focus must enter the recovery dialog"
	)
	for _step: int in 5:
		var next := InputEventAction.new()
		next.action = &"ui_focus_next"
		next.pressed = true
		get_viewport().push_input(next)
		await wait_process_frames(1)
		focused = get_viewport().gui_get_focus_owner()
		assert_true(
			focused != null and dialog.is_ancestor_of(focused),
			"Tab traversal must remain trapped inside the modal"
		)

	var cancel := Support.action_button(
		screen,
		&"menu.recovery.cancel"
	)
	assert_not_null(cancel)
	if cancel == null:
		return
	cancel.pressed.emit()
	await wait_process_frames(3)
	assert_eq(int(counts["cancel"]), 1)
	assert_null(screen.get_node_or_null(^"RecoveryConfirmation"))
	assert_eq(
		get_viewport().gui_get_focus_owner(),
		trigger,
		"closing the modal must restore the exact trigger focus"
	)
	assert_false(settings.disabled)
	assert_eq(settings.focus_mode, Control.FOCUS_ALL)
	settings.pressed.emit()
	assert_eq(int(counts["settings"]), 1)
