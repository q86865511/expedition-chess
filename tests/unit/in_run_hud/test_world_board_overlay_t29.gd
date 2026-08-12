extends GutTest

const SurfaceScript = preload(
	"res://presentation/viewport/production_world_surface.gd"
)
const SnapshotScript = preload(
	"res://presentation/viewport/world_board_snapshot.gd"
)
const UnitSnapshotScript = preload(
	"res://presentation/viewport/world_board_unit_snapshot.gd"
)
const PolicyScript = preload(
	"res://presentation/viewport/world_viewport_policy.gd"
)
const MapperScript = preload(
	"res://presentation/viewport/window_coordinate_mapper.gd"
)
const CoordinatorScript = preload(
	"res://presentation/viewport/production_viewport_coordinator.gd"
)
const MountAdapterScript = preload(
	"res://presentation/viewport/world_board_mount_adapter.gd"
)
const ProductionFrames = preload(
	"res://assets/production/units/slice_player_00.tres"
)

const OUTPUT_SIZES: Array[Vector2i] = [
	Vector2i(1280, 720),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440),
]


func test_group_mount_places_fixed_pixel_hud_above_world_and_vfx() -> void:
	var overlay_mount := Control.new()
	overlay_mount.add_to_group(SurfaceScript.OVERLAY_MOUNT_GROUP)
	add_child_autofree(overlay_mount)
	var surface := SurfaceScript.new()
	surface.size = Vector2(640.0, 360.0)
	add_child_autofree(surface)
	await get_tree().process_frame
	assert_true(surface.is_in_group(SurfaceScript.MOUNT_GROUP))

	var snapshot := _snapshot()
	var policy := PolicyScript.new()
	var mapper := MapperScript.new()
	for output_size: Vector2i in OUTPUT_SIZES:
		var layout: Dictionary = policy.layout_for_window(output_size)
		assert_eq(
			mapper.configure(layout, 100),
			&""
		)
		assert_eq(surface.mount_board_snapshot(snapshot, mapper), &"")
		var overlay: WorldBoardUiOverlay = surface.ui_overlay()
		assert_not_null(overlay)
		assert_eq(overlay.get_parent(), overlay_mount)
		assert_eq(overlay.z_index, overlay.OVERLAY_Z_INDEX)
		var placement := overlay.placement_for(&"visible")
		assert_not_null(placement)
		assert_eq(placement.health_rect.size, Vector2(40.0, 4.0))
		assert_eq(placement.mana_rect.size, Vector2(40.0, 3.0))
		var world_foot := BoardProjection.new().project_cell(Vector2i(2, 1))
		var expected_screen_head := mapper.world_to_screen(
			world_foot + Vector2(0.0, -56.0)
		).round()
		assert_eq(
			placement.health_rect.position,
			expected_screen_head + Vector2(-20.0, -6.0),
			"health anchor must project the sprite head before fixed-pixel layout"
		)
		assert_eq(
			placement.mana_rect.position,
			expected_screen_head + Vector2(-20.0, -1.0),
			"mana anchor must project the sprite head before fixed-pixel layout"
		)
		assert_eq(
			placement.screen_foot_position.y
				- placement.health_rect.position.y,
			56.0 * float(layout["integer_scale"]) + 6.0,
			"head distance must follow the 2x/3x/4x world scale"
		)
		assert_eq(
			placement.screen_foot_position,
			placement.screen_foot_position.round()
		)


func test_overlay_placement_order_matches_renderer_logical_depth() -> void:
	var snapshot := SnapshotScript.new()
	# Deliberately append in the opposite order from projected depth.
	snapshot.append_unit(_unit(&"near", Vector2i(7, 0)))
	snapshot.append_unit(_unit(&"far_right", Vector2i(4, 7)))
	snapshot.append_unit(_unit(&"far_left", Vector2i(1, 7)))
	assert_true(snapshot.is_valid())
	var mapper := MapperScript.new()
	assert_eq(
		mapper.configure(
			PolicyScript.new().layout_for_window(Vector2i(1920, 1080)),
			100
		),
		&""
	)
	var mapped := WorldBoardOverlayMapper.new().map_snapshot(
		snapshot,
		BoardProjection.new(),
		mapper
	)
	assert_true(mapped.error.is_empty())
	var mapped_ids: Array[StringName] = []
	for placement: WorldBoardOverlayPlacement in mapped.placements:
		mapped_ids.append(placement.presentation_instance_id)

	var renderer := WorldBoardRenderer.new()
	add_child_autofree(renderer)
	assert_eq(renderer.render_snapshot(snapshot), &"")
	assert_eq(mapped_ids, renderer.ordered_unit_ids())
	assert_eq(mapped_ids, [&"far_left", &"far_right", &"near"])


func test_duplicate_logical_cells_fail_snapshot_and_overlay_closed() -> void:
	var snapshot := SnapshotScript.new()
	snapshot.append_unit(_unit(&"first", Vector2i(3, 2)))
	snapshot.append_unit(_unit(&"second", Vector2i(3, 2)))
	assert_false(snapshot.is_valid())
	var mapper := MapperScript.new()
	assert_eq(
		mapper.configure(
			PolicyScript.new().layout_for_window(Vector2i(1920, 1080)),
			100
		),
		&""
	)
	var mapped := WorldBoardOverlayMapper.new().map_snapshot(
		snapshot,
		BoardProjection.new(),
		mapper
	)
	assert_eq(mapped.error, WorldBoardOverlayMapper.INVALID_SNAPSHOT)
	assert_true(mapped.placements.is_empty())


func test_health_mana_selection_and_drag_visibility_come_from_one_snapshot_clone() -> void:
	var overlay_mount := Control.new()
	add_child_autofree(overlay_mount)
	var surface := SurfaceScript.new()
	add_child_autofree(surface)
	await get_tree().process_frame
	var mapper := MapperScript.new()
	assert_eq(
		mapper.configure(
			PolicyScript.new().layout_for_window(Vector2i(1920, 1080)),
			100
		),
		&""
	)
	var snapshot := _snapshot()
	assert_eq(
		surface.mount_board_snapshot(snapshot, mapper, overlay_mount),
		&""
	)
	var overlay: WorldBoardUiOverlay = surface.ui_overlay()
	assert_true(overlay.hud_visible_for(&"visible"))
	assert_true(overlay.selection_visible_for(&"visible"))
	assert_false(overlay.hud_visible_for(&"hidden"))
	assert_false(overlay.selection_visible_for(&"hidden"))
	assert_true(overlay.drag_preview_visible())

	# Both renderer and overlay own clones; later caller mutation is isolated.
	snapshot.units[0].logical_cell = Vector2i(7, 7)
	assert_eq(surface.snapshot_clone().units[0].logical_cell, Vector2i(2, 1))
	assert_eq(overlay.snapshot_clone().units[0].logical_cell, Vector2i(2, 1))


func test_world_overlay_is_below_transition_menu_and_modal_input_layers() -> void:
	var screen_root := Control.new()
	screen_root.size = Vector2(1920.0, 1080.0)
	add_child_autofree(screen_root)

	# Mirror the production hierarchy: Composition has z=1, while the shared
	# layout overlay (system menu) and direct modal are siblings on the screen.
	var composition := Control.new()
	composition.name = "Composition"
	composition.z_index = 1
	composition.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen_root.add_child(composition)
	var hud_overlay_mount := Control.new()
	hud_overlay_mount.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	composition.add_child(hud_overlay_mount)

	var world_overlay := WorldBoardUiOverlay.new()
	world_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud_overlay_mount.add_child(world_overlay)
	var transition_banner := Label.new()
	transition_banner.name = "RunTransitionBanner"
	transition_banner.z_index = 50
	transition_banner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	transition_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_overlay_mount.add_child(transition_banner)

	var system_menu := SystemMenuOverlay.new()
	system_menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen_root.add_child(system_menu)
	system_menu.configure({
		&"screen.run_container.title": "menu",
		&"menu.continue": "continue",
		&"menu.settings": "settings",
		&"run.menu": "return",
		&"menu.exit": "exit",
	})
	var modal := PanelContainer.new()
	modal.name = "ConfirmationModal"
	modal.z_index = 100
	modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal.mouse_filter = Control.MOUSE_FILTER_STOP
	screen_root.add_child(modal)
	await get_tree().process_frame

	var drag_target := world_overlay.drag_target()
	drag_target.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	drag_target.mouse_filter = Control.MOUSE_FILTER_STOP
	assert_true(system_menu.open())
	await get_tree().process_frame
	var menu_surface := system_menu.get_node_or_null(^"Surface") as Control
	assert_not_null(menu_surface)
	if menu_surface == null:
		return
	assert_true(
		drag_target.get_global_rect().intersects(menu_surface.get_global_rect()),
		"the z/input assertion must exercise the same central pixels"
	)
	assert_eq(drag_target.mouse_filter, Control.MOUSE_FILTER_STOP)
	assert_eq(menu_surface.mouse_filter, Control.MOUSE_FILTER_STOP)
	assert_lt(
		_tree_effective_z_index(world_overlay),
		_tree_effective_z_index(transition_banner),
		"transition banner must paint above health bars and drag cues"
	)
	assert_lt(
		_tree_effective_z_index(drag_target),
		_tree_effective_z_index(menu_surface),
		"system menu must win GUI picking over the overlapping board target"
	)
	assert_lt(
		_tree_effective_z_index(world_overlay),
		_tree_effective_z_index(modal),
		"confirmation modal must remain the top input surface"
	)


func _tree_effective_z_index(item: CanvasItem) -> int:
	if item == null:
		return 0
	var effective := item.z_index
	if not item.z_as_relative:
		return effective
	var parent := item.get_parent() as CanvasItem
	if parent != null:
		effective += _tree_effective_z_index(parent)
	return effective


func test_overlay_is_recreated_after_its_route_mount_is_destroyed() -> void:
	var first_mount := Control.new()
	add_child_autofree(first_mount)
	var surface := SurfaceScript.new()
	add_child_autofree(surface)
	await get_tree().process_frame
	var mapper := MapperScript.new()
	assert_eq(
		mapper.configure(
			PolicyScript.new().layout_for_window(Vector2i(1920, 1080)),
			100
		),
		&""
	)
	assert_eq(surface.mount_board_snapshot(_snapshot(), mapper, first_mount), &"")
	var first_overlay: WorldBoardUiOverlay = surface.ui_overlay()
	assert_not_null(first_overlay)
	first_mount.queue_free()
	await get_tree().process_frame
	assert_false(is_instance_valid(first_overlay))

	var second_mount := Control.new()
	add_child_autofree(second_mount)
	assert_eq(surface.bind_overlay_mount(second_mount, mapper), &"")
	var second_overlay: WorldBoardUiOverlay = surface.ui_overlay()
	assert_not_null(second_overlay)
	assert_eq(second_overlay.get_parent(), second_mount)


func test_persistent_surface_prepare_to_combat_reparents_and_disables_drag() -> void:
	var surface := SurfaceScript.new()
	surface.size = Vector2(640.0, 360.0)
	add_child_autofree(surface)
	var coordinator := CoordinatorScript.new()
	add_child_autofree(coordinator)

	var prepare_route := Control.new()
	prepare_route.size = Vector2(1920.0, 1080.0)
	add_child_autofree(prepare_route)
	var prepare_mount := Control.new()
	prepare_mount.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	prepare_route.add_child(prepare_mount)
	await get_tree().process_frame
	assert_eq(
		coordinator._mapper.configure(
			PolicyScript.new().layout_for_window(Vector2i(1920, 1080)),
			100
		),
		&""
	)
	var player_half_validator := func(cell: Vector2i) -> bool:
		return cell.x >= 0 and cell.x < 8 and cell.y >= 0 and cell.y < 4
	var prepare_snapshot := _snapshot()
	prepare_snapshot.drag_preview_visible = false
	assert_eq(
		MountAdapterScript.mount(
			get_tree(),
			prepare_snapshot,
			player_half_validator,
			prepare_mount
		),
		&""
	)
	var overlay := surface.ui_overlay()
	assert_not_null(overlay)
	if overlay == null:
		return
	var overlay_instance_id := overlay.get_instance_id()
	var target := overlay.drag_target()
	assert_true(target.visible)
	assert_eq(target.mouse_filter, Control.MOUSE_FILTER_STOP)
	var mapper := coordinator.coordinate_mapper_clone()
	var target_screen := mapper.world_to_screen(
		BoardProjection.new().project_cell(Vector2i(3, 2))
	)
	var target_local := (
		target.get_global_transform_with_canvas().affine_inverse()
		* target_screen
	)
	var payload := {
		"kind": &"prepare_unit",
		"unit_instance_id": "visible",
	}
	assert_true(target._can_drop_data(target_local, payload))

	var combat_route := Control.new()
	combat_route.size = Vector2(1920.0, 1080.0)
	add_child_autofree(combat_route)
	var combat_mount := Control.new()
	combat_mount.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	combat_route.add_child(combat_mount)
	prepare_route.queue_free()
	var combat_snapshot := _snapshot()
	combat_snapshot.drag_preview_visible = false
	assert_eq(
		MountAdapterScript.mount(
			get_tree(),
			combat_snapshot,
			Callable(),
			combat_mount
		),
		&""
	)
	var combat_overlay := surface.ui_overlay()
	assert_not_null(combat_overlay)
	if combat_overlay == null:
		return
	assert_eq(combat_overlay.get_instance_id(), overlay_instance_id)
	assert_eq(combat_overlay.get_parent(), combat_mount)
	assert_not_null(combat_overlay.placement_for(&"visible"))
	var combat_target := combat_overlay.drag_target()
	assert_false(combat_target.visible)
	assert_eq(combat_target.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	var combat_target_local := (
		combat_target.get_global_transform_with_canvas().affine_inverse()
		* target_screen
	)
	assert_false(
		combat_target._can_drop_data(combat_target_local, payload),
		"empty combat validator must reject instead of inheriting prepare"
	)
	await get_tree().process_frame
	assert_true(is_instance_valid(combat_overlay))
	assert_eq(combat_overlay.get_parent(), combat_mount)


func test_failed_route_reparent_rolls_overlay_back_and_disables_input() -> void:
	var first_mount := Control.new()
	first_mount.size = Vector2(1920.0, 1080.0)
	add_child_autofree(first_mount)
	var second_mount := Control.new()
	second_mount.size = Vector2(1920.0, 1080.0)
	add_child_autofree(second_mount)
	var surface := SurfaceScript.new()
	add_child_autofree(surface)
	await get_tree().process_frame
	var mapper := MapperScript.new()
	assert_eq(
		mapper.configure(
			PolicyScript.new().layout_for_window(Vector2i(1920, 1080)),
			100
		),
		&""
	)
	var player_half_validator := func(cell: Vector2i) -> bool:
		return cell.x >= 0 and cell.x < 8 and cell.y >= 0 and cell.y < 4
	assert_eq(
		surface.mount_board_snapshot(
			_snapshot(),
			mapper,
			first_mount,
			player_half_validator
		),
		&""
	)
	var overlay := surface.ui_overlay()
	assert_not_null(overlay)
	if overlay == null:
		return
	surface._projection = null
	assert_eq(
		surface.mount_board_snapshot(
			_snapshot(),
			mapper,
			second_mount,
			Callable()
		),
		WorldBoardOverlayMapper.INVALID_SNAPSHOT
	)
	assert_eq(surface.ui_overlay(), overlay)
	assert_eq(overlay.get_parent(), first_mount)
	assert_false(overlay.drag_target().visible)
	assert_eq(
		overlay.drag_target().mouse_filter,
		Control.MOUSE_FILTER_IGNORE
	)


func test_projected_drag_uses_inverse_mapping_and_relays_one_typed_drop() -> void:
	var overlay_mount := Control.new()
	overlay_mount.size = Vector2(1920.0, 1080.0)
	add_child_autofree(overlay_mount)
	var surface := SurfaceScript.new()
	add_child_autofree(surface)
	await get_tree().process_frame
	var mapper := MapperScript.new()
	assert_eq(
		mapper.configure(
			PolicyScript.new().layout_for_window(Vector2i(1920, 1080)),
			100
		),
		&""
	)
	var player_half_validator := func(cell: Vector2i) -> bool:
		return cell.x >= 0 and cell.x < 8 and cell.y >= 0 and cell.y < 4
	assert_eq(
		surface.mount_board_snapshot(
			_snapshot(),
			mapper,
			overlay_mount,
			player_half_validator
		),
		&""
	)
	var target := surface.ui_overlay().drag_target()
	assert_not_null(target)
	if target == null:
		return
	var target_screen := mapper.world_to_screen(
		BoardProjection.new().project_cell(Vector2i(5, 3))
	)
	var target_local := (
		target.get_global_transform_with_canvas().affine_inverse()
		* target_screen
	)
	var payload := {
		"kind": &"prepare_unit",
		"unit_instance_id": "visible",
		"source_kind": &"board",
		"source_cell": Vector2i(2, 1),
		"source_slot": -1,
	}
	assert_true(target._can_drop_data(target_local, payload))
	assert_true(surface.ui_overlay().drag_preview_visible())
	var preview := surface.ui_overlay().mapped_snapshot_clone()
	assert_eq(preview.drag_preview_source_kind, &"board")
	assert_eq(preview.drag_preview_source_cell, Vector2i(2, 1))
	assert_eq(preview.drag_preview_target_cell, Vector2i(5, 3))
	assert_eq(preview.drag_preview_source_instance_id, &"visible")
	assert_eq(preview.drag_preview_target_instance_id, &"hidden")
	assert_true(preview.drag_preview_swap)
	assert_eq(
		preview.drag_preview_arrow_start,
		mapper.world_to_screen(
			BoardProjection.new().project_cell(Vector2i(2, 1))
		).round()
	)
	assert_eq(preview.drag_preview_arrow_end, target_screen.round())
	watch_signals(surface)
	target._drop_data(target_local, payload)
	assert_signal_emitted_with_parameters(
		surface,
		"unit_dropped",
		["visible", Vector2i(5, 3)]
	)
	assert_false(surface.ui_overlay().drag_preview_visible())


func test_resize_in_place_refreshes_overlay_and_projected_drag_mapper() -> void:
	var host := Node.new()
	add_child_autofree(host)
	var world_container := SubViewportContainer.new()
	world_container.name = "WorldViewportContainer"
	host.add_child(world_container)
	var world_viewport := SubViewport.new()
	world_viewport.name = "WorldViewport"
	world_container.add_child(world_viewport)
	var surface := SurfaceScript.new()
	surface.size = Vector2(640.0, 360.0)
	world_viewport.add_child(surface)

	var ui_layer := CanvasLayer.new()
	ui_layer.name = "UiLayer"
	host.add_child(ui_layer)
	var ui_root := Control.new()
	ui_root.name = "UiRoot"
	ui_layer.add_child(ui_root)
	var presentation_host := Control.new()
	presentation_host.name = "PresentationHost"
	ui_root.add_child(presentation_host)
	var overlay_mount := Control.new()
	overlay_mount.name = "OverlayMount"
	overlay_mount.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay_mount.add_to_group(SurfaceScript.OVERLAY_MOUNT_GROUP)
	presentation_host.add_child(overlay_mount)

	var coordinator := CoordinatorScript.new()
	coordinator.name = "ViewportCoordinator"
	host.add_child(coordinator)
	await get_tree().process_frame
	assert_eq(coordinator.synchronize(Vector2i(1280, 720)), &"")
	var player_half_validator := func(cell: Vector2i) -> bool:
		return cell.x >= 0 and cell.x < 8 and cell.y >= 0 and cell.y < 4
	assert_eq(
		surface.mount_board_snapshot(
			_snapshot(),
			coordinator.coordinate_mapper_clone(),
			overlay_mount,
			player_half_validator
		),
		&""
	)
	var overlay := surface.ui_overlay()
	assert_not_null(overlay)
	if overlay == null:
		return
	var before := overlay.placement_for(&"visible").screen_foot_position
	var same_overlay_instance_id := overlay.get_instance_id()

	assert_eq(coordinator.synchronize(Vector2i(2560, 1440)), &"")
	assert_eq(surface.ui_overlay().get_instance_id(), same_overlay_instance_id)
	var resized_mapper := coordinator.coordinate_mapper_clone()
	var expected_after := resized_mapper.world_to_screen(
		BoardProjection.new().project_cell(Vector2i(2, 1))
	).round()
	var after := surface.ui_overlay().placement_for(
		&"visible"
	).screen_foot_position
	assert_ne(after, before)
	assert_eq(after, expected_after)

	var target := surface.ui_overlay().drag_target()
	assert_not_null(target)
	if target == null:
		return
	var target_screen := resized_mapper.world_to_screen(
		BoardProjection.new().project_cell(Vector2i(3, 2))
	)
	var target_local := (
		target.get_global_transform_with_canvas().affine_inverse()
		* target_screen
	)
	var payload := {
		"kind": &"prepare_unit",
		"unit_instance_id": "visible",
	}
	assert_true(target._can_drop_data(target_local, payload))
	watch_signals(surface)
	target._drop_data(target_local, payload)
	assert_signal_emitted_with_parameters(
		surface,
		"unit_dropped",
		["visible", Vector2i(3, 2)]
	)

	# UI scale changes use the same event-driven mapper refresh contract.
	assert_eq(coordinator.apply_ui_scale(150), &"")
	var scaled_mapper := coordinator.coordinate_mapper_clone()
	assert_not_null(scaled_mapper)
	assert_eq(scaled_mapper.ui_scale_percent(), 150)
	assert_eq(
		surface.ui_overlay().placement_for(&"visible").screen_foot_position,
		scaled_mapper.world_to_screen(
			BoardProjection.new().project_cell(Vector2i(2, 1))
		).round()
	)

	# A failed overlay re-projection must be observable and must disable the
	# stale drag hitbox rather than leaving the old mapper active.
	surface._projection = null
	assert_eq(
		coordinator.synchronize(Vector2i(1280, 720)),
		WorldBoardOverlayMapper.INVALID_SNAPSHOT
	)
	assert_null(surface.ui_overlay().placement_for(&"visible"))
	assert_false(surface.ui_overlay().drag_target().visible)

	# Recreated surfaces may receive a resize mapper before mounting a snapshot;
	# that push is a no-op success and the stored clone supports the later mount.
	surface.queue_free()
	await get_tree().process_frame
	var replacement := SurfaceScript.new()
	replacement.size = Vector2(640.0, 360.0)
	world_viewport.add_child(replacement)
	await get_tree().process_frame
	assert_eq(coordinator.synchronize(Vector2i(2560, 1440)), &"")
	assert_eq(
		replacement.mount_board_snapshot(
			_snapshot(),
			null,
			overlay_mount,
			player_half_validator
		),
		&""
	)


func test_mount_adapter_requires_exactly_one_surface_and_returns_surface_error() -> void:
	assert_eq(
		MountAdapterScript.mount(get_tree(), _snapshot()),
		MountAdapterScript.SURFACE_MISSING
	)
	var surface := SurfaceScript.new()
	add_child_autofree(surface)
	var coordinator := CoordinatorScript.new()
	add_child_autofree(coordinator)
	await get_tree().process_frame
	assert_eq(
		coordinator._mapper.configure(
			PolicyScript.new().layout_for_window(Vector2i(1920, 1080)),
			100
		),
		&""
	)
	var invalid_snapshot := SnapshotScript.new()
	invalid_snapshot.drag_preview_visible = true
	assert_eq(
		MountAdapterScript.mount(get_tree(), invalid_snapshot),
		SurfaceScript.INVALID_SNAPSHOT
	)
	var duplicate := SurfaceScript.new()
	add_child_autofree(duplicate)
	await get_tree().process_frame
	assert_eq(
		MountAdapterScript.mount(get_tree(), _snapshot()),
		MountAdapterScript.SURFACE_AMBIGUOUS
	)


func test_mount_before_coordinator_sync_fails_with_mapper_configuration_error() -> void:
	var surface := SurfaceScript.new()
	add_child_autofree(surface)
	var coordinator := CoordinatorScript.new()
	add_child_autofree(coordinator)
	await get_tree().process_frame
	assert_false(coordinator.coordinate_mapper_ready())
	assert_null(coordinator.coordinate_mapper_clone())
	assert_eq(
		MountAdapterScript.mount(get_tree(), _snapshot()),
		MapperScript.NOT_CONFIGURED
	)
	assert_true(surface.snapshot_clone().units.is_empty())
	assert_null(surface.ui_overlay())
	assert_eq(
		surface.mount_board_snapshot(_snapshot(), MapperScript.new()),
		MapperScript.NOT_CONFIGURED
	)


func _snapshot() -> WorldBoardSnapshot:
	var snapshot := SnapshotScript.new()
	var visible := _unit(&"visible", Vector2i(2, 1))
	visible.selected = true
	snapshot.append_unit(visible)
	var hidden := _unit(&"hidden", Vector2i(5, 3))
	hidden.overlay_visible = false
	snapshot.append_unit(hidden)
	snapshot.drag_preview_visible = true
	snapshot.drag_preview_cell = Vector2i(4, 2)
	snapshot.drag_preview_legal = true
	return snapshot


func _unit(
	presentation_id: StringName,
	logical_cell: Vector2i
) -> WorldBoardUnitSnapshot:
	var unit := UnitSnapshotScript.new()
	unit.presentation_instance_id = presentation_id
	unit.logical_cell = logical_cell
	unit.sprite_frames = ProductionFrames
	unit.animation = &"idle_n_star1"
	unit.health = 45
	unit.max_health = 90
	unit.mana = 20
	unit.max_mana = 80
	return unit
