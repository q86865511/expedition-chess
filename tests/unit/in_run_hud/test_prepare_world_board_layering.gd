extends GutTest

const OUTPUT_SIZES: Array[Vector2i] = [
	Vector2i(1280, 720),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440),
]
const UI_SCALES: Array[int] = [100, 125, 150]
const REFERENCE_SIZE := Vector2(1920.0, 1080.0)
const BOARD_UNIT_ID := "board.layering.unit"
const BENCH_UNIT_ID := "bench.layering.unit"


class CapturingIntentPort:
	extends LiveScreenIntentPort

	var intents: Array[RunPresentationIntent] = []
	var _snapshot: RunPresentationSnapshot
	var preview_supply: LiveScreenSupplyPort


	func _init(snapshot: RunPresentationSnapshot) -> void:
		_snapshot = snapshot.deep_clone()


	func dispatch(intent: RunPresentationIntent) -> RunPresentationResult:
		intents.append(intent.deep_clone())
		var canonical := _snapshot.deep_clone()
		if intent.kind == RunPresentationIntent.Kind.COMMIT_BOARD_LAYOUT:
			canonical.roster.board = intent.board.deep_clone()
			canonical.roster.bench_unit_instance_ids.assign(
				intent.bench_unit_instance_ids
			)
		_snapshot = canonical.deep_clone()
		return RunPresentationResult.success(canonical)


	func supply_port() -> LiveScreenSupplyPort:
		return preview_supply


class LayeringPreviewSupplyPort:
	extends LiveScreenSupplyPort

	var _committed: BoardDraftPreviewSnapshot


	func _init(snapshot: RunPresentationSnapshot) -> void:
		_committed = _preview(snapshot.roster.board.placements)


	func try_committed_board_preview() -> BoardDraftPreviewSnapshot:
		return _committed.deep_clone()


	func try_board_draft_preview(
		draft_placements: Array[BoardPlacementState],
		_draft_bench_unit_instance_ids: Array[String]
	) -> BoardDraftPreviewSnapshot:
		return _preview(draft_placements)


	func _preview(
		placements: Array[BoardPlacementState]
	) -> BoardDraftPreviewSnapshot:
		var result := BoardDraftPreviewSnapshot.new()
		result.used_population = placements.size()
		result.derived_capacity = 2
		result.valid = placements.size() <= result.derived_capacity
		return result


func test_prepare_world_board_is_not_covered_across_output_and_ui_scales() -> void:
	var fixture := await _fixture()
	var screen := fixture.get("screen") as ProductionScreen
	var composition := fixture.get("composition") as RunPrepareScreen
	var surface := fixture.get("surface") as ProductionWorldSurface
	assert_not_null(screen)
	assert_not_null(composition)
	assert_not_null(surface)
	if screen == null or composition == null or surface == null:
		return

	var runtime := ExpeditionThemeRuntime.new()
	var policy := WorldViewportPolicy.new()
	for output_size: Vector2i in OUTPUT_SIZES:
		for scale_percent: int in UI_SCALES:
			var context := "%dx%d@ui%d" % [
				output_size.x, output_size.y, scale_percent,
			]
			var mapper := WindowCoordinateMapper.new()
			assert_eq(
				mapper.configure(
					policy.layout_for_window(output_size),
					scale_percent
				),
				&"",
				"%s: coordinate mapper must configure" % context
			)
			assert_eq(
				surface.refresh_coordinate_mapper(mapper),
				&"",
				"%s: mounted world overlay must accept the mapper" % context
			)
			assert_true(
				runtime.apply(screen, scale_percent),
				"%s: production theme scale must apply" % context
			)
			screen.apply_theme_scale_layout(scale_percent)
			await wait_process_frames(4)
			_assert_world_layering(
				screen,
				composition,
				surface,
				mapper,
				context
			)
			await _assert_prepare_shop_action_scroll(screen, context)
			await _assert_bottom_focus_scroll(screen, context)


func test_board_routes_cap_bottom_below_projection_and_other_routes_do_not() -> void:
	for route_kind: StringName in [&"RUN_PREPARE", &"RUN_COMBAT"]:
		var host := Control.new()
		host.anchor_left = 0.0
		host.anchor_top = 0.0
		host.anchor_right = 0.0
		host.anchor_bottom = 0.0
		host.position = Vector2.ZERO
		host.size = REFERENCE_SIZE
		add_child_autofree(host)
		var shell := ProductionLayoutShell.new()
		host.add_child(shell)
		shell.build(route_kind)
		shell.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var status_action := Button.new()
		status_action.name = "StatusVisibleBottomAction"
		status_action.focus_mode = Control.FOCUS_ALL
		shell.content(ProductionLayoutShell.REGION_BOTTOM).add_child(
			status_action
		)
		await wait_process_frames(1)
		for scale_percent: int in UI_SCALES:
			shell.set_scale_factor(float(scale_percent) / 100.0)
			ExpeditionLayoutMetrics.set_runtime_min(
				status_action,
				Vector2(180.0, 72.0 * float(scale_percent) / 100.0)
			)
			await wait_process_frames(1)
			_assert_actual_board_band_rects(
				shell,
				"%s@ui%d:status-hidden" % [route_kind, scale_percent]
			)
			var bottom_rect := shell.current_region_rect(
				ProductionLayoutShell.REGION_BOTTOM
			)
			assert_lte(
				bottom_rect.size.y,
				ProductionLayoutShell.BOARD_ROUTE_BOTTOM_HEIGHT_CAP,
				"%s@ui%d: board-route bottom height must be capped" % [
					route_kind, scale_percent,
				]
			)
			assert_gte(
				bottom_rect.position.y,
				804.0,
				"%s@ui%d: bottom band must start below the board AABB" % [
					route_kind, scale_percent,
				]
			)
			_assert_bottom_scroll_contract(shell, route_kind)
			shell.set_status_visible(true)
			await wait_process_frames(1)
			_assert_actual_board_band_rects(
				shell,
				"%s@ui%d:status-visible" % [route_kind, scale_percent]
			)
			var status_rect := shell.current_region_rect(
				ProductionLayoutShell.REGION_STATUS
			)
			bottom_rect = shell.current_region_rect(
				ProductionLayoutShell.REGION_BOTTOM
			)
			var expected_status_cap := (
				ProductionLayoutShell.BOARD_ROUTE_BOTTOM_HEIGHT_CAP
				- ProductionLayoutShell.STATUS_GUTTER
				- ceilf(
					ProductionLayoutShell.STATUS_HEIGHT
					* float(scale_percent) / 100.0
				)
			)
			assert_eq(
				bottom_rect.size.y,
				expected_status_cap,
				"%s@ui%d: visible status must shrink only the scroll band" % [
					route_kind, scale_percent,
				]
			)
			assert_gte(
				status_rect.position.y,
				804.0,
				"%s@ui%d: status+gap+bottom must stay below the board" % [
					route_kind, scale_percent,
				]
			)
			await _assert_status_bottom_action_reachable(
				shell,
				status_action,
				"%s@ui%d" % [route_kind, scale_percent]
			)
			shell.set_status_visible(false)
			await wait_process_frames(1)
			_assert_actual_board_band_rects(
				shell,
				"%s@ui%d:status-restored" % [route_kind, scale_percent]
			)
		host.queue_free()
		await wait_process_frames(1)

	for route_kind: StringName in [&"RUN_MAP", &"RUN_REWARD"]:
		var host := Control.new()
		host.anchor_left = 0.0
		host.anchor_top = 0.0
		host.anchor_right = 0.0
		host.anchor_bottom = 0.0
		host.position = Vector2.ZERO
		host.size = REFERENCE_SIZE
		add_child_autofree(host)
		var shell := ProductionLayoutShell.new()
		host.add_child(shell)
		shell.build(route_kind)
		shell.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		shell.set_scale_factor(1.5)
		shell.set_status_visible(true)
		await wait_process_frames(1)
		_assert_actual_board_band_rects(
			shell, "%s@ui150:status-visible" % route_kind
		)
		var bottom_rect := shell.current_region_rect(
			ProductionLayoutShell.REGION_BOTTOM
		)
		assert_eq(
			bottom_rect.size.y,
			ceilf(ProductionLayoutShell.BOTTOM_HEIGHT * 1.5),
			"%s must preserve the uncapped skeleton height" % route_kind
		)
		assert_null(
			shell.find_child("BottomContentScroll", true, false),
			"%s must not inherit the world-board scroll cap" % route_kind
		)
		host.queue_free()
		await wait_process_frames(1)


func test_prepare_keyboard_paths_survive_hidden_legacy_board_grid() -> void:
	var fixture := await _fixture()
	var screen := fixture.get("screen") as ProductionScreen
	var composition := fixture.get("composition") as RunPrepareScreen
	var port := fixture.get("port") as CapturingIntentPort
	assert_not_null(screen)
	assert_not_null(composition)
	assert_not_null(port)
	if screen == null or composition == null or port == null:
		return

	var build_units := composition.find_child(
		"BuildUnitSelector", true, false
	) as ItemList
	var board_grid := composition.find_child(
		"BoardGrid", true, false
	) as GridContainer
	var group_selector := screen.find_child(
		"PrepareActionGroupSelector", true, false
	) as OptionButton
	var placement_targets := composition.find_child(
		"UnitSelector", true, false
	) as ItemList
	assert_not_null(build_units)
	assert_not_null(board_grid)
	assert_not_null(group_selector)
	assert_not_null(placement_targets)
	if (
		build_units == null
		or board_grid == null
		or group_selector == null
		or placement_targets == null
	):
		return
	assert_eq(build_units.get_meta(&"typed_data_kind"), &"unit_instance")
	assert_eq(build_units.focus_mode, Control.FOCUS_ALL)

	var bench_index := _item_index_for(build_units, BENCH_UNIT_ID)
	assert_gte(bench_index, 0, "BuildUnitSelector must expose the bench unit")
	if bench_index < 0:
		return
	build_units.select(bench_index)
	build_units.item_selected.emit(bench_index)
	build_units.grab_focus()
	# Party is the second authored group and owns the legacy move buttons.
	group_selector.select(1)
	group_selector.item_selected.emit(1)
	await wait_process_frames(3)

	var focus_ring: Array = screen.call(&"_ordered_focus_controls")
	assert_true(
		focus_ring.has(build_units),
		"BuildUnitSelector must remain keyboard reachable"
	)
	assert_true(
		focus_ring.has(placement_targets),
		"row-major board and slot-order bench proxy must enter the focus graph"
	)
	assert_eq(
		placement_targets.get_meta(&"stable_focus_id"),
		&"prepare.placement_targets"
	)
	assert_eq(placement_targets.item_count, 41)
	assert_eq(
		board_grid.get_child_count(),
		BoardPreparationValidator.PLAYER_HALF_CAPACITY,
		"hidden row-major keyboard proxy must still author all player-half cells"
	)
	for node: Node in board_grid.get_children():
		var board_cell := node as Control
		if board_cell != null:
			assert_false(
				focus_ring.has(board_cell),
				"hidden legacy BoardGrid cells must not enter the focus graph"
			)
	for action_id: StringName in [
		&"prepare.move_board",
		&"prepare.move_bench",
	]:
		var action := _action_button(screen, action_id)
		assert_not_null(action, "%s must keep its existing button path" % action_id)
		if action != null and not action.disabled:
			assert_true(
				focus_ring.has(action),
				"%s must remain keyboard reachable when enabled" % action_id
			)

	var quick_toggle := InputEventAction.new()
	quick_toggle.action = &"prepare_quick_toggle_unit"
	quick_toggle.pressed = true
	composition.call(&"_unhandled_input", quick_toggle)
	await wait_process_frames(2)
	assert_eq(
		port.intents.size(),
		1,
		"BuildUnitSelector focus/selection plus W must commit one board draft"
	)
	if port.intents.is_empty():
		return
	var intent := port.intents[0]
	assert_eq(intent.kind, RunPresentationIntent.Kind.COMMIT_BOARD_LAYOUT)
	assert_false(intent.bench_unit_instance_ids.has(BENCH_UNIT_ID))
	var moved_to_board := false
	for placement: BoardPlacementState in intent.board.placements:
		if placement != null and placement.unit_instance_id == BENCH_UNIT_ID:
			moved_to_board = true
			break
	assert_true(
		moved_to_board,
		"W must move the selected bench unit onto the canonical board draft"
	)


func test_world_unit_hover_supplies_w_target_without_click() -> void:
	var fixture := await _fixture()
	var composition := fixture.get("composition") as RunPrepareScreen
	var surface := fixture.get("surface") as ProductionWorldSurface
	var coordinator := fixture.get(
		"coordinator"
	) as ProductionViewportCoordinator
	var port := fixture.get("port") as CapturingIntentPort
	assert_not_null(composition)
	assert_not_null(surface)
	assert_not_null(coordinator)
	assert_not_null(port)
	if (
		composition == null
		or surface == null
		or coordinator == null
		or port == null
	):
		return
	var overlay := surface.ui_overlay()
	var target := overlay.drag_target() if overlay != null else null
	var mapper := coordinator.coordinate_mapper_clone()
	assert_not_null(target)
	assert_not_null(mapper)
	if target == null or mapper == null:
		return
	var board_unit_screen := mapper.world_to_screen(
		BoardProjection.new().project_cell(Vector2i(0, 0))
	)
	var motion := InputEventMouseMotion.new()
	motion.position = (
		target.get_global_transform_with_canvas().affine_inverse()
		* board_unit_screen
	)
	target.call(&"_gui_input", motion)
	assert_eq(
		composition.get(&"_quick_toggle_unit_id"),
		BOARD_UNIT_ID,
		"hover over a projected world sprite must update the W authority"
	)
	assert_eq(
		surface.refresh_coordinate_mapper(mapper),
		&"",
		"resize/remount lifecycle must reconfigure the projected target"
	)
	assert_eq(
		composition.get(&"_quick_toggle_unit_id"),
		"",
		"reconfigure must relay an empty hover and clear stale W authority"
	)
	# The next real motion may reacquire the same logical unit from the newly
	# configured projection.
	target.call(&"_gui_input", motion)
	var quick_toggle := InputEventAction.new()
	quick_toggle.action = &"prepare_quick_toggle_unit"
	quick_toggle.pressed = true
	composition.call(&"_unhandled_input", quick_toggle)
	assert_eq(port.intents.size(), 1)
	if port.intents.is_empty():
		return
	assert_true(
		port.intents[0].bench_unit_instance_ids.has(BOARD_UNIT_ID),
		"hover plus W must collect the hovered board unit to the bench"
	)


func test_world_unit_drop_commits_the_exact_projected_player_cell() -> void:
	var fixture := await _fixture()
	var surface := fixture.get("surface") as ProductionWorldSurface
	var coordinator := fixture.get(
		"coordinator"
	) as ProductionViewportCoordinator
	var port := fixture.get("port") as CapturingIntentPort
	assert_not_null(surface)
	assert_not_null(coordinator)
	assert_not_null(port)
	if surface == null or coordinator == null or port == null:
		return
	var overlay := surface.ui_overlay()
	var target := overlay.drag_target() if overlay != null else null
	var mapper := coordinator.coordinate_mapper_clone()
	assert_not_null(target)
	assert_not_null(mapper)
	if target == null or mapper == null:
		return
	var destination := Vector2i(7, 3)
	var screen_position := mapper.world_to_screen(
		BoardProjection.new().project_cell(destination)
	)
	var local_position := (
		target.get_global_transform_with_canvas().affine_inverse()
		* screen_position
	)
	var payload := {
		"kind": &"prepare_unit",
		"unit_instance_id": BOARD_UNIT_ID,
		"source_kind": &"board",
		"source_cell": Vector2i.ZERO,
		"source_slot": -1,
	}
	var drops: Array[Dictionary] = []
	target.unit_dropped.connect(func(unit_id: String, cell: Vector2i) -> void:
		drops.append({"unit_id": unit_id, "cell": cell})
	)
	assert_true(
		target.call(&"_can_drop_data", local_position, payload),
		"a player-half cell center must remain a legal projected drop target"
	)
	target.call(&"_drop_data", local_position, payload)
	assert_eq(drops.size(), 1)
	if drops.size() != 1:
		return
	assert_eq(String(drops[0].get("unit_id", "")), BOARD_UNIT_ID)
	assert_eq(drops[0].get("cell", Vector2i(-1, -1)), destination)
	assert_eq(port.intents.size(), 1)
	if port.intents.size() != 1:
		return
	var intent := port.intents[0]
	assert_eq(intent.kind, RunPresentationIntent.Kind.COMMIT_BOARD_LAYOUT)
	assert_true(intent.board.placements.any(
		func(placement: BoardPlacementState) -> bool:
			return (
				placement != null
				and placement.unit_instance_id == BOARD_UNIT_ID
				and placement.logical_x == destination.x
				and placement.logical_y == destination.y
			)
	))


func _assert_world_layering(
	screen: ProductionScreen,
	composition: RunPrepareScreen,
	surface: ProductionWorldSurface,
	mapper: WindowCoordinateMapper,
	context: String
) -> void:
	var board_grid := composition.find_child(
		"BoardGrid", true, false
	) as GridContainer
	var bench := composition.find_child("BenchRow", true, false) as HBoxContainer
	var inventory := composition.find_child(
		"InventorySelector", true, false
	) as ItemList
	var center_scroll := composition.find_child(
		"PrepareCenterScroll", true, false
	) as ScrollContainer
	var hud := composition.find_child(
		"InRunHudShell", true, false
	) as InRunHudShell
	var overlay := surface.ui_overlay()
	var drag_target: WorldBoardDragTarget = (
		overlay.drag_target() if overlay != null else null
	)
	var bottom_panel := screen.find_child(
		"BottomRegion", true, false
	) as Control
	var bottom_scroll := screen.find_child(
		"BottomContentScroll", true, false
	) as ScrollContainer

	assert_not_null(board_grid, "%s: legacy BoardGrid probe is required" % context)
	assert_not_null(bench, "%s: BenchRow is required" % context)
	assert_not_null(inventory, "%s: InventorySelector is required" % context)
	assert_not_null(center_scroll, "%s: center scroll is required" % context)
	assert_not_null(hud, "%s: shared HUD is required" % context)
	assert_not_null(overlay, "%s: world overlay must be mounted" % context)
	assert_not_null(drag_target, "%s: world drag target must exist" % context)
	assert_not_null(mapper, "%s: coordinate mapper must exist" % context)
	assert_not_null(bottom_panel, "%s: bottom panel must exist" % context)
	assert_not_null(bottom_scroll, "%s: board bottom scroll must exist" % context)
	if (
		board_grid == null
		or bench == null
		or inventory == null
		or center_scroll == null
		or hud == null
		or drag_target == null
		or mapper == null
		or bottom_panel == null
		or bottom_scroll == null
	):
		return
	_assert_bottom_scroll_contract(screen.get("_layout_shell"), &"RUN_PREPARE")

	# Invisible controls are excluded from Container layout in Godot. Requiring
	# the node itself to be hidden (not merely clipped) proves it neither paints
	# nor reserves the former 8x4 control-grid footprint.
	assert_false(board_grid.visible, "%s: legacy BoardGrid must be hidden" % context)
	assert_false(
		board_grid.is_visible_in_tree(),
		"%s: legacy BoardGrid must not paint" % context
	)
	assert_eq(
		board_grid.mouse_filter,
		Control.MOUSE_FILTER_IGNORE,
		"%s: legacy BoardGrid must not consume pointer input" % context
	)
	assert_true(
		board_grid.custom_minimum_size.is_zero_approx(),
		"%s: legacy BoardGrid must not reserve a minimum layout footprint" % context
	)

	assert_true(bench.is_visible_in_tree(), "%s: bench must remain visible" % context)
	assert_eq(bench.get_child_count(), 9, "%s: bench must retain nine slots" % context)
	assert_false(
		center_scroll.is_ancestor_of(bench),
		"%s: bench must not re-enter theme-scaled center flow" % context
	)
	var previous_x := -INF
	var reference_y := NAN
	for index: int in bench.get_child_count():
		var cell := bench.get_child(index) as Control
		assert_not_null(cell, "%s: bench slot %d must be a Control" % [context, index])
		if cell == null:
			continue
		var cell_rect := cell.get_global_rect()
		assert_true(
			cell_rect.position.x > previous_x,
			"%s: bench slots must progress horizontally at slot %d" % [
				context, index,
			]
		)
		if is_nan(reference_y):
			reference_y = cell_rect.position.y
		else:
			assert_almost_eq(
				cell_rect.position.y,
				reference_y,
				1.0,
				"%s: bench slot %d must stay on one row" % [context, index]
			)
		previous_x = cell_rect.position.x
	var bench_reference_rect := bench.get_global_rect()
	var bench_screen_start := mapper.ui_to_screen(
		bench_reference_rect.position
	)
	var bench_screen_end := mapper.ui_to_screen(bench_reference_rect.end)
	var bench_screen_rect := Rect2(
		bench_screen_start,
		bench_screen_end - bench_screen_start
	)
	assert_false(
		bench_screen_rect.intersects(drag_target.get_global_rect()),
		"%s: bench %s must not cover world drag %s" % [
			context, bench_screen_rect, drag_target.get_global_rect(),
		]
	)
	var projection := BoardProjection.new()
	var expected_drag_rect := _projected_board_screen_aabb(
		projection,
		mapper
	)
	assert_eq(
		drag_target.get_global_rect(),
		expected_drag_rect,
		"%s: drag target rect must be the exact projected 8x8 AABB" % context
	)
	var bottom_reference_rect := (
		screen.get("_layout_shell") as ProductionLayoutShell
	).current_region_rect(ProductionLayoutShell.REGION_BOTTOM)
	var bottom_screen_top := mapper.ui_to_screen(
		Vector2(0.0, bottom_reference_rect.position.y)
	).y
	assert_lte(
		drag_target.get_global_rect().end.y,
		bottom_screen_top,
		"%s: world board must end before the bottom band begins" % context
	)
	var target_inverse := (
		drag_target.get_global_transform_with_canvas().affine_inverse()
	)
	for logical_y: int in range(8):
		for logical_x: int in range(8):
			var cell := Vector2i(logical_x, logical_y)
			var world_center := projection.project_cell(cell)
			var screen_center := mapper.world_to_screen(world_center)
			assert_true(
				drag_target.get_global_rect().has_point(screen_center),
				"%s: projected cell %s must stay inside the target rect" % [
					context, cell,
				]
			)
			var round_trip_world := mapper.screen_to_world(screen_center)
			var fractional := projection.world_to_fractional(round_trip_world)
			assert_almost_eq(fractional.x, float(logical_x), 0.000001)
			assert_almost_eq(fractional.y, float(logical_y), 0.000001)
			assert_eq(
				projection.try_screen_to_cell(
					screen_center,
					mapper,
					func(_candidate: Vector2i) -> bool: return true
				),
				cell,
				"%s: all 64 projected centers must survive exact inverse" % context
			)
			var local_center := target_inverse * screen_center
			var hit_cell: Vector2i = drag_target.call(&"_cell_at", local_center)
			assert_eq(
				hit_cell,
				cell if logical_y < 4 else Vector2i(-1, -1),
				(
					"%s: projected cell %s must invert exactly before the "
					+ "player-half validator"
				) % [context, cell]
			)

	var left_host := hud.host(ProductionLayoutShell.REGION_LEFT)
	var left_scroll := hud.find_child(
		"InRunLeftScroll", true, false
	) as ScrollContainer
	assert_not_null(left_host, "%s: shared HUD left host is required" % context)
	assert_not_null(left_scroll, "%s: shared HUD left scroll is required" % context)
	assert_true(
		left_host != null and left_host.is_ancestor_of(inventory),
		"%s: InventorySelector must live in HudLeftHost" % context
	)
	assert_true(
		left_scroll != null and left_scroll.is_ancestor_of(inventory),
		"%s: InventorySelector must live in InRunLeftScroll" % context
	)
	assert_false(
		center_scroll.is_ancestor_of(inventory),
		"%s: InventorySelector must not occupy the world-board center" % context
	)
	assert_true(
		inventory.is_visible_in_tree(),
		"%s: InventorySelector must remain usable" % context
	)


func _assert_bottom_scroll_contract(
	shell: ProductionLayoutShell,
	route_kind: StringName
) -> void:
	assert_not_null(shell, "%s: layout shell must exist" % route_kind)
	if shell == null:
		return
	var scroll := shell.find_child(
		"BottomContentScroll", true, false
	) as ScrollContainer
	var content := shell.content(ProductionLayoutShell.REGION_BOTTOM)
	assert_not_null(scroll, "%s: bottom scroll host must exist" % route_kind)
	assert_not_null(content, "%s: bottom content must exist" % route_kind)
	if scroll == null or content == null:
		return
	assert_true(scroll.is_ancestor_of(content))
	assert_eq(
		scroll.horizontal_scroll_mode,
		ScrollContainer.SCROLL_MODE_DISABLED
	)
	assert_eq(
		scroll.vertical_scroll_mode,
		ScrollContainer.SCROLL_MODE_AUTO
	)
	assert_true(scroll.follow_focus)


func _assert_actual_board_band_rects(
	shell: ProductionLayoutShell,
	context: String
) -> void:
	var bottom_panel := shell.find_child(
		"BottomRegion", true, false
	) as Control
	var status_panel := shell.find_child(
		"StatusRegion", true, false
	) as Control
	assert_not_null(bottom_panel, "%s: actual bottom panel must exist" % context)
	assert_not_null(status_panel, "%s: actual status panel must exist" % context)
	if bottom_panel == null or status_panel == null:
		return
	assert_eq(
		bottom_panel.get_global_rect(),
		shell.current_region_rect(ProductionLayoutShell.REGION_BOTTOM),
		"%s: actual bottom rect must match shell authority" % context
	)
	assert_eq(
		status_panel.get_global_rect(),
		shell.current_region_rect(ProductionLayoutShell.REGION_STATUS),
		"%s: actual status rect must match shell authority" % context
	)
	var expected_variation := (
		ProductionLayoutShell.ACTION_BAR_COMPACT_VARIATION
		if (
			shell.is_status_visible()
			and shell.find_child("BottomContentScroll", true, false) != null
		)
		else ProductionLayoutShell.ACTION_BAR_VARIATION
	)
	assert_eq(
		bottom_panel.theme_type_variation,
		expected_variation,
		"%s: bottom panel compact variation must follow status state" % context
	)


func _assert_bottom_focus_scroll(
	screen: ProductionScreen,
	context: String
) -> void:
	var scroll := screen.find_child(
		"BottomContentScroll", true, false
	) as ScrollContainer
	assert_not_null(scroll, "%s: bottom scroll host must exist" % context)
	if scroll == null:
		return
	var deepest: Button
	var deepest_end_y := -INF
	for node: Node in scroll.find_children("*", "Button", true, false):
		var button := node as Button
		if (
			button == null
			or not button.is_visible_in_tree()
			or button.disabled
			or button.focus_mode == Control.FOCUS_NONE
		):
			continue
		var end_y := button.get_global_rect().end.y
		if end_y > deepest_end_y:
			deepest = button
			deepest_end_y = end_y
	assert_not_null(deepest, "%s: bottom band needs an enabled focus target" % context)
	if deepest == null:
		return
	var focus_owner := screen.get_viewport().gui_get_focus_owner()
	if focus_owner != null:
		focus_owner.release_focus()
	await wait_process_frames(1)
	scroll.scroll_vertical = 0
	await wait_process_frames(1)
	deepest.grab_focus()
	await wait_process_frames(3)
	assert_true(deepest.has_focus(), "%s: bottom target must take focus" % context)
	assert_true(
		scroll.get_global_rect().grow(1.0).encloses(deepest.get_global_rect()),
		"%s: bottom scroll %s must reveal focused %s" % [
			context, scroll.get_global_rect(), deepest.get_global_rect(),
		]
	)


func _assert_prepare_shop_action_scroll(
	screen: ProductionScreen,
	context: String
) -> void:
	var scroll := screen.find_child(
		"PrepareShopActionsScroll", true, false
	) as ScrollContainer
	var actions := screen.find_child(
		"PrepareShopActions", true, false
	) as GridContainer
	assert_not_null(scroll, "%s: shop action viewport must exist" % context)
	assert_not_null(actions, "%s: shop action content must exist" % context)
	if scroll == null or actions == null:
		return
	assert_true(scroll.is_ancestor_of(actions))
	assert_eq(
		scroll.horizontal_scroll_mode,
		ScrollContainer.SCROLL_MODE_DISABLED
	)
	assert_eq(
		scroll.vertical_scroll_mode,
		ScrollContainer.SCROLL_MODE_AUTO
	)
	assert_true(scroll.follow_focus)
	scroll.scroll_vertical = 0
	await wait_process_frames(2)
	var viewport := scroll.get_global_rect()
	var visible_buttons := 0
	for node: Node in actions.find_children("*", "Button", true, false):
		var button := node as Button
		if button == null or not button.is_visible_in_tree():
			continue
		var button_rect := button.get_global_rect()
		var intersection := viewport.intersection(button_rect)
		if intersection.size.y <= 0.5:
			continue
		visible_buttons += 1
		assert_true(
			viewport.grow(1.0).encloses(button_rect),
			"%s: shop viewport must never expose a partial button" % context
		)
	assert_eq(
		visible_buttons,
		1,
		"%s: the bounded shop viewport starts on one complete action" % context
	)
	assert_true(
		scroll.get_v_scroll_bar().visible,
		"%s: additional shop actions need an explicit scroll boundary" % context
	)


func _assert_status_bottom_action_reachable(
	shell: ProductionLayoutShell,
	action: Button,
	context: String
) -> void:
	var scroll := shell.find_child(
		"BottomContentScroll", true, false
	) as ScrollContainer
	assert_not_null(scroll, "%s: status bottom scroll must exist" % context)
	if scroll == null:
		return
	var focus_owner := shell.get_viewport().gui_get_focus_owner()
	if focus_owner != null:
		focus_owner.release_focus()
	await wait_process_frames(1)
	scroll.scroll_vertical = 0
	await wait_process_frames(1)
	action.grab_focus()
	await wait_process_frames(2)
	assert_true(action.has_focus(), "%s: status action must take focus" % context)
	var scroll_rect := scroll.get_global_rect()
	var action_rect := action.get_global_rect()
	var visible_intersection := scroll_rect.intersection(action_rect)
	var required_visible_height := minf(
		scroll_rect.size.y, action_rect.size.y
	) - 1.0
	assert_true(
		visible_intersection.size.y >= required_visible_height,
		"%s: status scroll must expose the full shorter height" % context
	)
	assert_true(
		action_rect.get_center().y >= scroll_rect.position.y - 1.0
		and action_rect.get_center().y <= scroll_rect.end.y + 1.0,
		"%s: focused action vertical center must stay in the viewport" % context
	)


func _projected_board_screen_aabb(
	projection: BoardProjection,
	mapper: WindowCoordinateMapper
) -> Rect2:
	var minimum := Vector2(INF, INF)
	var maximum := Vector2(-INF, -INF)
	for logical_corner: Vector2 in [
		Vector2(-0.5, -0.5),
		Vector2(7.5, -0.5),
		Vector2(7.5, 7.5),
		Vector2(-0.5, 7.5),
	]:
		var screen_corner := mapper.world_to_screen(
			projection.logical_to_world(logical_corner)
		)
		minimum = minimum.min(screen_corner)
		maximum = maximum.max(screen_corner)
	minimum = minimum.floor()
	maximum = maximum.ceil()
	return Rect2(minimum, maximum - minimum)


func _fixture() -> Dictionary:
	var surface := ProductionWorldSurface.new()
	surface.name = "LayeringWorldSurface"
	surface.size = Vector2(640.0, 360.0)
	add_child_autofree(surface)
	var coordinator := ProductionViewportCoordinator.new()
	coordinator.name = "LayeringViewportCoordinator"
	add_child_autofree(coordinator)
	await wait_process_frames(1)
	assert_eq(
		coordinator._mapper.configure(
			WorldViewportPolicy.new().layout_for_window(Vector2i(1920, 1080)),
			100
		),
		&""
	)

	var snapshot := _snapshot()
	var port := CapturingIntentPort.new(snapshot)
	port.preview_supply = LayeringPreviewSupplyPort.new(snapshot)
	var screen := ProductionSceneCatalog.new().instantiate(&"RUN_PREPARE")
	assert_not_null(screen)
	if screen == null:
		return {}
	screen.anchor_left = 0.0
	screen.anchor_top = 0.0
	screen.anchor_right = 0.0
	screen.anchor_bottom = 0.0
	screen.position = Vector2.ZERO
	screen.size = REFERENCE_SIZE
	assert_eq(
		screen.bind(StagedScreenContext.new(
			&"RUN_PREPARE",
			snapshot,
			null,
			&"zh_TW",
			_localized_text()
		)),
		&""
	)
	assert_eq(
		screen.prepare_live_binding(ProductionLiveScreenContext.new(
			&"RUN_PREPARE",
			snapshot,
			null,
			null,
			null,
			port
		)),
		&""
	)
	add_child_autofree(screen)
	screen.activate_live()
	await wait_process_frames(4)
	var composition := screen.get_node_or_null(^"Composition") as RunPrepareScreen
	assert_not_null(composition)
	if composition != null:
		assert_eq(composition.world_board_mount_error(), &"")
	return {
		"screen": screen,
		"composition": composition,
		"surface": surface,
		"coordinator": coordinator,
		"port": port,
	}


func _snapshot() -> RunPresentationSnapshot:
	var snapshot := RunPresentationSnapshot.new()
	snapshot.run_id = &"run_prepare_world_layering"
	snapshot.app_phase = &"PREPARE"
	var placements: Array[BoardPlacementState] = [
		BoardPlacementState.new(0, 0, BOARD_UNIT_ID),
	]
	var bench: Array[String] = [BENCH_UNIT_ID]
	var equipment: Array[String] = []
	var units: Array[UnitInstance] = [
		UnitInstance.new(
			BOARD_UNIT_ID,
			&"unit.slice_player_00",
			1,
			equipment,
			U64Bits.zero()
		),
		UnitInstance.new(
			BENCH_UNIT_ID,
			&"unit.slice_player_01",
			1,
			equipment,
			U64Bits.one()
		),
	]
	var items: Array[ItemInstanceState] = []
	var inventory: Array[String] = []
	var overflow: Array[String] = []
	var relics: Array[RelicSlotState] = []
	snapshot.roster = RosterState.new(
		BoardState.new(placements),
		bench,
		units,
		items,
		inventory,
		overflow,
		relics
	)
	var issues: Array[BoardValidationIssue] = []
	snapshot.board_validation_report = BoardValidationReport.new(2, issues)
	return snapshot


func _item_index_for(selector: ItemList, identity: String) -> int:
	for index: int in selector.item_count:
		if String(selector.get_item_metadata(index)) == identity:
			return index
	return -1


func _action_button(
	screen: ProductionScreen,
	action_id: StringName
) -> Button:
	for node: Node in screen.find_children("*", "Button", true, false):
		var button := node as Button
		if (
			button != null
			and StringName(button.get_meta(&"action_id", &"")) == action_id
		):
			return button
	return null


func _localized_text() -> Dictionary:
	return {
		&"error.status.pre_commit": "",
		&"error.presentation.render_failed": "render-failed",
	}
