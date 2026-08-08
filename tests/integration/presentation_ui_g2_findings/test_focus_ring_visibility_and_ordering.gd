extends GutTest

## G2 L3：焦點蒐集用 `visible` 而非 `is_visible_in_tree()`，整列 row 隱藏時
## 編輯器仍會進焦點環。
## G2 建議項2：`prepare.start`（開始戰鬥）誤觸代價高，退出焦點環前段。

const Support = preload(
	"res://tests/integration/presentation_ui_g2_findings/"
	+ "g2_findings_test_support.gd"
)


func test_hidden_row_removes_its_editor_from_the_focus_ring() -> void:
	var screen := ProductionSceneCatalog.new().instantiate(&"SETTINGS")
	assert_not_null(screen)
	if screen == null:
		return
	assert_eq(
		screen.bind(
			StagedScreenContext.new(
				&"SETTINGS",
				SettingsSnapshot.new(),
				null,
				&"zh_TW",
				Support.localized([&"settings.apply", &"settings.back"])
			)
		),
		&""
	)
	add_child_autofree(screen)
	await wait_process_frames(2)
	var row := screen.get_node_or_null(
		^"Composition/SettingsScroll/SettingEditors/LocaleRow"
	) as Control
	var editor := screen.get_node_or_null(
		^"Composition/SettingsScroll/SettingEditors/LocaleRow/Locale"
	) as Control
	assert_not_null(row)
	assert_not_null(editor)
	if row == null or editor == null:
		return
	var title := screen.get_node_or_null(^"Label") as Label
	assert_not_null(title)
	if title != null:
		assert_false(
			title.get_global_rect().intersects(row.get_global_rect()),
			"settings title must not overlap the locale row"
		)
	assert_true(
		editor.tooltip_text.is_empty(),
		"hover text must not duplicate the visible row label"
	)

	var before: Array = screen.call(&"_ordered_focus_controls")
	assert_true(before.has(editor), "a visible editor belongs to the focus ring")

	row.visible = false
	var after: Array = screen.call(&"_ordered_focus_controls")
	assert_false(
		after.has(editor),
		"an editor inside a hidden row must leave the focus ring"
	)
	assert_true(
		editor.visible,
		"the editor's own visible flag is still true; only the tree is hidden"
	)


func test_start_combat_is_the_last_action_in_the_prepare_focus_ring() -> void:
	var action_ids: Array[StringName] = [
		&"prepare.unit",
		&"prepare.refresh",
		&"prepare.buy",
		&"prepare.xp",
		&"prepare.sell",
		&"prepare.forge",
		&"prepare.forge.confirm",
		&"prepare.forge.cancel",
		&"prepare.equip",
		&"prepare.dismantle",
		&"prepare.move_board",
		&"prepare.move_bench",
		&"prepare.start",
		&"run.menu",
	]
	var screen := ProductionSceneCatalog.new().instantiate(&"RUN_PREPARE")
	assert_not_null(screen)
	if screen == null:
		return
	assert_eq(
		screen.bind(
			StagedScreenContext.new(
				&"RUN_PREPARE",
				RunPresentationSnapshot.new(),
				null,
				&"zh_TW",
				Support.localized(action_ids)
			)
		),
		&""
	)
	add_child_autofree(screen)
	var group_selector := screen.find_child(
		"PrepareActionGroupSelector", true, false
	) as OptionButton
	assert_not_null(
		group_selector,
		"RUN_PREPARE must expose a localized action-group selector"
	)
	if group_selector == null:
		return
	assert_eq(group_selector.item_count, 3)
	var controls: Array = screen.call(&"_ordered_focus_controls")
	assert_false(controls.is_empty())
	if not controls.is_empty():
		assert_eq(
			controls[0],
			group_selector,
			"the page selector must be the first prepare focus stop"
		)

	var order := Support.focus_action_order(screen)
	assert_false(order.is_empty())
	if order.is_empty():
		return
	assert_true(
		order.has(&"prepare.start"),
		"the action must stay reachable by keyboard"
	)
	assert_eq(
		order[order.size() - 1],
		&"prepare.start",
		"start combat must not sit at the front of the tab ring"
	)
	assert_true(
		order.find(&"prepare.start") > order.find(&"prepare.buy"),
		"every shop action comes before start combat"
	)


func test_prepare_groups_keep_every_action_reachable_inside_720p() -> void:
	var action_ids: Array[StringName] = [
		&"prepare.unit", &"prepare.refresh", &"prepare.buy", &"prepare.xp",
		&"prepare.sell", &"prepare.forge", &"prepare.forge.confirm",
		&"prepare.forge.cancel", &"prepare.equip", &"prepare.dismantle",
		&"service.dismantle", &"service.exit", &"prepare.move_board",
		&"prepare.move_bench", &"prepare.start", &"choice.begin",
		&"choice.confirm", &"choice.cancel", &"choice.ack", &"run.menu",
		&"prepare.group.shop", &"prepare.group.forge_equipment",
		&"prepare.group.party", &"prepare.group.advance",
	]
	var screen := ProductionSceneCatalog.new().instantiate(&"RUN_PREPARE")
	assert_not_null(screen)
	if screen == null:
		return
	assert_eq(
		screen.bind(StagedScreenContext.new(
			&"RUN_PREPARE",
			RunPresentationSnapshot.new(),
			null,
			&"zh_TW",
			Support.localized(action_ids)
		)),
		&""
	)
	screen.set_anchors_preset(Control.PRESET_TOP_LEFT)
	screen.size = Vector2(1280.0, 720.0)
	add_child_autofree(screen)
	await wait_process_frames(2)
	var selector := screen.find_child(
		"PrepareActionGroupSelector", true, false
	) as OptionButton
	assert_not_null(selector)
	if selector == null:
		return
	var seen: Dictionary[StringName, bool] = {}
	for group_index: int in selector.item_count:
		selector.select(group_index)
		selector.item_selected.emit(group_index)
		await wait_process_frames(1)
		for node: Node in screen.find_children("*", "Button", true, false):
			var button := node as Button
			if button == null or not button.is_visible_in_tree() \
			or not button.has_meta(&"action_id"):
				continue
			var action_id := StringName(button.get_meta(&"action_id"))
			seen[action_id] = true
			var scroll := _ancestor_scroll_container(button)
			if scroll != null:
				scroll.ensure_control_visible(button)
				await wait_process_frames(1)
			var rect := button.get_global_rect()
			assert_true(
				Rect2(Vector2.ZERO, Vector2(1280.0, 720.0)).encloses(rect),
				"%s button itself must stay inside 1280x720; rect=%s" % [String(action_id), rect]
			)
			assert_gte(
				button.get_combined_minimum_size().x,
				_button_text_minimum_width(button),
				"%s width must include its complete text" % String(action_id)
			)
	for action_id: StringName in action_ids.slice(0, 20):
		assert_true(seen.has(action_id), "%s must remain reachable" % action_id)


func _ancestor_scroll_container(control: Control) -> ScrollContainer:
	var ancestor := control.get_parent()
	while ancestor != null:
		if ancestor is ScrollContainer:
			return ancestor as ScrollContainer
		ancestor = ancestor.get_parent()
	return null


func _button_text_minimum_width(button: Button) -> float:
	if button == null or button.text.is_empty():
		return 0.0
	var font := button.get_theme_font(&"font")
	var font_size := button.get_theme_font_size(&"font_size")
	var widest_line := 0.0
	for line: String in button.text.split("\n"):
		widest_line = maxf(
			widest_line,
			font.get_string_size(
				line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size
			).x
		)
	return widest_line


func test_prepare_with_node_choice_defaults_to_advance_group() -> void:
	var action_ids: Array[StringName] = [
		&"prepare.unit", &"prepare.refresh", &"prepare.buy", &"prepare.xp",
		&"prepare.sell", &"prepare.forge", &"prepare.forge.confirm",
		&"prepare.forge.cancel", &"prepare.equip", &"prepare.dismantle",
		&"service.dismantle", &"service.exit", &"prepare.move_board",
		&"prepare.move_bench", &"prepare.start", &"choice.begin",
		&"choice.confirm", &"choice.cancel", &"choice.ack", &"run.menu",
		&"prepare.group.shop", &"prepare.group.forge_equipment",
		&"prepare.group.party", &"prepare.group.advance",
	]
	var snapshot := RunPresentationSnapshot.new()
	snapshot.node_choice_overlay = NodeChoiceOverlaySnapshot.new()
	var screen := ProductionSceneCatalog.new().instantiate(&"RUN_PREPARE")
	assert_not_null(screen)
	if screen == null:
		return
	assert_eq(
		screen.bind(StagedScreenContext.new(
			&"RUN_PREPARE",
			snapshot,
			null,
			&"zh_TW",
			Support.localized(action_ids)
		)),
		&""
	)
	add_child_autofree(screen)
	var selector := screen.find_child(
		"PrepareActionGroupSelector", true, false
	) as OptionButton
	assert_not_null(selector)
	if selector == null:
		return
	assert_eq(selector.selected, 2)
	var advance_page := screen.find_child(
		"GroupAdvance", true, false
	) as GridContainer
	assert_not_null(advance_page)
	if advance_page != null:
		assert_true(advance_page.visible)


func test_global_focus_indicator_tracks_button_focus() -> void:
	var screen := ProductionSceneCatalog.new().instantiate(&"MENU_MAIN")
	assert_not_null(screen)
	if screen == null:
		return
	assert_eq(
		screen.bind(StagedScreenContext.new(
			&"MENU_MAIN",
			MainMenuSnapshot.new(),
			null,
			&"zh_TW",
			Support.localized([&"menu.settings", &"menu.exit"])
		)),
		&""
	)
	add_child_autofree(screen)
	await wait_process_frames(1)
	var button := Support.button(screen, &"menu.settings")
	var indicator := screen.get_node_or_null(^"FocusIndicator") as Control
	assert_not_null(button)
	assert_not_null(indicator, "every production screen requires a focus outline")
	if button == null or indicator == null:
		return
	button.grab_focus()
	await wait_process_frames(1)
	assert_true(indicator.visible)
	assert_gt(indicator.size.x, button.size.x)
	assert_gt(indicator.size.y, button.size.y)
