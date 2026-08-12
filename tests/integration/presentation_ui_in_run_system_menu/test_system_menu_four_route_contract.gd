extends GutTest

const PlaybackSupport = preload(
	"res://tests/integration/presentation_ui_g2_combat_flow/"
	+ "g2_combat_flow_test_support.gd"
)

const RUN_ROUTES: Array[StringName] = [
	&"RUN_MAP",
	&"RUN_PREPARE",
	&"RUN_COMBAT",
	&"RUN_REWARD",
]


func test_four_run_routes_replace_resident_run_menu_with_system_button() -> void:
	var graph := KeyboardFocusGraph.new()
	for route: StringName in RUN_ROUTES:
		var screen := ProductionSceneCatalog.new().instantiate(route)
		assert_not_null(screen)
		if screen == null:
			continue
		assert_eq(screen.bind(StagedScreenContext.new(
			route,
			RunPresentationSnapshot.new(),
			null,
			&"zh_TW",
			_localized()
		)), &"")
		add_child_autofree(screen)
		var required: Array = screen.call(&"_required_action_ids")
		assert_false(
			required.has(&"run.menu"),
			"%s resident action contract must not contain run.menu" % route
		)
		assert_false(
			graph.focus_order(route, 100, []).has(&"run.menu"),
			"%s primary focus graph must match the route contract" % route
		)
		var menu_button := screen.system_menu_button()
		assert_not_null(menu_button)
		assert_eq(menu_button.name, "SystemMenuButton")
		assert_eq(
			StringName(menu_button.get_meta(&"localization_key", &"")),
			&"screen.run_container.title"
		)
		assert_eq(menu_button.text, _localized()[&"screen.run_container.title"])
		assert_eq(
			String(menu_button.get_meta(&"accessible_text", "")),
			menu_button.text,
			"visible, accessible, and metadata localization must stay aligned"
		)
		menu_button.disabled = false
		assert_true(
			screen.call(&"_ordered_focus_controls").has(menu_button),
			"SystemMenuButton must be a stable keyboard focus stop"
		)
		for node: Node in screen.find_children("*", "Button", true, false):
			var button := node as Button
			if button == null or not button.has_meta(&"action_id"):
				continue
			assert_ne(
				StringName(button.get_meta(&"action_id")),
				&"run.menu",
				"closed HUD must not retain a hidden run.menu button"
			)
		var overlay := screen.system_menu_overlay()
		assert_not_null(overlay)
		if route == &"RUN_PREPARE":
			var overlay_region := screen.layout_content(
				ProductionLayoutShell.REGION_OVERLAY
			)
			assert_not_null(overlay_region)
			if overlay_region != null:
				assert_true(overlay_region.is_ancestor_of(overlay))


func test_system_menu_input_prioritizes_modal_popup_and_text_edit() -> void:
	var screen := _synthetic_screen(&"RUN_MAP")
	var overlay := screen.system_menu_overlay()
	var event := _system_menu_event()

	screen.set(&"_modal_open", true)
	screen.call(&"_unhandled_input", event)
	assert_false(bool(screen.get(&"_modal_open")))
	assert_eq(overlay.state_name(), &"CLOSED")

	var popup := PopupPanel.new()
	popup.name = "ExistingPopup"
	screen.add_child(popup)
	popup.popup(Rect2i(20, 20, 120, 80))
	assert_true(popup.visible)
	screen.call(&"_unhandled_input", event)
	assert_false(popup.visible)
	assert_eq(overlay.state_name(), &"CLOSED")

	var editor := LineEdit.new()
	editor.name = "ExistingTextEdit"
	screen.add_child(editor)
	editor.grab_focus()
	await wait_process_frames(1)
	screen.call(&"_unhandled_input", event)
	assert_ne(screen.get_viewport().gui_get_focus_owner(), editor)
	assert_eq(overlay.state_name(), &"CLOSED")

	screen.call(&"_unhandled_input", event)
	assert_eq(overlay.state_name(), &"ROOT")
	assert_true(_press(overlay, &"system_menu.settings"))
	assert_eq(overlay.state_name(), &"SETTINGS_EMBEDDED")
	screen.call(&"_unhandled_input", event)
	assert_eq(overlay.state_name(), &"ROOT")
	screen.call(&"_unhandled_input", event)
	assert_eq(overlay.state_name(), &"CLOSED")
	await wait_process_frames(2)


func test_combat_menu_restores_true_false_pause_and_canonical_digest() -> void:
	for initially_paused: bool in [false, true]:
		var session := RunPresentationSession.new()
		PlaybackSupport.install_transcript(
			self,
			session,
			PlaybackSupport.tick_events(16),
			PlaybackSupport.identity()
		)
		if initially_paused:
			assert_true(session.set_playback_paused(true).ok)
		var registry := LiveScreenLeaseRegistry.new()
		var lease := registry.activate(AppStateMachine.State.RUN, 880)
		var port := LiveScreenPlaybackPort.new(lease, registry, session)
		var screen := _synthetic_screen(&"RUN_COMBAT", port)
		var before := session.try_playback().state
		var before_digest := (
			before.transcript_identity.committed_result_digest
		)
		assert_true(screen.open_system_menu())
		assert_true(session.try_playback().state.paused)
		assert_false(
			screen.open_system_menu(),
			"subpage/repeated open must not overwrite the captured pause state"
		)
		assert_true(screen.close_system_menu())
		var after := session.try_playback().state
		assert_eq(after.paused, initially_paused)
		assert_eq(after.cursor, before.cursor)
		assert_eq(
			after.transcript_identity.committed_result_digest,
			before_digest,
			"system-menu pause is presentation-only; canonical digest must not change"
		)
		await wait_process_frames(2)


func test_confirmed_exit_uses_injected_safe_exit_handler_once() -> void:
	var screen := _synthetic_screen(&"RUN_MAP")
	var exits: Array[int] = []
	assert_eq(screen.bind_system_menu_exit_handler(func() -> void:
		exits.append(1)
	), &"")
	assert_true(screen.open_system_menu())
	var overlay := screen.system_menu_overlay()
	assert_true(_press(overlay, &"menu.exit"))
	assert_eq(exits.size(), 0)
	assert_true(_press(overlay, &"menu.exit.confirm"))
	assert_eq(exits.size(), 1)
	assert_eq(overlay.state_name(), &"CLOSED")


func test_shared_hud_focus_is_trapped_once_and_raw_fallback_is_localized() -> void:
	var screen := _synthetic_screen(&"RUN_MAP")
	var shared_controls: Array[Control] = []
	for control_name: StringName in [
		&"TraitList",
		&"HudInventory",
		&"HudRelicSlots",
	]:
		var control := ItemList.new()
		control.name = control_name
		control.focus_mode = Control.FOCUS_ALL
		screen.add_child(control)
		shared_controls.append(control)
	var ordered: Array = screen.call(&"_ordered_focus_controls")
	for control: Control in shared_controls:
		assert_eq(
			ordered.count(control),
			1,
			"shared HUD controls must join the focus graph exactly once"
		)
	assert_true(screen.open_system_menu())
	for control: Control in shared_controls:
		assert_eq(control.focus_mode, Control.FOCUS_NONE)
	assert_true(screen.close_system_menu())
	for control: Control in shared_controls:
		assert_eq(control.focus_mode, Control.FOCUS_ALL)

	var shell := InRunHudShell.new()
	screen.add_child(shell)
	assert_eq(shell.bind(
		RunPresentationSnapshot.new(),
		&"RUN_MAP",
		Callable(self, "_hud_test_rect"),
		Callable(self, "_hud_test_ui_text"),
		Callable(self, "_hud_test_content_text")
	), &"")
	assert_eq(shell.call(&"_item_name", "opaque_internal_id"), "無")
	var hp := shell.find_child("ExpeditionHpValue", true, false) as Label
	assert_not_null(hp)
	if hp != null:
		assert_true(hp.text.contains("無"))
		assert_false(hp.text.contains("-"))
	await wait_process_frames(2)


func test_open_menu_traps_unlisted_late_added_and_late_enabled_background_focus() -> void:
	var screen := _synthetic_screen(&"RUN_MAP")
	var unlisted := Button.new()
	unlisted.name = "UnlistedBackgroundAction"
	unlisted.focus_mode = Control.FOCUS_ALL
	screen.add_child(unlisted)
	var dormant := Button.new()
	dormant.name = "DormantBackgroundAction"
	dormant.focus_mode = Control.FOCUS_NONE
	screen.add_child(dormant)
	assert_false(
		(screen.call(&"_ordered_focus_controls") as Array).has(unlisted),
		"fixture must prove isolation no longer depends on the open-time allowlist"
	)
	var original_recursive_behavior := screen.focus_behavior_recursive
	assert_true(screen.open_system_menu())
	var overlay := screen.system_menu_overlay()
	assert_not_null(overlay)
	if overlay == null:
		return
	assert_eq(unlisted.focus_mode, Control.FOCUS_NONE)
	assert_eq(
		screen.focus_behavior_recursive,
		Control.FOCUS_BEHAVIOR_DISABLED
	)
	assert_eq(
		overlay.focus_behavior_recursive,
		Control.FOCUS_BEHAVIOR_ENABLED
	)

	var late_added := Button.new()
	late_added.name = "LateAddedBackgroundAction"
	late_added.focus_mode = Control.FOCUS_ALL
	screen.add_child(late_added)
	await wait_process_frames(1)
	assert_eq(
		late_added.focus_mode,
		Control.FOCUS_NONE,
		"tree monitoring must suppress newly-added focusable background controls"
	)

	dormant.focus_mode = Control.FOCUS_ALL
	var focus_next := InputEventAction.new()
	focus_next.action = &"ui_focus_next"
	focus_next.pressed = true
	Input.parse_input_event(focus_next)
	await wait_process_frames(1)
	assert_false(
		dormant.has_focus(),
		"recursive host isolation must block controls enabled after open"
	)
	var focus_owner := get_viewport().gui_get_focus_owner()
	assert_true(
		focus_owner != null and overlay.is_ancestor_of(focus_owner),
		"focus must remain inside the active system-menu surface"
	)

	assert_true(screen.close_system_menu())
	assert_eq(screen.focus_behavior_recursive, original_recursive_behavior)
	assert_eq(unlisted.focus_mode, Control.FOCUS_ALL)
	assert_eq(late_added.focus_mode, Control.FOCUS_ALL)
	assert_eq(
		dormant.focus_mode,
		Control.FOCUS_ALL,
		"a focus mode intentionally enabled while open must survive close"
	)


func _synthetic_screen(
	route: StringName,
	playback_port: LiveScreenPlaybackPort = null
) -> ProductionScreen:
	var host := Control.new()
	host.size = Vector2(1920.0, 1080.0)
	add_child_autofree(host)
	var screen := ProductionScreen.new()
	screen.route_kind = route
	host.add_child(screen)
	var overlay := SystemMenuOverlay.new()
	overlay.name = "SystemMenuOverlay"
	screen.add_child(overlay)
	overlay.configure(_localized())
	overlay.closed.connect(Callable(screen, "_on_system_menu_closed"))
	overlay.return_to_menu_requested.connect(
		Callable(screen, "_on_system_menu_return_to_menu_requested")
	)
	overlay.exit_requested.connect(
		Callable(screen, "_on_system_menu_exit_requested")
	)
	screen.set(&"_system_menu_overlay", overlay)
	screen.set(&"_live_active", true)
	screen.set(&"_live_context", ProductionLiveScreenContext.new(
		route,
		RunPresentationSnapshot.new(),
		null,
		null,
		null,
		null,
		playback_port
	))
	return screen


func _press(overlay: SystemMenuOverlay, action_id: StringName) -> bool:
	for node: Node in overlay.find_children("*", "Button", true, false):
		var button := node as Button
		if button != null and button.has_meta(&"action_id") \
		and StringName(button.get_meta(&"action_id")) == action_id:
			button.pressed.emit()
			return true
	assert_true(false, "missing system-menu action %s" % String(action_id))
	return false


func _system_menu_event() -> InputEventAction:
	var event := InputEventAction.new()
	event.action = &"system_menu"
	event.pressed = true
	return event


func _hud_test_rect(_region: StringName) -> Rect2:
	return Rect2(Vector2.ZERO, Vector2(1920.0, 1080.0))


func _hud_test_ui_text(key: StringName) -> String:
	return "無" if key == &"combat.inspection.none" else String(key)


func _hud_test_content_text(key: StringName) -> String:
	return String(key)


func _localized() -> Dictionary:
	var values: Dictionary = {
		&"screen.run_container.title": "遠征",
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
	for action: StringName in [
		&"map.select", &"map.confirm", &"choice.ack",
		&"prepare.unit", &"prepare.refresh", &"prepare.buy", &"prepare.xp",
		&"prepare.sell", &"prepare.forge", &"prepare.forge.confirm",
		&"prepare.forge.cancel", &"prepare.equip", &"prepare.dismantle",
		&"service.dismantle", &"service.exit", &"prepare.move_board",
		&"prepare.move_bench", &"prepare.start", &"choice.begin",
		&"choice.confirm", &"choice.cancel", &"combat.pause",
		&"combat.inspect", &"combat.speed", &"reward.select", &"reward.confirm",
		&"prepare.panel.shop", &"prepare.resource.gold",
		&"prepare.action_group_selector", &"prepare.group.forge_equipment",
		&"prepare.group.party", &"prepare.group.advance",
	]:
		values[action] = String(action)
	return values
