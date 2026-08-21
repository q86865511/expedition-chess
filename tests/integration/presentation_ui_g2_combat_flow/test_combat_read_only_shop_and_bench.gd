extends GutTest

const Support = preload(
	"res://tests/integration/presentation_ui_r15_behavior/"
	+ "r15_behavior_test_support.gd"
)
const REFERENCE_SIZE := Vector2(1920.0, 1080.0)
const VIEWPORT_SIZES: Array[Vector2i] = [
	Vector2i(1280, 720),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440),
]
const UI_SCALES: Array[int] = [100, 125, 150]
const COMBAT_WORLD_ID: StringName = &"combat.t23"
const COMBAT_WORLD_CELL := Vector2i(2, 1)


func test_combat_keeps_shop_and_bench_as_read_only_snapshot_surfaces() -> void:
	var session := Support.SpyTypedSession.new()
	var source_snapshot := _combat_snapshot()
	session.current_snapshot = source_snapshot.deep_clone()
	var playback := Support.FunctionalSupport.playback_fixture(self)
	var registry := LiveScreenLeaseRegistry.new()
	var lease := registry.activate(AppStateMachine.State.RUN, 2301)
	var screen := ProductionSceneCatalog.new().instantiate(&"RUN_COMBAT")
	assert_not_null(screen)
	if screen == null:
		return
	assert_eq(screen.bind(StagedScreenContext.new(
		&"RUN_COMBAT",
		source_snapshot,
		null,
		&"zh_TW",
		_localized_text()
	)), &"")
	var live := ProductionLiveScreenContext.new(
		&"RUN_COMBAT",
		session.snapshot(),
		null,
		ProductionScreenActionPort.new(lease, registry, {}),
		LiveScreenNavigationPort.new(),
		LiveScreenIntentPort.new(lease, registry, session),
		playback.get("port") as LiveScreenPlaybackPort
	)
	assert_eq(screen.prepare_live_binding(live), &"")
	var combat := screen.get_node_or_null(^"Composition") as RunCombatScreen
	assert_not_null(combat)
	if combat == null:
		return
	# This is a geometry lifecycle test, not a playback/settlement test. Disable
	# the whole composition process mode before attachment so the production
	# 750ms presentation clock cannot settle the battle and become a competing
	# asynchronous writer of the parent screen's status band while the matrix
	# deliberately waits many SceneTree frames.
	combat.process_mode = Node.PROCESS_MODE_DISABLED
	var viewport_fixture := _production_viewport_fixture()
	var presentation_host := viewport_fixture["presentation_host"] as Control
	var coordinator := viewport_fixture["coordinator"] as ProductionViewportCoordinator
	var surface := viewport_fixture["surface"] as ProductionWorldSurface
	assert_not_null(presentation_host)
	assert_not_null(coordinator)
	assert_not_null(surface)
	await get_tree().process_frame
	assert_false(screen.is_inside_tree())
	assert_false(
		bool(combat.get("_world_board_mount_scheduled")),
		"the detached compose deferred call must be consumed before attachment"
	)
	assert_eq(coordinator.synchronize(VIEWPORT_SIZES[0]), &"")
	presentation_host.add_child(screen)
	screen.activate_live()
	await wait_process_frames(3)
	assert_false(
		combat.can_process(),
		"the geometry fixture must keep combat playback/settlement disabled"
	)
	assert_false(bool(combat.get("_world_board_mount_scheduled")))
	assert_eq(combat.world_board_mount_error(), &"")
	assert_not_null(surface.ui_overlay())
	await _assert_combat_geometry_matrix(
		screen, coordinator, surface, presentation_host
	)

	var shop_cards := _read_only_buttons(screen, &"combat_shop_slot")
	var bench_slots := _read_only_buttons(screen, &"combat_bench_slot")
	assert_eq(shop_cards.size(), 5, "COMBAT must retain all five shop slots")
	assert_eq(bench_slots.size(), 9, "COMBAT must retain all nine bench slots")
	_assert_slot_order(shop_cards, &"shop_slot_index", 5)
	_assert_slot_order(bench_slots, &"bench_slot", 9)
	for bench_slot: Button in bench_slots:
		if String(bench_slot.get_meta(&"unit_instance_id", "")).is_empty():
			assert_eq(bench_slot.text, "◇")
			assert_almost_eq(
				bench_slot.self_modulate.a,
				ExpeditionLayoutMetrics.BENCH_EMPTY_ALPHA,
				0.001
			)
			assert_ne(bench_slot.text, "無")
	if shop_cards.size() == 5:
		var active_card := shop_cards[1]
		_assert_shop_semantic_cues(
			active_card, "費用", "單位", "星級", true
		)
		screen.relocalize(&"en", _localized_text_en())
		_assert_shop_semantic_cues(
			active_card, "Cost", "Units", "Star", true
		)
		active_card.set_meta(&"shop_star_up_after_purchase", false)
		screen.call(&"_refresh_shop_card_localization", active_card)
		_assert_shop_semantic_cues(
			active_card, "Cost", "Units", "Star", false
		)
		screen.relocalize(&"zh_TW", _localized_text())
		_assert_shop_semantic_cues(
			active_card, "費用", "單位", "星級", false
		)

	var dispatches_before := session.dispatch_count
	for control: Button in shop_cards + bench_slots:
		assert_true(control.disabled)
		assert_eq(control.focus_mode, Control.FOCUS_NONE)
		assert_false(control.has_meta(&"action_id"))
		assert_true(control.has_meta(&"accessible_text"))
		assert_false(String(control.get_meta(&"accessible_text")).is_empty())
		assert_true(
			control.pressed.get_connections().is_empty(),
			"read-only snapshot controls must not own dispatch handlers"
		)
		control.pressed.emit()
	assert_eq(
		session.dispatch_count,
		dispatches_before,
		"shop/bench probes must never dispatch gameplay intent"
	)

	# Mutating the caller's DTO after bind cannot alter the retained projection.
	source_snapshot.economy.shop_offers.clear()
	source_snapshot.roster.bench_unit_instance_ids.clear()
	if shop_cards.size() == 5 and bench_slots.size() == 9:
		assert_eq(String(shop_cards[1].get_meta(&"shop_offer_id")), "offer.t23")
		assert_eq(
			String(bench_slots[0].get_meta(&"unit_instance_id")),
			"bench.t23"
		)

	var focus_ring: Array = screen.call(&"_ordered_focus_controls")
	var geometry_controls: Array[Control] = []
	geometry_controls.assign(shop_cards)
	geometry_controls.append_array(bench_slots)
	for action_id: StringName in [
		&"combat.pause", &"combat.inspect", &"combat.speed",
	]:
		var action := Support.action_button(screen, action_id)
		assert_not_null(action)
		if action == null:
			continue
		assert_false(action.disabled)
		assert_eq(action.focus_mode, Control.FOCUS_ALL)
		assert_true(focus_ring.has(action))
		geometry_controls.append(action)
	_assert_controls_inside_bottom(screen, geometry_controls, "final ui150")


func test_combat_layout_source_has_no_runtime_absolute_assignments() -> void:
	var combat_source := FileAccess.get_file_as_string(
		"res://presentation/screens/run_combat_screen.gd"
	)
	assert_false(combat_source.is_empty())
	for assignment: String in [
		".position =", ".size =", ".offset_left =", ".offset_top =",
		".offset_right =", ".offset_bottom =",
	]:
		assert_false(
			combat_source.contains(assignment),
			"RUN_COMBAT composition must not own absolute geometry: %s" % assignment
		)
	var production_source := FileAccess.get_file_as_string(
		"res://presentation/screens/production_screen.gd"
	)
	var combat_branch := _source_between(
		production_source,
		"elif route_kind == &\"RUN_COMBAT\"",
		"elif route_kind in RUN_ROUTES"
	)
	var combat_builder := _source_between(
		production_source,
		"func _build_combat_snapshot_controls(",
		"func _combat_bench_unit_text("
	)
	var shop_content := _source_between(
		production_source,
		"func _add_shop_card_content(",
		"func _on_prepare_shop_card_pressed("
	)
	for section: String in [combat_branch, combat_builder, shop_content]:
		assert_false(section.is_empty())
		for assignment: String in [
			".position =", ".size =", ".offset_left =", ".offset_top =",
			".offset_right =", ".offset_bottom =",
		]:
			assert_false(
				section.contains(assignment),
				"combat shop/bench/action layout must be Container-owned: %s"
				% assignment
			)
	assert_true(
		combat_branch.contains(
			"bottom_content.add_child(controls)"
		),
		"combat Actions must mount into the shared bottom region Content"
	)


func _assert_shop_semantic_cues(
	card: Button,
	cost_title: String,
	owned_title: String,
	star_title: String,
	star_up: bool
) -> void:
	var price := card.get_node(
		"CardContent/IdentityRow/IdentityText/PriceTier"
	) as Label
	assert_eq(price.text, "%s 4" % cost_title)
	assert_false(price.text.contains("%s 3" % cost_title))
	assert_eq(String(price.get_meta(&"accessible_text")), price.text)
	var tier_cue := price.get_node(^"TierCueShapes") as HBoxContainer
	assert_eq(tier_cue.get_child_count(), 3)
	assert_eq(int(tier_cue.get_meta(&"authoritative_cost_tier")), 3)
	assert_eq(tier_cue.get_meta(&"non_color_cue"), &"tier-pips")

	var ownership := card.get_node(
		"CardContent/OwnedAndStarUp"
	) as Label
	var expected := "%s 1" % owned_title
	if star_up:
		expected += " · %s" % star_title
	assert_eq(ownership.text, expected)
	var accessible := String(ownership.get_meta(&"accessible_text"))
	assert_eq(accessible, expected)
	assert_false(accessible.contains("%s 0" % star_title))
	assert_false(accessible.contains("%s 1" % star_title))
	var star_cue := ownership.get_node(^"StarUpCueShape") as HBoxContainer
	assert_eq(
		bool(star_cue.get_meta(&"star_up_after_purchase_value")),
		star_up
	)
	assert_eq(
		star_cue.get_meta(&"non_color_cue"),
		&"star-rise" if star_up else &"star-flat"
	)
	assert_eq(star_cue.get_child_count(), 2 if star_up else 1)
	assert_true(card.tooltip_text.contains("%s 4" % cost_title))
	assert_eq(card.tooltip_text.contains(star_title), star_up)


func _read_only_buttons(
	screen: ProductionScreen,
	typed_data_kind: StringName
) -> Array[Button]:
	var result: Array[Button] = []
	for node: Node in screen.find_children("*", "Button", true, false):
		var button := node as Button
		if button != null and StringName(
			button.get_meta(&"typed_data_kind", &"")
		) == typed_data_kind:
			result.append(button)
	result.sort_custom(func(left: Button, right: Button) -> bool:
		return left.name.naturalnocasecmp_to(right.name) < 0
	)
	return result


func _assert_slot_order(
	controls: Array[Button],
	metadata_key: StringName,
	expected_count: int
) -> void:
	if controls.size() != expected_count:
		return
	for index: int in expected_count:
		assert_eq(int(controls[index].get_meta(metadata_key, -1)), index)


func _assert_combat_geometry_matrix(
	screen: ProductionScreen,
	coordinator: ProductionViewportCoordinator,
	surface: ProductionWorldSurface,
	presentation_host: Control
) -> void:
	var screen_instance_id := screen.get_instance_id()
	var surface_instance_id := surface.get_instance_id()
	var overlay := surface.ui_overlay()
	assert_not_null(overlay)
	if overlay == null:
		return
	var overlay_instance_id := overlay.get_instance_id()
	var ui_policy := coordinator.get("_ui_policy") as UiScaleRoot
	assert_not_null(ui_policy)
	if ui_policy == null:
		return
	var ui_policy_instance_id := ui_policy.get_instance_id()
	for scale_percent: int in UI_SCALES:
		assert_true(
			ExpeditionThemeRuntime.new().apply(screen, scale_percent),
			"theme application must succeed at ui%d" % scale_percent
		)
		assert_eq(coordinator.apply_ui_scale(scale_percent), &"")
		await wait_process_frames(2)

		# Mount errors may have opened the status band during the initial deferred
		# compose. Clear it through the typed result path, then exercise both shell
		# states so host refresh remains event-driven and observable.
		screen.report_composition_result(AppActionResult.success(false))
		await wait_process_frames(2)
		assert_true(screen.status_message_text().is_empty())
		await _assert_combat_geometry_for_resize_sequence(
			screen,
			coordinator,
			surface,
			presentation_host,
			scale_percent,
			false,
			screen_instance_id,
			surface_instance_id,
			overlay_instance_id,
			ui_policy_instance_id
		)
		var shell := screen.get("_layout_shell") as ProductionLayoutShell
		assert_not_null(shell)
		if shell == null:
			return
		assert_false(
			shell.is_status_visible(),
			"the hidden resize sequence must preserve hidden status at ui%d"
			% scale_percent
		)
		# Capture after the resize sequence has allowed Container minimum sizes to
		# settle. Comparing a pre-resize measurement to a post-resize measurement
		# would mix two lifecycle states instead of testing the status contract.
		var hidden_center_height := screen.layout_region_content_rect(
			ProductionLayoutShell.REGION_CENTER
		).size.y
		var hidden_bottom_height := shell.current_region_rect(
			ProductionLayoutShell.REGION_BOTTOM
		).size.y

		screen.report_composition_result(AppActionResult.failure(
			DiagnosticError.new(
				&"RENDER_FAILED", &"error.presentation.render_failed"
			)
		))
		assert_eq(
			StringName(screen.status_report().get("source_code", &"")),
			&"RENDER_FAILED",
			"the injected typed failure must own the status before awaiting ui%d"
			% scale_percent
		)
		assert_true(
			shell.is_status_visible(),
			"report_composition_result must synchronously open status at ui%d"
			% scale_percent
		)
		await wait_process_frames(2)
		assert_false(
			screen.status_message_text().is_empty(),
			"the injected status must survive deferred layout settle at ui%d"
			% scale_percent
		)
		assert_eq(
			StringName(screen.status_report().get("source_code", &"")),
			&"RENDER_FAILED",
			"no asynchronous combat result may replace the geometry probe at ui%d"
			% scale_percent
		)
		assert_true(
			shell.is_status_visible(),
			"deferred layout settle must preserve visible status at ui%d"
			% scale_percent
		)
		var expected_visible_height := (
			hidden_center_height
			+ hidden_bottom_height
			- (
				ProductionLayoutShell.BOARD_ROUTE_BOTTOM_HEIGHT_CAP
				- ProductionLayoutShell.STATUS_GUTTER
			)
		)
		assert_almost_eq(
			screen.layout_region_content_rect(
				ProductionLayoutShell.REGION_CENTER
			).size.y,
			expected_visible_height,
			0.5,
			"visible status band must use the formal shell geometry at ui%d"
			% scale_percent
		)
		await _assert_combat_geometry_for_resize_sequence(
			screen,
			coordinator,
			surface,
			presentation_host,
			scale_percent,
			true,
			screen_instance_id,
			surface_instance_id,
			overlay_instance_id,
			ui_policy_instance_id
		)

	# Leave the existing behavioral assertions at the historically strongest
	# 150% case, without retaining an error banner as unrelated test state.
	screen.report_composition_result(AppActionResult.success(false))
	await wait_process_frames(2)


func _assert_combat_geometry_for_resize_sequence(
	screen: ProductionScreen,
	coordinator: ProductionViewportCoordinator,
	surface: ProductionWorldSurface,
	presentation_host: Control,
	scale_percent: int,
	status_visible: bool,
	screen_instance_id: int,
	surface_instance_id: int,
	overlay_instance_id: int,
	ui_policy_instance_id: int
) -> void:
	var context := "ui%d/status_%s" % [scale_percent, status_visible]
	var previous_world_foot := Vector2.INF
	for viewport_size: Vector2i in VIEWPORT_SIZES:
		assert_eq(coordinator.synchronize(viewport_size), &"")
		await wait_process_frames(2)
		_assert_mounted_combat_geometry(
			screen,
			coordinator,
			surface,
			presentation_host,
			viewport_size,
			scale_percent,
			status_visible,
			context,
			screen_instance_id,
			surface_instance_id,
			overlay_instance_id,
			ui_policy_instance_id
		)
		await _assert_combat_bottom_scroll_reachability(
			screen, context + "/viewport_%dx%d" % [
				viewport_size.x, viewport_size.y,
			]
		)
		var mapper := coordinator.coordinate_mapper_clone()
		var current_world_foot := mapper.world_to_screen(
			BoardProjection.new().project_cell(COMBAT_WORLD_CELL)
		).round()
		if previous_world_foot != Vector2.INF:
			assert_ne(
				current_world_foot,
				previous_world_foot,
				"%s world mapper must refresh after resize to %s"
				% [context, viewport_size]
			)
		previous_world_foot = current_world_foot


func _assert_mounted_combat_geometry(
	screen: ProductionScreen,
	coordinator: ProductionViewportCoordinator,
	surface: ProductionWorldSurface,
	presentation_host: Control,
	viewport_size: Vector2i,
	scale_percent: int,
	status_visible: bool,
	context: String,
	screen_instance_id: int,
	surface_instance_id: int,
	overlay_instance_id: int,
	ui_policy_instance_id: int
) -> void:
	var device_context := "%s/viewport_%dx%d" % [
		context, viewport_size.x, viewport_size.y,
	]
	assert_eq(screen.get_instance_id(), screen_instance_id)
	assert_eq(surface.get_instance_id(), surface_instance_id)
	assert_eq(screen.get_parent(), presentation_host)
	assert_eq(coordinator.window_size(), viewport_size)
	assert_eq(int(coordinator.get_meta(&"ui_scale_percent", 0)), scale_percent)

	var ui_policy := coordinator.get("_ui_policy") as UiScaleRoot
	assert_not_null(ui_policy)
	if ui_policy == null:
		return
	assert_eq(ui_policy.get_instance_id(), ui_policy_instance_id)
	assert_eq(ui_policy.ui_scale_percent(), scale_percent)
	var mapper := coordinator.coordinate_mapper_clone()
	assert_not_null(mapper)
	if mapper == null:
		return
	assert_eq(mapper.ui_scale_percent(), scale_percent)
	var window_rect := Rect2(Vector2.ZERO, Vector2(viewport_size))
	var mapped_reference := _map_ui_rect(
		mapper, Rect2(Vector2.ZERO, REFERENCE_SIZE)
	)
	_assert_rect_close(
		mapped_reference, ui_policy.screen_rect(), device_context + "/ui-policy"
	)
	_assert_rect_close(
		_canvas_rect(presentation_host),
		mapped_reference,
		device_context + "/PresentationHost"
	)
	assert_true(
		window_rect.grow(0.5).encloses(_canvas_rect(presentation_host)),
		device_context + " presentation host must fit the mounted viewport"
	)

	var world_container := coordinator.get_node_or_null(
		coordinator.world_container_path
	) as SubViewportContainer
	assert_not_null(world_container)
	if world_container != null:
		var expected_world_rect: Rect2 = coordinator.get_meta(&"world_rect")
		_assert_rect_close(
			world_container.get_global_rect(),
			expected_world_rect,
			device_context + "/WorldViewportContainer"
		)
		assert_true(
			window_rect.grow(0.5).encloses(world_container.get_global_rect()),
			device_context + " world viewport must fit the mounted viewport"
		)

	var overlay := surface.ui_overlay()
	assert_not_null(overlay)
	if overlay == null:
		return
	assert_eq(overlay.get_instance_id(), overlay_instance_id)
	var surface_mapper := overlay.get("_coordinate_mapper") as WindowCoordinateMapper
	assert_not_null(surface_mapper)
	if surface_mapper != null:
		assert_eq(
			surface_mapper.ui_scale_percent(),
			scale_percent,
			device_context + " world surface must receive the current UI-scale mapper"
		)
		assert_eq(
			surface_mapper.world_to_screen(
				BoardProjection.new().project_cell(COMBAT_WORLD_CELL)
			).round(),
			mapper.world_to_screen(
				BoardProjection.new().project_cell(COMBAT_WORLD_CELL)
			).round(),
			device_context + " world surface mapper must not retain a stale resize"
		)
	var placement := overlay.placement_for(COMBAT_WORLD_ID)
	assert_not_null(placement)
	if placement != null:
		assert_eq(
			placement.screen_foot_position,
			mapper.world_to_screen(
				BoardProjection.new().project_cell(COMBAT_WORLD_CELL)
			).round(),
			device_context + " combat overlay must re-project with the live mapper"
		)

	var bottom := screen.layout_region_content_rect(
		ProductionLayoutShell.REGION_BOTTOM
	)
	var mapped_bottom := _map_ui_rect(mapper, bottom)
	assert_true(
		window_rect.grow(0.5).encloses(mapped_bottom),
		device_context + " bottom region must fit the mounted viewport"
	)
	var shell := screen.get("_layout_shell") as ProductionLayoutShell
	assert_not_null(shell)
	if shell == null:
		return
	var actions := screen.find_child("Actions", true, false) as Control
	assert_not_null(actions)
	if actions == null:
		return
	assert_eq(
		actions.get_parent(),
		screen.layout_content(ProductionLayoutShell.REGION_BOTTOM),
		"combat Actions must remain a child of the shared bottom Content"
	)
	var bottom_scroll := screen.find_child(
		"BottomContentScroll", true, false
	) as ScrollContainer
	assert_not_null(bottom_scroll)
	if bottom_scroll == null:
		return
	assert_true(bottom_scroll.clip_contents)
	assert_true(bottom_scroll.follow_focus)
	assert_eq(
		bottom_scroll.horizontal_scroll_mode,
		ScrollContainer.SCROLL_MODE_DISABLED
	)
	assert_eq(
		bottom_scroll.vertical_scroll_mode,
		ScrollContainer.SCROLL_MODE_AUTO
	)
	var bottom_scroll_rect := bottom_scroll.get_global_rect()
	var bottom_region := shell.current_region_rect(
		ProductionLayoutShell.REGION_BOTTOM
	)
	assert_true(
		bottom_region.grow(1.0).encloses(bottom_scroll_rect),
		device_context + " bottom viewport must remain inside its panel region"
	)
	var actions_rect := actions.get_global_rect()
	var bottom_content_rect := screen.layout_content(
		ProductionLayoutShell.REGION_BOTTOM
	).get_global_rect()
	_assert_rect_close(
		actions_rect,
		bottom_content_rect,
		device_context + "/Actions-scroll-content"
	)
	assert_true(
		actions_rect.size.y + 0.5 >= bottom_scroll_rect.size.y,
		device_context + " Actions must fill or overflow only through the scroll host"
	)
	if actions_rect.size.y > bottom_scroll_rect.size.y + 0.5:
		var vertical_bar := bottom_scroll.get_v_scroll_bar()
		assert_true(
			vertical_bar.max_value - vertical_bar.page > 0.5,
			device_context + " overflowing combat rows must remain scroll-reachable"
		)
	else:
		assert_almost_eq(
			actions_rect.size.y, bottom_scroll_rect.size.y, 0.5,
			device_context + "/Actions-reference/height"
		)

	var combat := screen.get_node_or_null(^"Composition") as RunCombatScreen
	var hud := (
		combat.find_child("InRunHudShell", true, false) as InRunHudShell
		if combat != null
		else null
	)
	assert_not_null(hud)
	if hud != null:
		for region: StringName in [
			ProductionLayoutShell.REGION_TOP,
			ProductionLayoutShell.REGION_LEFT,
			ProductionLayoutShell.REGION_CENTER,
			ProductionLayoutShell.REGION_RIGHT,
			ProductionLayoutShell.REGION_BOTTOM,
			ProductionLayoutShell.REGION_OVERLAY,
		]:
			var region_host := hud.host(region)
			assert_not_null(region_host)
			if region_host == null:
				continue
			var expected_reference := screen.layout_region_content_rect(region)
			_assert_rect_close(
				region_host.get_global_rect(),
				expected_reference,
				device_context + "/" + String(region) + "-reference"
			)
			_assert_mounted_control_inside(
				region_host,
				expected_reference,
				mapper,
				window_rect,
				device_context + "/" + String(region)
			)
		var left := hud.host(ProductionLayoutShell.REGION_LEFT)
		var right := hud.host(ProductionLayoutShell.REGION_RIGHT)
		if left != null:
			assert_false(left.get_global_rect().intersects(bottom))
		if right != null:
			assert_false(right.get_global_rect().intersects(bottom))

	var status := screen.status_message_control()
	assert_not_null(status)
	assert_eq(
		shell.is_status_visible(),
		status_visible,
		device_context + " shell status state must survive mounted resize"
	)
	if status != null and status_visible:
		assert_true(
			status.is_visible_in_tree(),
			device_context + " status label must remain visible in the mounted tree"
		)

	var controls: Array[Control] = []
	controls.assign(_read_only_buttons(screen, &"combat_shop_slot"))
	controls.append_array(_read_only_buttons(screen, &"combat_bench_slot"))
	for action_id: StringName in [
		&"combat.pause", &"combat.inspect", &"combat.speed",
	]:
		var action := Support.action_button(screen, action_id)
		assert_not_null(action)
		if action != null:
			assert_true(
				action.visible,
				device_context + " action must remain locally visible: "
				+ String(action_id)
			)
			controls.append(action)
	if actions_rect.size.y <= bottom_scroll_rect.size.y + 0.5:
		_assert_controls_inside_bottom(screen, controls, device_context)
		for control: Control in controls:
			_assert_mounted_control_inside(
				control,
				bottom,
				mapper,
				window_rect,
				device_context + "/" + control.name
			)
	else:
		_assert_controls_inside_scroll_content(
			controls, actions_rect, bottom_scroll_rect, mapper, device_context
		)


func _assert_mounted_control_inside(
	control: Control,
	reference_outer: Rect2,
	mapper: WindowCoordinateMapper,
	window_rect: Rect2,
	context: String
) -> void:
	var actual := _canvas_rect(control)
	var expected := _map_ui_rect(mapper, control.get_global_rect())
	_assert_rect_close(actual, expected, context + "/canvas-transform")
	assert_true(
		_map_ui_rect(mapper, reference_outer).grow(0.5).encloses(actual),
		context + " must fit its mounted production region"
	)
	assert_true(
		window_rect.grow(0.5).encloses(actual),
		context + " must fit the mounted viewport"
	)


func _assert_controls_inside_bottom(
	screen: ProductionScreen,
	controls: Array[Control],
	context: String
) -> void:
	var bottom := screen.layout_region_content_rect(
		ProductionLayoutShell.REGION_BOTTOM
	)
	for control: Control in controls:
		var rect := control.get_global_rect()
		assert_true(
			bottom.grow(0.5).encloses(rect),
			"%s control %s exceeds bottom rect: %s vs %s" % [
				context, control.name, rect, bottom,
			]
		)


func _assert_controls_inside_scroll_content(
	controls: Array[Control],
	content_rect: Rect2,
	viewport_rect: Rect2,
	mapper: WindowCoordinateMapper,
	context: String
) -> void:
	var mapped_content := _map_ui_rect(mapper, content_rect)
	var mapped_viewport := _map_ui_rect(mapper, viewport_rect)
	for control: Control in controls:
		var reference_rect := control.get_global_rect()
		assert_true(
			content_rect.grow(0.5).encloses(reference_rect),
			"%s control %s must remain inside scroll content: %s vs %s" % [
				context, control.name, reference_rect, content_rect,
			]
		)
		var actual := _canvas_rect(control)
		_assert_rect_close(
			actual,
			_map_ui_rect(mapper, reference_rect),
			context + "/" + control.name + "/canvas-transform"
		)
		assert_true(
			mapped_content.grow(0.5).encloses(actual),
			context + "/" + control.name + " must remain in mounted scroll content"
		)
		assert_true(
			actual.position.x >= mapped_viewport.position.x - 0.5
			and actual.end.x <= mapped_viewport.end.x + 0.5,
			context + "/" + control.name + " must remain horizontally reachable"
		)


func _assert_combat_bottom_scroll_reachability(
	screen: ProductionScreen,
	context: String
) -> void:
	var scroll := screen.find_child(
		"BottomContentScroll", true, false
	) as ScrollContainer
	assert_not_null(scroll)
	if scroll == null:
		return
	assert_eq(
		scroll.horizontal_scroll_mode,
		ScrollContainer.SCROLL_MODE_DISABLED
	)
	assert_eq(
		scroll.vertical_scroll_mode,
		ScrollContainer.SCROLL_MODE_AUTO
	)
	_assert_combat_actions_in_authored_focus_cycle(screen, context)
	var focus_owner := get_viewport().gui_get_focus_owner()
	if focus_owner != null:
		focus_owner.release_focus()
	scroll.scroll_vertical = 0
	await wait_process_frames(2)
	for shop: Button in _read_only_buttons(screen, &"combat_shop_slot"):
		_assert_control_visible_in_scroll(scroll, shop, context + "/" + shop.name)
	for action_id: StringName in [
		&"combat.pause", &"combat.inspect", &"combat.speed",
	]:
		var action := Support.action_button(screen, action_id)
		assert_not_null(action)
		if action == null:
			continue
		focus_owner = get_viewport().gui_get_focus_owner()
		if focus_owner != null:
			focus_owner.release_focus()
		await wait_process_frames(1)
		action.grab_focus()
		await wait_process_frames(3)
		assert_true(action.has_focus(), context + "/" + String(action_id))
		_assert_control_visible_in_scroll(
			scroll, action, context + "/" + action.name
		)
	var vertical_bar := scroll.get_v_scroll_bar()
	scroll.scroll_vertical = ceili(vertical_bar.max_value)
	await wait_process_frames(2)
	for bench: Button in _read_only_buttons(screen, &"combat_bench_slot"):
		_assert_control_visible_in_scroll(
			scroll, bench, context + "/" + bench.name
		)


func _assert_combat_actions_in_authored_focus_cycle(
	screen: ProductionScreen,
	context: String
) -> void:
	var ordered: Array = screen.call(&"_ordered_focus_controls")
	assert_false(ordered.is_empty(), context + " authored focus cycle must exist")
	if ordered.is_empty():
		return
	var first := ordered[0] as Control
	assert_not_null(first)
	if first == null:
		return
	var visited: Array[Control] = []
	var current := first
	for _step: int in range(ordered.size()):
		assert_not_null(current, context + " focus_next must resolve every step")
		if current == null or visited.has(current):
			break
		visited.append(current)
		current = current.get_node_or_null(current.focus_next) as Control
	assert_eq(
		visited.size(), ordered.size(),
		context + " focus_next must traverse the entire authored cycle"
	)
	assert_eq(
		current, first,
		context + " focus_next must close back to the stable first stop"
	)
	for action_id: StringName in [
		&"combat.pause", &"combat.inspect", &"combat.speed",
	]:
		var action := Support.action_button(screen, action_id)
		assert_not_null(action)
		if action != null:
			assert_true(
				visited.has(action),
				context + " focus_next must reach " + String(action_id)
			)


func _assert_control_visible_in_scroll(
	scroll: ScrollContainer,
	control: Control,
	context: String
) -> void:
	var viewport_rect := scroll.get_global_rect()
	var control_rect := control.get_global_rect()
	assert_true(
		viewport_rect.grow(1.0).encloses(control_rect),
		"%s must be fully visible in scroll viewport: %s vs %s" % [
			context, control_rect, viewport_rect,
		]
	)
func _assert_rect_close(actual: Rect2, expected: Rect2, context: String) -> void:
	assert_almost_eq(actual.position.x, expected.position.x, 0.5, context + "/x")
	assert_almost_eq(actual.position.y, expected.position.y, 0.5, context + "/y")
	assert_almost_eq(actual.size.x, expected.size.x, 0.5, context + "/width")
	assert_almost_eq(actual.size.y, expected.size.y, 0.5, context + "/height")


func _map_ui_rect(mapper: WindowCoordinateMapper, rect: Rect2) -> Rect2:
	var mapped_start := mapper.ui_to_screen(rect.position)
	var mapped_end := mapper.ui_to_screen(rect.end)
	return Rect2(mapped_start, mapped_end - mapped_start)


func _canvas_rect(control: Control) -> Rect2:
	var transform := control.get_global_transform_with_canvas()
	var points: Array[Vector2] = [
		transform * Vector2.ZERO,
		transform * Vector2(control.size.x, 0.0),
		transform * control.size,
		transform * Vector2(0.0, control.size.y),
	]
	var minimum := points[0]
	var maximum := points[0]
	for point: Vector2 in points:
		minimum = minimum.min(point)
		maximum = maximum.max(point)
	return Rect2(minimum, maximum - minimum)


func _production_viewport_fixture() -> Dictionary:
	var viewport_root := Node.new()
	viewport_root.name = "T23ProductionViewportRoot"
	add_child_autofree(viewport_root)

	var world_container := SubViewportContainer.new()
	world_container.name = "WorldViewportContainer"
	viewport_root.add_child(world_container)
	var world_viewport := SubViewport.new()
	world_viewport.name = "WorldViewport"
	world_viewport.size = BoardProjection.WORLD_SIZE
	world_container.add_child(world_viewport)
	var surface := ProductionWorldSurface.new()
	surface.name = "ProductionWorld"
	surface.size = Vector2(BoardProjection.WORLD_SIZE)
	world_viewport.add_child(surface)

	var ui_layer := CanvasLayer.new()
	ui_layer.name = "UiLayer"
	viewport_root.add_child(ui_layer)
	var ui_root := Control.new()
	ui_root.name = "UiRoot"
	ui_root.size = REFERENCE_SIZE
	ui_layer.add_child(ui_root)
	var presentation_host := Control.new()
	presentation_host.name = "PresentationHost"
	presentation_host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui_root.add_child(presentation_host)

	var coordinator := ProductionViewportCoordinator.new()
	coordinator.name = "ViewportCoordinator"
	viewport_root.add_child(coordinator)
	return {
		"root": viewport_root,
		"presentation_host": presentation_host,
		"coordinator": coordinator,
		"surface": surface,
	}


func _source_between(source: String, start: String, finish: String) -> String:
	var start_index := source.find(start)
	if start_index < 0:
		return ""
	var finish_index := source.find(finish, start_index + start.length())
	if finish_index < 0:
		return ""
	return source.substr(start_index, finish_index - start_index)


func _combat_snapshot() -> RunPresentationSnapshot:
	var snapshot := Support.CompositionSupport.combat_snapshot()
	var owner := ReservationOwnerKeyState.create(
		&"run.t23",
		&"node.t23",
		&"shop",
		&"refresh.1",
		1,
		&"owner.t23"
	)
	var offers: Array[ShopOffer] = [
		ShopOffer.new(1, "offer.t23", &"unit.enemy.alpha", 4, 1, owner),
	]
	snapshot.economy = EconomyState.new(10, 3, 0, 0, 0, 1, offers)
	var no_equipment: Array[String] = []
	var units: Array[UnitInstance] = [
		UnitInstance.new(
			"bench.t23",
			&"unit.enemy.alpha",
			2,
			no_equipment,
			U64Bits.one()
		),
	]
	var bench: Array[String] = ["bench.t23"]
	var no_placements: Array[BoardPlacementState] = []
	var no_items: Array[ItemInstanceState] = []
	var no_item_ids: Array[String] = []
	var no_relics: Array[RelicSlotState] = []
	snapshot.roster = RosterState.new(
		BoardState.new(no_placements),
		bench,
		units,
		no_items,
		no_item_ids,
		no_item_ids,
		no_relics
	)
	var preview := ShopOfferPreviewSnapshot.new()
	preview.offer_id = &"offer.t23"
	preview.slot_index = 1
	preview.unit_def_id = &"unit.enemy.alpha"
	preview.cost = 4
	preview.cost_tier = 3
	preview.owned_unit_count = 1
	preview.star_up_after_purchase = true
	snapshot.shop_offer_previews.append(preview)
	var inspection := CombatUnitInspectionSnapshot.new()
	inspection.unit_serial = 1
	inspection.presentation_instance_id = COMBAT_WORLD_ID
	inspection.source_id = &"unit.slice_monster_00"
	inspection.side_id = &"enemy"
	inspection.logical_cell = COMBAT_WORLD_CELL
	inspection.stats = {
		"star": 1,
		"health": 100,
		"start_mana": 0,
		"max_mana": 100,
	}
	snapshot.combat_inspections.append(inspection)
	return snapshot


func _localized_text() -> Dictionary:
	return {
		&"combat.pause": "暫停",
		&"combat.inspect": "檢視",
		&"combat.speed": "速度",
		&"combat.inspection.none": "無",
		&"combat.stat.star": "星級",
		&"prepare.panel.bench": "備戰區",
		&"prepare.panel.shop": "商店",
		&"prepare.panel.units": "單位",
		&"prepare.resource.gold": "金幣",
		&"tooltip.cost": "費用",
		&"tooltip.star": "星級",
		&"error.status.pre_commit": "操作未生效：",
		&"error.presentation.render_failed": "畫面顯示失敗",
		&"unit.enemy.alpha": "敵方單位",
		&"screen.run_container.title": "系統",
		&"system_menu.title": "系統選單",
		&"system_menu.continue": "繼續",
		&"system_menu.settings": "設定",
	}


func _localized_text_en() -> Dictionary:
	var values := _localized_text()
	values[&"prepare.panel.units"] = "Units"
	values[&"tooltip.cost"] = "Cost"
	values[&"tooltip.star"] = "Star"
	values[&"unit.enemy.alpha"] = "Enemy Unit"
	return values
