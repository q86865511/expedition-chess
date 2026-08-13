extends GutTest

const CompositionSupport = preload(
	"res://tests/integration/presentation_ui_nonterminal_scene_composition/"
	+ "scene_composition_test_support.gd"
)

const ERROR_TEXT := "localized-render-failed"


func test_prepare_mount_failure_reaches_player_visible_status() -> void:
	var snapshot := _prepare_snapshot()
	var screen := _screen(&"RUN_PREPARE", snapshot)
	assert_not_null(screen)
	if screen == null:
		return
	add_child_autofree(screen)
	await wait_process_frames(2)
	_assert_surface_missing_is_visible(screen)


func test_prepare_detached_compose_retries_mount_when_candidate_enters_tree() -> void:
	var snapshot := _prepare_snapshot()
	var screen := _screen(&"RUN_PREPARE", snapshot)
	assert_not_null(screen)
	if screen == null:
		return
	var composition := screen.get_node_or_null(^"Composition") as RunPrepareScreen
	assert_not_null(composition)
	if composition == null:
		screen.free()
		return

	# Mirror SceneRouterService.prepare_production(): bind and live-compose the
	# candidate while detached, then let the compose-time deferred mount run.
	await wait_process_frames(1)
	assert_false(screen.is_inside_tree())
	assert_eq(composition.world_board_mount_error(), &"")
	assert_true(screen.status_message_text().is_empty())

	# SceneRouterService.commit_prepared() adds the same candidate. ENTER_TREE
	# must schedule a new formal callsite attempt and surface its named failure.
	add_child_autofree(screen)
	await wait_process_frames(2)
	_assert_surface_missing_is_visible(screen)


func test_combat_mount_failure_reaches_player_visible_status() -> void:
	var snapshot := _combat_snapshot()
	var screen := _screen(&"RUN_COMBAT", snapshot)
	assert_not_null(screen)
	if screen == null:
		return
	add_child_autofree(screen)
	await wait_process_frames(2)
	_assert_surface_missing_is_visible(screen)


func test_persistent_surface_prepare_to_combat_uses_route_local_overlay_hosts() -> void:
	var surface := ProductionWorldSurface.new()
	surface.size = Vector2(640.0, 360.0)
	add_child_autofree(surface)
	var coordinator := ProductionViewportCoordinator.new()
	add_child_autofree(coordinator)
	await wait_process_frames(1)
	assert_eq(
		coordinator._mapper.configure(
			WorldViewportPolicy.new().layout_for_window(Vector2i(1920, 1080)),
			100
		),
		&""
	)

	var prepare_screen := _screen(&"RUN_PREPARE", _prepare_snapshot())
	assert_not_null(prepare_screen)
	if prepare_screen == null:
		return
	add_child_autofree(prepare_screen)
	await wait_process_frames(2)
	var prepare_composition := (
		prepare_screen.get_node_or_null(^"Composition") as RunPrepareScreen
	)
	assert_not_null(prepare_composition)
	if prepare_composition == null:
		return
	assert_eq(prepare_composition.world_board_mount_error(), &"")
	var prepare_shell := (
		prepare_composition.find_child("InRunHudShell", true, false)
		as InRunHudShell
	)
	assert_not_null(prepare_shell)
	if prepare_shell == null:
		return
	var prepare_overlay_host := prepare_shell.host(
		ProductionLayoutShell.REGION_OVERLAY
	)
	var overlay := surface.ui_overlay()
	assert_not_null(overlay)
	if overlay == null:
		return
	assert_eq(overlay.get_parent(), prepare_overlay_host)
	assert_true(overlay.drag_target().visible)
	var overlay_instance_id := overlay.get_instance_id()

	# SceneRouter briefly keeps the committed route alive while the candidate is
	# installed. The persistent surface must move the same overlay to the new
	# screen's host before the old screen is released.
	var combat_screen := _screen(&"RUN_COMBAT", _combat_snapshot())
	assert_not_null(combat_screen)
	if combat_screen == null:
		return
	add_child_autofree(combat_screen)
	await wait_process_frames(2)
	var combat_composition := (
		combat_screen.get_node_or_null(^"Composition") as RunCombatScreen
	)
	assert_not_null(combat_composition)
	if combat_composition == null:
		return
	assert_eq(combat_composition.world_board_mount_error(), &"")
	var combat_shell := (
		combat_composition.find_child("InRunHudShell", true, false)
		as InRunHudShell
	)
	assert_not_null(combat_shell)
	if combat_shell == null:
		return
	var combat_overlay_host := combat_shell.host(
		ProductionLayoutShell.REGION_OVERLAY
	)
	var combat_overlay := surface.ui_overlay()
	assert_not_null(combat_overlay)
	if combat_overlay == null:
		return
	assert_ne(combat_overlay_host, prepare_overlay_host)
	assert_eq(combat_overlay.get_instance_id(), overlay_instance_id)
	assert_eq(combat_overlay.get_parent(), combat_overlay_host)
	assert_false(combat_overlay.drag_target().visible)
	assert_eq(
		combat_overlay.drag_target().mouse_filter,
		Control.MOUSE_FILTER_IGNORE
	)
	prepare_screen.queue_free()
	await wait_process_frames(1)
	assert_true(is_instance_valid(combat_overlay))
	assert_eq(combat_overlay.get_parent(), combat_overlay_host)


func test_combat_event_window_remounts_sprite_and_overlay_from_after_values() -> void:
	var surface := ProductionWorldSurface.new()
	surface.size = Vector2(640.0, 360.0)
	add_child_autofree(surface)
	var coordinator := ProductionViewportCoordinator.new()
	add_child_autofree(coordinator)
	await wait_process_frames(1)
	assert_eq(
		coordinator._mapper.configure(
			WorldViewportPolicy.new().layout_for_window(Vector2i(1920, 1080)),
			100
		),
		&""
	)
	var source := _combat_snapshot_with_unit()
	var screen := _screen(&"RUN_COMBAT", source)
	assert_not_null(screen)
	if screen == null:
		return
	add_child_autofree(screen)
	await wait_process_frames(2)
	var combat := screen.get_node_or_null(^"Composition") as RunCombatScreen
	assert_not_null(combat)
	if combat == null:
		return
	assert_eq(combat.world_board_mount_error(), &"")
	var events: Array = [
		_damage_event(&"u_0000000000000001", 35),
		_heal_event(&"u_0000000000000001", 75),
		_mana_event(&"u_0000000000000001", 50),
		_move_event(
			&"u_0000000000000001",
			Vector2i(1, 5),
			Vector2i(3, 4)
		),
	]

	assert_eq(combat.call(&"_present_world_event_window", events), &"")
	var mounted := surface.snapshot_clone()
	assert_eq(mounted.units.size(), 1)
	if mounted.units.size() != 1:
		return
	var unit := mounted.units[0]
	assert_eq(unit.health, 75)
	assert_eq(unit.mana, 50)
	assert_eq(unit.logical_cell, Vector2i(3, 4))
	var sprite := surface.board_renderer().unit_sprite(&"u_0000000000000001")
	assert_not_null(sprite)
	if sprite != null:
		assert_eq(sprite.get_meta(&"logical_cell"), Vector2i(3, 4))
		assert_eq(
			sprite.position,
			BoardProjection.new().project_cell(Vector2i(3, 4)).round()
		)
	var overlay := surface.ui_overlay()
	assert_not_null(overlay)
	if overlay != null:
		var placement := overlay.placement_for(&"u_0000000000000001")
		assert_not_null(placement)
		if placement != null:
			assert_almost_eq(placement.health_ratio, 0.75, 0.000001)
			assert_almost_eq(placement.mana_ratio, 0.5, 0.000001)

	# The screen projection consumes clones only; its source setup and the
	# committed event payloads stay byte-for-byte equivalent in owned fields.
	assert_eq(source.combat_inspections[0].logical_cell, Vector2i(1, 5))
	assert_eq(int(source.combat_inspections[0].stats.get("health", -1)), 100)
	assert_eq(
		((events[0] as BattleEvent).payload as DamageEventPayload).health_after,
		35
	)
	assert_eq(
		((events[3] as BattleEvent).payload as MoveEventPayload).to_x,
		3
	)


func test_map_detached_compose_retries_clear_when_candidate_enters_tree() -> void:
	await _assert_detached_candidate_clears_old_world(
		&"RUN_MAP", _map_snapshot()
	)


func test_reward_detached_compose_retries_clear_when_candidate_enters_tree() -> void:
	await _assert_detached_candidate_clears_old_world(
		&"RUN_REWARD", _reward_snapshot()
	)


func test_map_clear_missing_surface_reaches_player_visible_status() -> void:
	var screen := _screen(&"RUN_MAP", _map_snapshot())
	assert_not_null(screen)
	if screen == null:
		return
	await wait_process_frames(1)
	add_child_autofree(screen)
	await wait_process_frames(2)
	_assert_clear_error_is_visible(
		screen, WorldBoardMountAdapter.SURFACE_MISSING
	)


func test_reward_clear_ambiguous_surface_reaches_player_visible_status() -> void:
	for index: int in 2:
		var surface := ProductionWorldSurface.new()
		surface.name = "AmbiguousWorldSurface%d" % index
		add_child_autofree(surface)
	await wait_process_frames(1)
	var screen := _screen(&"RUN_REWARD", _reward_snapshot())
	assert_not_null(screen)
	if screen == null:
		return
	await wait_process_frames(1)
	add_child_autofree(screen)
	await wait_process_frames(2)
	_assert_clear_error_is_visible(
		screen, WorldBoardMountAdapter.SURFACE_AMBIGUOUS
	)


func test_prepare_missing_values_never_render_raw_identity_or_dash() -> void:
	var snapshot := _prepare_snapshot()
	var screen := _screen(&"RUN_PREPARE", snapshot)
	assert_not_null(screen)
	if screen == null:
		return
	add_child_autofree(screen)
	await wait_process_frames(2)
	var composition := screen.get_node_or_null(^"Composition") as RunPrepareScreen
	assert_not_null(composition)
	if composition == null:
		return
	var opaque_unit_id := "opaque-unit-instance-id"
	var opaque_item_id := "opaque-item-instance-id"
	assert_ne(
		composition.call(&"_unit_display_name", opaque_unit_id, snapshot),
		opaque_unit_id
	)
	assert_ne(
		composition.call(&"_item_display_name", opaque_item_id, snapshot),
		opaque_item_id
	)
	var metrics := composition.find_child("PrepareMetrics", true, false)
	assert_not_null(metrics)
	if metrics == null:
		return
	var metric_count := 0
	for node: Node in metrics.get_children():
		var label := node as Label
		if label == null:
			continue
		metric_count += 1
		assert_false(label.text.ends_with(" -"))
	assert_eq(metric_count, 4)


func _screen(
	route_kind: StringName,
	snapshot: RunPresentationSnapshot
) -> ProductionScreen:
	var screen := ProductionSceneCatalog.new().instantiate(route_kind)
	if screen == null:
		return null
	var localized := {
		&"error.status.pre_commit": "",
		&"error.presentation.render_failed": ERROR_TEXT,
	}
	assert_eq(
		screen.bind(StagedScreenContext.new(
			route_kind,
			snapshot,
			null,
			&"zh_TW",
			localized
		)),
		&""
	)
	if route_kind == &"RUN_COMBAT":
		var combat := screen.get_node_or_null(^"Composition") as RunCombatScreen
		assert_not_null(combat)
		if combat != null:
			combat.set("_snapshot", snapshot.deep_clone())
			var projection := CombatWorldEventProjection.new()
			assert_eq(
				projection.compose(
					WorldBoardSnapshotFactory.new().build_combat(
						snapshot.deep_clone()
					)
				),
				&""
			)
			combat.set("_combat_world_projection", projection)
			# This focused fixture does not own a playback port, so it cannot call
			# full compose(). Build the same route-local HUD host used by the formal
			# compose path before exercising its mount callsite.
			combat.call(&"_build_hud_shell")
			combat.call_deferred(&"_mount_world_board")
	else:
		assert_eq(
			screen.prepare_live_binding(ProductionLiveScreenContext.new(
				route_kind,
				snapshot,
				null,
				null,
				null,
				LiveScreenIntentPort.new()
			)),
			&""
		)
	return screen


func _assert_detached_candidate_clears_old_world(
	route_kind: StringName,
	snapshot: RunPresentationSnapshot
) -> void:
	var surface := await _surface_with_old_world_snapshot()
	assert_not_null(surface)
	if surface == null:
		return
	var screen := _screen(route_kind, snapshot)
	assert_not_null(screen)
	if screen == null:
		return
	var candidate_instance_id := screen.get_instance_id()
	var composition := screen.get_node_or_null(^"Composition")
	assert_not_null(composition)
	if composition == null:
		screen.free()
		return

	# Mirror prepare_production(): compose detached, then allow the early
	# deferred clear to be consumed before committing the exact candidate.
	await wait_process_frames(1)
	assert_false(screen.is_inside_tree())
	assert_false(bool(composition.get("_world_board_clear_deferred_pending")))
	assert_eq(
		StringName(composition.call(&"world_board_clear_error")), &""
	)
	assert_true(
		surface.snapshot_clone().drag_preview_visible,
		"a detached candidate must not mutate the live world surface"
	)

	add_child_autofree(screen)
	await wait_process_frames(2)
	assert_eq(screen.get_instance_id(), candidate_instance_id)
	assert_false(bool(composition.get("_world_board_clear_deferred_pending")))
	assert_eq(
		StringName(composition.call(&"world_board_clear_error")), &""
	)
	assert_false(
		surface.snapshot_clone().drag_preview_visible,
		"%s ENTER_TREE retry must clear the stale world snapshot" % route_kind
	)
	assert_true(surface.snapshot_clone().units.is_empty())
	assert_true(screen.status_message_text().is_empty())


func _surface_with_old_world_snapshot() -> ProductionWorldSurface:
	var overlay_mount := Control.new()
	overlay_mount.name = "OldWorldOverlayMount"
	add_child_autofree(overlay_mount)
	var surface := ProductionWorldSurface.new()
	surface.name = "OldWorldSurface"
	surface.size = Vector2(640.0, 360.0)
	add_child_autofree(surface)
	await wait_process_frames(1)
	var mapper := WindowCoordinateMapper.new()
	assert_eq(
		mapper.configure(
			WorldViewportPolicy.new().layout_for_window(Vector2i(1920, 1080)),
			100
		),
		&""
	)
	var old_snapshot := WorldBoardSnapshot.new()
	old_snapshot.drag_preview_visible = true
	old_snapshot.drag_preview_cell = Vector2i(2, 1)
	old_snapshot.drag_preview_legal = true
	assert_eq(
		surface.mount_board_snapshot(old_snapshot, mapper, overlay_mount), &""
	)
	assert_true(surface.snapshot_clone().drag_preview_visible)
	return surface


func _assert_surface_missing_is_visible(screen: ProductionScreen) -> void:
	var composition := screen.get_node_or_null(^"Composition")
	assert_not_null(composition)
	if composition != null:
		assert_eq(
			StringName(composition.call(&"world_board_mount_error")),
			WorldBoardMountAdapter.SURFACE_MISSING
		)
	assert_eq(
		StringName(screen.status_report().get("source_code", &"")),
		&"RENDER_FAILED"
	)
	assert_eq(screen.status_message_text(), ERROR_TEXT)
	var status := screen.status_message_control()
	assert_not_null(status)
	if status != null:
		assert_true(status.is_visible_in_tree())


func _assert_clear_error_is_visible(
	screen: ProductionScreen,
	expected_error: StringName
) -> void:
	var composition := screen.get_node_or_null(^"Composition")
	assert_not_null(composition)
	if composition != null:
		assert_eq(
			StringName(composition.call(&"world_board_clear_error")),
			expected_error
		)
	assert_eq(
		StringName(screen.status_report().get("source_code", &"")),
		&"RENDER_FAILED"
	)
	assert_eq(screen.status_message_text(), ERROR_TEXT)
	var status := screen.status_message_control()
	assert_not_null(status)
	if status != null:
		assert_true(status.is_visible_in_tree())


func _prepare_snapshot() -> RunPresentationSnapshot:
	var snapshot := RunPresentationSnapshot.new()
	snapshot.app_phase = &"PREPARE"
	snapshot.roster = _empty_roster()
	var issues: Array[BoardValidationIssue] = []
	snapshot.board_validation_report = BoardValidationReport.new(0, issues)
	return snapshot


func _map_snapshot() -> RunPresentationSnapshot:
	var snapshot := _prepare_snapshot()
	snapshot.app_phase = &"MAP"
	var nodes: Array[MapNodeState] = []
	var edges: Array[MapEdgeState] = []
	var completed_node_ids: Array[String] = []
	snapshot.map = MapState.new(nodes, edges, null, completed_node_ids)
	return snapshot


func _reward_snapshot() -> RunPresentationSnapshot:
	return CompositionSupport.reward_snapshot(
		PendingRewardState.Phase.CHOOSING
	)


func _combat_snapshot() -> RunPresentationSnapshot:
	var snapshot := RunPresentationSnapshot.new()
	snapshot.app_phase = &"COMBAT"
	var nodes: Array[MapNodeState] = []
	var edges: Array[MapEdgeState] = []
	var completed_node_ids: Array[String] = []
	snapshot.map = MapState.new(nodes, edges, null, completed_node_ids)
	var inspection := CombatUnitInspectionSnapshot.new()
	inspection.unit_serial = 1
	inspection.presentation_instance_id = &"u_0000000000000001"
	inspection.source_id = &"unit.slice_player_00"
	inspection.side_id = &"player"
	inspection.logical_cell = Vector2i(1, 5)
	inspection.stats = {
		"star": 1,
		"health": 100,
		"start_mana": 10,
		"max_mana": 100,
	}
	snapshot.combat_inspections.append(inspection)
	return snapshot


func _combat_snapshot_with_unit() -> RunPresentationSnapshot:
	return _combat_snapshot()


func _damage_event(target_id: StringName, health_after: int) -> BattleEvent:
	var event := BattleEvent.new()
	event.type = &"damage"
	event.target_instance_ids.assign([target_id])
	var payload := DamageEventPayload.new()
	payload.damage_type = &"physical"
	payload.health_after = health_after
	event.payload = payload
	return event


func _heal_event(target_id: StringName, health_after: int) -> BattleEvent:
	var event := BattleEvent.new()
	event.type = &"heal"
	event.target_instance_ids.assign([target_id])
	var payload := HealEventPayload.new()
	payload.health_after = health_after
	event.payload = payload
	return event


func _mana_event(target_id: StringName, mana_after: int) -> BattleEvent:
	var event := BattleEvent.new()
	event.type = &"mana"
	event.target_instance_ids.assign([target_id])
	var payload := ManaEventPayload.new()
	payload.reason = &"effect"
	payload.mana_after = mana_after
	event.payload = payload
	return event


func _move_event(
	source_id: StringName,
	from_cell: Vector2i,
	to_cell: Vector2i
) -> BattleEvent:
	var event := BattleEvent.new()
	event.type = &"move"
	event.source_instance_id = OptionalStringNameValue.of(source_id)
	var payload := MoveEventPayload.new()
	payload.from_x = from_cell.x
	payload.from_y = from_cell.y
	payload.to_x = to_cell.x
	payload.to_y = to_cell.y
	event.payload = payload
	return event


func _empty_roster() -> RosterState:
	var placements: Array[BoardPlacementState] = []
	var bench: Array[String] = []
	var units: Array[UnitInstance] = []
	var items: Array[ItemInstanceState] = []
	var inventory: Array[String] = []
	var overflow: Array[String] = []
	var relics: Array[RelicSlotState] = []
	return RosterState.new(
		BoardState.new(placements),
		bench,
		units,
		items,
		inventory,
		overflow,
		relics
	)
