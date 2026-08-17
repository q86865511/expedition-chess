extends GutTest


class FakeSettingsPort:
	extends SettingsApplicationPort

	func apply(candidate: SettingsSnapshot) -> SettingsApplicationResult:
		return SettingsApplicationResult.success(candidate)


var _menu_dispatches: int = 0


func test_settings_uses_shell_without_changing_editor_paths() -> void:
	var screen := ProductionSceneCatalog.new().instantiate(&"SETTINGS")
	assert_not_null(screen)
	if screen == null:
		return
	screen.size = ProductionLayoutShell.REFERENCE_SIZE
	assert_eq(screen.bind(StagedScreenContext.new(
		&"SETTINGS", SettingsSnapshot.new(), null, &"zh_TW", _localized()
	)), &"")
	add_child_autofree(screen)
	assert_true(ExpeditionThemeRuntime.new().apply(screen, 150))
	await wait_process_frames(2)
	var shell := screen.get("_layout_shell") as ProductionLayoutShell
	assert_not_null(shell)
	if shell == null:
		return
	assert_eq(
		shell.current_region_rect(ProductionLayoutShell.REGION_LEFT).size.x,
		0.0
	)
	assert_eq(
		shell.current_region_rect(ProductionLayoutShell.REGION_RIGHT).size.x,
		0.0
	)
	var composition := screen.get_node_or_null(^"Composition") as Control
	var actions := screen.get_node_or_null(^"Actions") as Control
	assert_not_null(composition)
	assert_not_null(actions)
	assert_not_null(screen.get_node_or_null(
		^"Composition/SettingsScroll/SettingEditors/LocaleRow/Locale"
	))
	assert_not_null(screen.find_child("AccessibilityDivider", true, false))
	assert_not_null(screen.find_child("AudioDivider", true, false))
	if composition != null:
		assert_true(shell.current_content_rect(
			ProductionLayoutShell.REGION_CENTER
		).grow(1.0).encloses(composition.get_global_rect()))
		var scroll := composition.get_node_or_null(
			^"SettingsScroll"
		) as ScrollContainer
		assert_not_null(scroll)
		if scroll != null:
			assert_almost_eq(
				scroll.get_rect().end.y,
				composition.size.y,
				1.0,
				"settings scroll must reach the content-panel bottom"
			)
	if actions != null:
		assert_true(shell.current_content_rect(
			ProductionLayoutShell.REGION_BOTTOM
		).grow(1.0).encloses(actions.get_global_rect()))


func test_results_offsets_live_in_metrics_and_values_render_as_cards() -> void:
	for scene_path: String in [
		"res://scenes/production/results.tscn",
		"res://scenes/production/results_fallback.tscn",
	]:
		var source := FileAccess.get_file_as_string(scene_path)
		assert_false(source.contains("offset_left"), scene_path)
		assert_false(source.contains("offset_top"), scene_path)
		assert_false(source.contains("offset_right"), scene_path)
		assert_false(source.contains("offset_bottom"), scene_path)
	var screen := ProductionSceneCatalog.new().instantiate(&"RESULTS")
	assert_not_null(screen)
	if screen == null:
		return
	screen.size = ProductionLayoutShell.REFERENCE_SIZE
	var snapshot := _results_snapshot()
	assert_not_null(snapshot)
	if snapshot == null:
		return
	assert_eq(screen.bind(StagedScreenContext.new(
		&"RESULTS", snapshot, null, &"zh_TW", _localized()
	)), &"")
	var composition := screen.get_node_or_null(
		^"Composition"
	) as ResultsScreenComposition
	assert_not_null(composition)
	if composition == null:
		return
	assert_eq(composition.compose(snapshot, _localized()), &"")
	add_child_autofree(screen)
	assert_true(ExpeditionThemeRuntime.new().apply(screen, 150))
	await wait_process_frames(2)
	var shell := screen.get("_layout_shell") as ProductionLayoutShell
	assert_not_null(shell)
	if shell == null:
		return
	var center := shell.current_content_rect(
		ProductionLayoutShell.REGION_CENTER
	).grow(1.0)
	for value_name: StringName in [
		&"Outcome", &"Reward", &"Profile", &"Receipt", &"Digest",
	]:
		var card := composition.get_node_or_null(
			NodePath("%sCard" % String(value_name))
		) as PanelContainer
		var label := composition.get_node_or_null(
			NodePath("%sValue" % String(value_name))
		) as Label
		assert_not_null(card, String(value_name))
		assert_not_null(label, String(value_name))
		if card != null and label != null:
			assert_true(center.encloses(card.get_global_rect()), String(value_name))
			assert_true(
				card.get_global_rect().encloses(label.get_global_rect()),
				"%s value remains inside its card" % value_name
			)
	for metric_name: StringName in [&"Reward", &"Profile"]:
		var metric_label := composition.get_node_or_null(
			NodePath("%sLabel" % String(metric_name))
		) as Label
		assert_not_null(metric_label, String(metric_name))
		if metric_label != null:
			assert_false(metric_label.text.is_empty())
			assert_true(
				(composition.get_node(
					NodePath("%sCard" % String(metric_name))
				) as Control).get_global_rect().encloses(
					metric_label.get_global_rect()
				)
			)
	var theme := load("res://theme/expedition_theme.tres") as Theme
	var outcome_style := theme.get_stylebox(
		&"panel", &"ExpeditionResultsOutcomeCard"
	)
	assert_true(
		outcome_style is StyleBoxFlat,
		"results outcome banner must not nest the shell's textured frame"
	)
	assert_eq(
		theme.get_font_size(&"font_size", &"ExpeditionResultsAudit"),
		14,
		"receipt and digest stay auxiliary"
	)


func test_results_system_menu_keeps_embedded_settings_and_confirmation() -> void:
	_menu_dispatches = 0
	var snapshot := _results_snapshot()
	var screen := ProductionSceneCatalog.new().instantiate(&"RESULTS")
	assert_not_null(screen)
	if screen == null or snapshot == null:
		return
	screen.size = ProductionLayoutShell.REFERENCE_SIZE
	assert_eq(screen.bind(StagedScreenContext.new(
		&"RESULTS", snapshot, null, &"zh_TW", _localized()
	)), &"")
	assert_eq(screen.bind_system_menu_settings(
		SettingsSnapshot.new(), FakeSettingsPort.new()
	), &"")
	var registry := LiveScreenLeaseRegistry.new()
	var lease := registry.activate(AppStateMachine.State.RESULTS, 1)
	var action_port := ProductionScreenActionPort.new(
		lease,
		registry,
		{&"results.menu": Callable(self, "_record_menu_dispatch")}
	)
	assert_eq(screen.prepare_live_binding(ProductionLiveScreenContext.new(
		&"RESULTS", snapshot, null, action_port
	)), &"")
	add_child_autofree(screen)
	screen.activate_live()
	await wait_process_frames(2)
	var system_menu_button := screen.system_menu_button()
	assert_not_null(system_menu_button)
	if system_menu_button != null:
		assert_eq(system_menu_button.text, "選單")
		assert_eq(
			StringName(system_menu_button.get_meta(&"localization_key", &"")),
			&"system_menu.open"
		)
	assert_true(screen.open_system_menu())
	var overlay := screen.system_menu_overlay()
	assert_not_null(overlay)
	if overlay == null:
		return
	assert_eq(overlay.state_name(), &"ROOT")
	assert_true(_press(overlay, &"system_menu.settings"))
	assert_eq(overlay.state_name(), &"SETTINGS_EMBEDDED")
	var apply := _button(overlay, &"settings.apply")
	assert_not_null(apply)
	if apply != null:
		assert_false(apply.disabled)
	assert_true(overlay.handle_system_menu_action())
	assert_true(_press(overlay, &"run.menu"))
	assert_eq(overlay.state_name(), &"CONFIRM_MENU")
	assert_eq(_menu_dispatches, 0)
	assert_true(_press(overlay, &"run.menu.cancel"))
	assert_eq(overlay.state_name(), &"ROOT")
	assert_eq(_menu_dispatches, 0)
	assert_true(_press(overlay, &"run.menu"))
	assert_true(_press(overlay, &"run.menu.confirm"))
	assert_eq(_menu_dispatches, 1)
	await wait_process_frames(2)


func test_main_world_targets_are_non_drawing_hit_areas() -> void:
	var main: Node = load("res://app/main.tscn").instantiate()
	assert_not_null(main)
	if main == null:
		return
	autofree(main)
	for target_path: NodePath in [
		^"AppRoot/WorldViewportContainer/WorldViewport/ProductionWorld/BoardTileTarget",
		^"AppRoot/WorldViewportContainer/WorldViewport/ProductionWorld/CampHotspotTarget",
	]:
		var target: Node = main.get_node_or_null(target_path)
		assert_not_null(target)
		if target == null:
			continue
		assert_eq(target.get_class(), "Control")
		assert_false(target is ColorRect)
		assert_false(target is TextureRect)


func test_b_out_3_sources_have_no_scattered_theme_overrides() -> void:
	for path: String in [
		"res://presentation/screens/production_screen.gd",
		"res://presentation/screens/production_layout_shell.gd",
		"res://presentation/screens/settings_screen_composition.gd",
		"res://presentation/screens/results_screen_composition.gd",
		"res://presentation/screens/system_menu_overlay.gd",
	]:
		assert_false(
			FileAccess.get_file_as_string(path).contains("theme_override_"),
			path
		)


func _record_menu_dispatch() -> AppActionResult:
	_menu_dispatches += 1
	return AppActionResult.success()


func _results_snapshot() -> ResultsPresentationSnapshot:
	var profile := SaveRootFixture.create_valid_root().profile
	profile.meta_currency = 138
	var run_id: StringName = &"run.b_out_3_visual"
	var key_result := RuntimeKeySchemaRegistry.new().build_settlement_receipt(run_id)
	if not key_result.ok:
		return null
	var receipt := SettlementReceiptState.new(
		key_result.key_state as SettlementReceiptKeyState,
		SettlementReceiptState.Outcome.COMPLETED,
		42,
		"receipt.payload.b_out_3_visual"
	)
	profile.settlement_receipts.append(receipt)
	return ResultsPresentationSnapshot.capture(
		profile, receipt, run_id, "a".repeat(64), true
	)


func _press(overlay: SystemMenuOverlay, action_id: StringName) -> bool:
	var button := _button(overlay, action_id)
	if button == null or button.disabled:
		return false
	button.pressed.emit()
	return true


func _button(overlay: SystemMenuOverlay, action_id: StringName) -> Button:
	for node: Node in overlay.find_children("*", "Button", true, false):
		var button := node as Button
		if (
			button != null
			and button.has_meta(&"action_id")
			and StringName(button.get_meta(&"action_id")) == action_id
		):
			return button
	return null


func _localized() -> Dictionary:
	return {
		&"screen.settings.title": "設定",
		&"screen.results.title": "遠征結算",
		&"screen.run_container.title": "遠征",
		&"system_menu.open": "選單",
		&"menu.continue": "繼續遠征",
		&"menu.settings": "設定",
		&"run.menu": "返回主選單",
		&"menu.exit": "離開",
		&"run.menu.status": "返回主選單？",
		&"run.menu.confirm": "確認返回",
		&"run.menu.cancel": "取消",
		&"menu.exit.status": "確定要離開遊戲？",
		&"menu.exit.confirm": "確認離開",
		&"menu.exit.cancel": "取消",
		&"settings.apply": "套用",
		&"settings.back": "返回",
		&"results.camp": "返回營地",
		&"results.menu": "返回主選單",
		&"results.metric.currency_delta": "本次貨幣獎勵",
		&"results.metric.profile_currency": "目前持有貨幣",
		&"results.outcome.completed": "遠征完成",
	}
