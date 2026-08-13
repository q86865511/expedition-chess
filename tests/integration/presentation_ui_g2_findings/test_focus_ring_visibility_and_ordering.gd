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
		&"system_menu.open",
	]
	var screen := ProductionSceneCatalog.new().instantiate(&"RUN_PREPARE")
	assert_not_null(screen)
	if screen == null:
		return
	# The 1920 reference rect must exist before bind builds the authored shell;
	# resizing only afterwards preserves stale container allocation from the
	# packed scene's legacy rect and is not the production coordinator path.
	screen.set_anchors_preset(Control.PRESET_TOP_LEFT)
	screen.size = Vector2(1920.0, 1080.0)
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
			screen.system_menu_button(),
			"SystemMenuButton must be the first stable run focus stop"
		)
		assert_true(
			controls.has(group_selector),
			"the page selector must remain in the prepare focus ring"
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


func test_prepare_groups_keep_every_action_reachable_inside_reference_canvas() -> void:
	var action_ids: Array[StringName] = [
		&"prepare.unit", &"prepare.refresh", &"prepare.buy", &"prepare.xp",
		&"prepare.sell", &"prepare.forge", &"prepare.forge.confirm",
		&"prepare.forge.cancel", &"prepare.equip", &"prepare.dismantle",
		&"service.dismantle", &"service.exit", &"prepare.move_board",
		&"prepare.move_bench", &"prepare.start", &"choice.begin",
		&"choice.confirm", &"choice.cancel", &"choice.ack",
		&"system_menu.open",
		&"prepare.group.shop", &"prepare.group.forge_equipment",
		&"prepare.group.party", &"prepare.group.advance",
	]
	var screen := ProductionSceneCatalog.new().instantiate(&"RUN_PREPARE")
	assert_not_null(screen)
	if screen == null:
		return
	screen.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	screen.position = Vector2.ZERO
	screen.size = Vector2(1920.0, 1080.0)
	var snapshot := _prepare_snapshot_with_one_shop_offer()
	_assert_shop_fixture_matches(snapshot)
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
	var runtime := ExpeditionThemeRuntime.new()
	assert_true(runtime.apply(screen, 100))
	screen.apply_theme_scale_layout(100)
	# Theme minima, Container sort, and the prepare page's deferred height sync
	# all settle at frame end in production. Reachability must be measured after
	# those event-driven layout passes, not from a staged pre-sort minimum.
	await wait_process_frames(4)
	var selector := screen.find_child(
		"PrepareActionGroupSelector", true, false
	) as OptionButton
	assert_not_null(selector)
	if selector == null:
		return
	# B1R3 T13：先驗初始狀態——未做任何手動切組前，預設分組頁必須已有
	# 高度且露出可用動作（P1 的可失敗斷言；下方逐組 emit 驗不到這件事）。
	var pages := screen.find_child(
		"PrepareActionGroupPages", true, false
	) as Control
	assert_not_null(pages)
	if pages != null:
		assert_gt(
			pages.get_combined_minimum_size().y,
			0.0,
			"default group page must reserve height before any manual switch"
		)
		var initially_visible := 0
		for node: Node in pages.find_children("*", "Button", true, false):
			var initial_button := node as Control
			if initial_button != null and initial_button.is_visible_in_tree():
				initially_visible += 1
		assert_gt(
			initially_visible,
			0,
			"default group must expose usable actions on load"
		)
	var seen: Dictionary[StringName, bool] = {}
	for group_index: int in selector.item_count:
		selector.select(group_index)
		selector.item_selected.emit(group_index)
		await wait_process_frames(3)
		for node: Node in screen.find_children("*", "Button", true, false):
			var button := node as Button
			if button == null or not button.is_visible_in_tree() \
			or not button.has_meta(&"action_id"):
				continue
			var action_id := StringName(button.get_meta(&"action_id"))
			seen[action_id] = true
			var scroll := _ancestor_scroll_container(button)
			if scroll != null:
				# Use the authored keyboard path: focus_entered defers
				# ensure_control_visible() until Container sorting has settled.
				button.grab_focus()
				await wait_process_frames(3)
				assert_true(button.has_focus(), "%s must accept focus" % action_id)
				assert_true(
					scroll.get_global_rect().grow(1.0).encloses(
						button.get_global_rect()
					),
					"%s must scroll into the action viewport" % action_id
				)
			# clip_text deliberately prevents localized text from widening the
			# fixed column minimum. The post-sort actual rect, not
			# get_combined_minimum_size(), is the player-visible geometry.
			assert_gte(
				button.get_global_rect().size.x,
				_button_text_minimum_width(button),
				"%s actual width must include its visible text" % String(action_id)
			)
	var resident_action_ids: Array[StringName] = [
		&"prepare.unit", &"prepare.refresh", &"prepare.xp", &"prepare.sell",
		&"prepare.forge", &"prepare.forge.confirm", &"prepare.forge.cancel",
		&"prepare.equip", &"prepare.dismantle", &"service.dismantle",
		&"service.exit", &"prepare.move_board", &"prepare.move_bench",
		&"prepare.start", &"choice.begin", &"choice.confirm", &"choice.cancel",
		&"choice.ack",
	]
	for action_id: StringName in resident_action_ids:
		assert_true(seen.has(action_id), "%s must remain reachable" % action_id)

	# Buying is intentionally exact-offer-owned: shop cards must not impersonate
	# the generic prepare.buy action or join its lookup/dispatch path.
	assert_null(
		Support.button(screen, &"prepare.buy"),
		"prepare.buy must not return as a generic resident Button"
	)
	var offer_card: Button
	for node: Node in screen.find_children("ShopCard*", "Button", true, false):
		var candidate := node as Button
		if (
			candidate != null
			and String(candidate.get_meta(&"shop_offer_id", ""))
				== "offer.focus"
		):
			offer_card = candidate
			break
	assert_not_null(offer_card, "an authoritative offer must expose its exact card")
	if offer_card != null:
		assert_false(offer_card.has_meta(&"action_id"))
		assert_true(bool(offer_card.get_meta(&"direct_action_owned", false)))
		assert_eq(String(offer_card.get_meta(&"shop_offer_id")), "offer.focus")
		assert_false(offer_card.disabled)
		assert_eq(offer_card.focus_mode, Control.FOCUS_ALL)
		var focus_controls: Array = screen.call(&"_ordered_focus_controls")
		assert_true(
			focus_controls.has(offer_card),
			"the exact offer card must replace generic prepare.buy in the focus ring"
		)


func _prepare_snapshot_with_one_shop_offer() -> RunPresentationSnapshot:
	var snapshot := RunPresentationSnapshot.new()
	var owner := ReservationOwnerKeyState.create(
		&"run.focus",
		&"node.focus",
		&"shop",
		&"refresh.focus",
		0,
		&"owner.focus"
	)
	var offers: Array[ShopOffer] = [
		ShopOffer.new(
			0,
			"offer.focus",
			&"unit.focus",
			3,
			1,
			owner
		),
	]
	snapshot.economy = EconomyState.new(10, 1, 0, 0, 0, 0, offers)
	var preview := ShopOfferPreviewSnapshot.new()
	preview.offer_id = &"offer.focus"
	preview.slot_index = 0
	preview.unit_def_id = &"unit.focus"
	preview.cost = 3
	preview.cost_tier = 1
	snapshot.shop_offer_previews.append(preview)
	return snapshot


func _assert_shop_fixture_matches(snapshot: RunPresentationSnapshot) -> void:
	assert_not_null(snapshot.economy, "shop fixture requires typed economy")
	if snapshot.economy == null:
		return
	assert_eq(snapshot.economy.shop_offers.size(), 1, "expected one typed offer")
	assert_eq(snapshot.shop_offer_previews.size(), 1, "expected one typed preview")
	if (
		snapshot.economy.shop_offers.size() != 1
		or snapshot.shop_offer_previews.size() != 1
	):
		return
	var offer := snapshot.economy.shop_offers[0]
	var preview := snapshot.shop_offer_previews[0]
	assert_eq(preview.slot_index, offer.slot_index, "shop slot mismatch")
	assert_eq(String(preview.offer_id), offer.offer_id, "shop offer id mismatch")
	assert_eq(preview.unit_def_id, offer.unit_def_id, "shop unit id mismatch")
	assert_eq(preview.cost, offer.cost, "shop cost mismatch")
	assert_true(
		preview.cost_tier >= 1 and preview.cost_tier <= 5,
		"shop cost tier must be in the strict production range"
	)


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
	var style := button.get_theme_stylebox(&"normal")
	if style != null:
		widest_line += (
			style.get_content_margin(SIDE_LEFT)
			+ style.get_content_margin(SIDE_RIGHT)
		)
	return widest_line


func test_prepare_with_node_choice_defaults_to_advance_group() -> void:
	var action_ids: Array[StringName] = [
		&"prepare.unit", &"prepare.refresh", &"prepare.buy", &"prepare.xp",
		&"prepare.sell", &"prepare.forge", &"prepare.forge.confirm",
		&"prepare.forge.cancel", &"prepare.equip", &"prepare.dismantle",
		&"service.dismantle", &"service.exit", &"prepare.move_board",
		&"prepare.move_bench", &"prepare.start", &"choice.begin",
		&"choice.confirm", &"choice.cancel", &"choice.ack",
		&"system_menu.open",
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
