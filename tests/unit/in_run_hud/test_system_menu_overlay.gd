extends GutTest


class FakeSettingsPort:
	extends SettingsApplicationPort

	var calls: int = 0
	var received: SettingsSnapshot

	func apply(candidate: SettingsSnapshot) -> SettingsApplicationResult:
		calls += 1
		received = candidate.deep_clone() if candidate != null else null
		return SettingsApplicationResult.success(candidate)


func test_state_machine_embeds_shared_settings_and_never_routes() -> void:
	var fixture := _fixture()
	var overlay := fixture["overlay"] as SystemMenuOverlay
	var port := fixture["port"] as FakeSettingsPort
	assert_true(overlay.open([fixture["background"] as Control]))
	assert_eq(overlay.state_name(), &"ROOT")
	var continue_button := _button(overlay, &"menu.continue")
	assert_not_null(continue_button)
	if continue_button != null:
		assert_eq(continue_button.text, "繼續遠征")
		assert_eq(
			StringName(continue_button.get_meta(&"localization_key", &"")),
			&"menu.continue"
		)

	assert_true(_press(overlay, &"system_menu.settings"))
	assert_eq(overlay.state_name(), &"SETTINGS_EMBEDDED")
	var composition := overlay.settings_composition()
	assert_true(composition is SettingsScreenComposition)
	if composition == null:
		return
	var draft := composition.settings_draft()
	draft.ui_scale_percent = 125
	assert_eq(composition.replace_settings_draft(draft), &"")
	assert_true(_press(overlay, &"settings.apply"))
	assert_eq(port.calls, 1)
	assert_not_null(port.received)
	if port.received != null:
		assert_eq(port.received.ui_scale_percent, 125)
	assert_eq(
		overlay.state_name(),
		&"SETTINGS_EMBEDDED",
		"applying embedded settings must not transition the run route"
	)

	assert_true(overlay.handle_system_menu_action())
	assert_eq(overlay.state_name(), &"ROOT")
	assert_true(overlay.handle_system_menu_action())
	assert_eq(overlay.state_name(), &"CLOSED")


func test_confirm_states_cancel_to_root_and_emit_only_after_confirm() -> void:
	var fixture := _fixture()
	var overlay := fixture["overlay"] as SystemMenuOverlay
	var menu_requests: Array[int] = []
	var exit_requests: Array[int] = []
	overlay.return_to_menu_requested.connect(func() -> void:
		menu_requests.append(1)
	)
	overlay.exit_requested.connect(func() -> void:
		exit_requests.append(1)
	)
	assert_true(overlay.open())

	assert_true(_press(overlay, &"run.menu"))
	assert_eq(overlay.state_name(), &"CONFIRM_MENU")
	assert_eq(overlay.confirmation_node_name(), "RunMenuConfirmation")
	assert_eq(menu_requests.size(), 0)
	assert_true(_press(overlay, &"run.menu.cancel"))
	assert_eq(overlay.state_name(), &"ROOT")
	assert_eq(menu_requests.size(), 0, "cancel must remain zero-dispatch")

	assert_true(_press(overlay, &"run.menu"))
	assert_true(_press(overlay, &"run.menu.confirm"))
	assert_eq(menu_requests.size(), 1)
	assert_eq(exit_requests.size(), 0)
	assert_true(overlay.handle_system_menu_action())
	assert_eq(overlay.state_name(), &"ROOT")

	assert_true(_press(overlay, &"menu.exit"))
	assert_eq(overlay.state_name(), &"CONFIRM_EXIT")
	assert_eq(exit_requests.size(), 0)
	assert_true(_press(overlay, &"menu.exit.confirm"))
	assert_eq(exit_requests.size(), 1)


func test_focus_is_trapped_and_restored_across_dynamic_pages() -> void:
	var fixture := _fixture()
	var overlay := fixture["overlay"] as SystemMenuOverlay
	var background := fixture["background"] as Button
	background.grab_focus()
	await wait_process_frames(1)
	assert_true(overlay.open([background]))
	assert_eq(background.focus_mode, Control.FOCUS_NONE)
	await wait_process_frames(1)
	_assert_focus_cycle_is_inside_overlay(overlay)

	assert_true(_press(overlay, &"system_menu.settings"))
	await wait_process_frames(1)
	_assert_focus_cycle_is_inside_overlay(overlay)
	assert_true(overlay.close())
	assert_eq(background.focus_mode, Control.FOCUS_ALL)
	await wait_process_frames(1)
	assert_eq(
		background.get_viewport().gui_get_focus_owner(),
		background,
		"closing the overlay restores the pre-open focus owner"
	)


func _fixture() -> Dictionary:
	var host := Control.new()
	host.size = Vector2(1920.0, 1080.0)
	add_child_autofree(host)
	var background := Button.new()
	background.name = "UnderlyingAction"
	background.focus_mode = Control.FOCUS_ALL
	host.add_child(background)
	var overlay := SystemMenuOverlay.new()
	overlay.name = "SystemMenuOverlay"
	host.add_child(overlay)
	var port := FakeSettingsPort.new()
	overlay.configure(_localized(), SettingsSnapshot.new(), port)
	return {
		"host": host,
		"background": background,
		"overlay": overlay,
		"port": port,
	}


func _press(overlay: SystemMenuOverlay, action_id: StringName) -> bool:
	var button := _button(overlay, action_id)
	if button != null:
		button.pressed.emit()
		return true
	assert_true(false, "missing system-menu action %s" % String(action_id))
	return false


func _button(
	overlay: SystemMenuOverlay,
	action_id: StringName
) -> Button:
	for node: Node in overlay.find_children("*", "Button", true, false):
		var button := node as Button
		if (
			button != null
			and button.has_meta(&"action_id")
			and StringName(button.get_meta(&"action_id")) == action_id
		):
			return button
	return null


func _assert_focus_cycle_is_inside_overlay(
	overlay: SystemMenuOverlay
) -> void:
	var controls := overlay.active_focus_controls()
	assert_false(controls.is_empty())
	for control: Control in controls:
		assert_true(overlay.is_ancestor_of(control))
		assert_ne(control.focus_mode, Control.FOCUS_NONE)
		var next := control.get_node_or_null(control.focus_next) as Control
		assert_not_null(next)
		if next != null:
			assert_true(
				overlay.is_ancestor_of(next),
				"Tab focus must never escape to the run HUD"
			)


func _localized() -> Dictionary:
	return {
		&"system_menu.title": "系統選單",
		&"menu.continue": "繼續遠征",
		&"system_menu.settings": "設定",
		&"run.menu": "返回主選單",
		&"menu.exit": "離開遊戲",
		&"run.menu.status": "返回主選單？",
		&"run.menu.confirm": "確認返回",
		&"run.menu.cancel": "取消",
		&"menu.exit.status": "離開遊戲？",
		&"menu.exit.confirm": "確認離開",
		&"menu.exit.cancel": "取消",
		&"settings.apply": "套用",
		&"settings.back": "返回",
	}
