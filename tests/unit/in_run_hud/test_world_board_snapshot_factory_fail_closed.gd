extends GutTest

const VALID_DEF: StringName = &"unit.slice_player_00"
const SECOND_VALID_DEF: StringName = &"unit.slice_player_01"
const MISSING_VISUAL_DEF: StringName = &"unit.factory_missing_visual"
const MISSING_ANIMATION_DEF: StringName = &"unit.factory_missing_animation"


class VisualFixture:
	extends ProductionUnitVisualCatalog

	const Frames = preload(
		"res://assets/production/units/slice_player_00.tres"
	)

	var _frames_without_idle := SpriteFrames.new()


	func _init() -> void:
		_frames_without_idle.add_animation(&"walk")


	func try_sprite_frames(unit_def_id: StringName) -> SpriteFrames:
		if unit_def_id == &"unit.factory_missing_visual":
			return null
		if unit_def_id == &"unit.factory_missing_animation":
			return _frames_without_idle
		return Frames


func test_prepare_missing_visual_keeps_invalid_unit_and_stops_build() -> void:
	var factory := WorldBoardSnapshotFactory.new()
	factory.set(&"_visuals", VisualFixture.new())
	var definitions: Array[StringName] = [
		VALID_DEF,
		MISSING_VISUAL_DEF,
		SECOND_VALID_DEF,
	]
	var source := _prepare_snapshot(definitions)

	var built := factory.build_prepare(source, source.roster.board)

	assert_eq(built.units.size(), 2)
	assert_true(built.units[0].is_valid())
	assert_eq(built.units[1].presentation_instance_id, &"prepare.factory.1")
	assert_null(built.units[1].sprite_frames)
	assert_false(built.units[1].is_valid())
	assert_false(built.is_valid())


func test_combat_missing_animation_keeps_invalid_unit_and_stops_build() -> void:
	var factory := WorldBoardSnapshotFactory.new()
	factory.set(&"_visuals", VisualFixture.new())
	var definitions: Array[StringName] = [
		VALID_DEF,
		MISSING_ANIMATION_DEF,
		SECOND_VALID_DEF,
	]

	var built := factory.build_combat(_combat_snapshot(definitions))

	assert_eq(built.units.size(), 2)
	assert_true(built.units[0].is_valid())
	assert_eq(built.units[1].presentation_instance_id, &"combat.factory.1")
	assert_not_null(built.units[1].sprite_frames)
	assert_true(built.units[1].animation.is_empty())
	assert_false(built.units[1].is_valid())
	assert_false(built.is_valid())


func test_required_null_sources_return_invalid_sentinel_snapshots() -> void:
	var factory := WorldBoardSnapshotFactory.new()
	var without_roster := RunPresentationSnapshot.new()
	var one_definition: Array[StringName] = [VALID_DEF]
	var prepare_source := _prepare_snapshot(one_definition)
	var empty_placements: Array[BoardPlacementState] = []
	var empty_board := BoardState.new(empty_placements)
	var cases: Array[WorldBoardSnapshot] = [
		factory.build_prepare(null, prepare_source.roster.board),
		factory.build_prepare(without_roster, empty_board),
		factory.build_prepare(prepare_source, null),
		factory.build_combat(null),
	]

	for built: WorldBoardSnapshot in cases:
		_assert_invalid_sentinel(built)


func test_prepare_null_canonical_entries_fail_the_whole_build() -> void:
	var factory := WorldBoardSnapshotFactory.new()
	var definitions: Array[StringName] = [VALID_DEF]
	var null_placement := _prepare_snapshot(definitions)
	null_placement.roster.board.placements.append(null)
	var null_unit := _prepare_snapshot(definitions)
	null_unit.roster.unit_instances.append(null)
	var null_preview := _prepare_snapshot(definitions)
	null_preview.unit_stats_previews.append(null)
	var sources: Array[RunPresentationSnapshot] = [
		null_placement,
		null_unit,
		null_preview,
	]

	for source: RunPresentationSnapshot in sources:
		var built := factory.build_prepare(source, source.roster.board)
		assert_false(built.is_valid())
		assert_false(built.units.is_empty())


func test_combat_null_inspection_invalidates_prior_units_in_the_build() -> void:
	var definitions: Array[StringName] = [VALID_DEF, SECOND_VALID_DEF]
	var source := _combat_snapshot(definitions)
	source.combat_inspections.insert(1, null)

	var built := WorldBoardSnapshotFactory.new().build_combat(source)

	assert_eq(built.units.size(), 2)
	assert_true(built.units[0].is_valid())
	assert_false(built.units[1].is_valid())
	assert_false(built.is_valid())


func test_combat_empty_inspections_return_invalid_typed_sentinel() -> void:
	var source := RunPresentationSnapshot.new()
	source.app_phase = &"COMBAT"
	source.view = _empty_combat_view(ResolutionState.Kind.COMBAT_PENDING)
	assert_eq(
		source.view.resolution_kind,
		ResolutionState.Kind.COMBAT_PENDING,
		"fixture must represent active COMBAT_PENDING, not summary recovery"
	)

	var built := WorldBoardSnapshotFactory.new().build_combat(source)

	_assert_invalid_sentinel(built)


func test_committed_summary_recovery_allows_a_genuinely_empty_world() -> void:
	var source := RunPresentationSnapshot.new()
	source.app_phase = &"COMBAT"
	source.view = _empty_combat_view(
		ResolutionState.Kind.BATTLE_RESULT_PENDING
	)

	var built := WorldBoardSnapshotFactory.new().build_combat(source)

	assert_true(built.is_valid())
	assert_true(built.units.is_empty())


func _empty_combat_view(
	resolution_kind: ResolutionState.Kind
) -> RunViewState:
	var no_placements: Array[BoardPlacementState] = []
	var no_strings: Array[String] = []
	var no_units: Array[UnitInstance] = []
	var no_relics: Array[RelicSlotState] = []
	return RunViewState.new(
		U64Bits.zero(),
		"run.summary.reload",
		"manifest.summary.reload",
		1,
		OptionalStringValue.new("node.summary.reload"),
		RunState.RunPhase.COMBAT,
		100,
		EconomyViewState.new(0, 1, 0, 0, 0),
		RosterViewState.new(
			BoardState.new(no_placements),
			no_strings,
			no_units,
			no_strings,
			no_strings,
			no_relics
		),
		resolution_kind
	)


func test_combat_missing_stable_presentation_identity_fails_closed() -> void:
	var definitions: Array[StringName] = [VALID_DEF]
	var source := _combat_snapshot(definitions)
	source.combat_inspections[0].presentation_instance_id = &""

	var built := WorldBoardSnapshotFactory.new().build_combat(source)

	assert_eq(built.units.size(), 1)
	assert_eq(built.units[0].presentation_instance_id, &"")
	assert_false(built.units[0].is_valid())
	assert_false(built.is_valid())


func test_invalid_factory_snapshot_clears_previous_surface_renderer() -> void:
	var surface := ProductionWorldSurface.new()
	surface.size = Vector2(640.0, 360.0)
	add_child_autofree(surface)
	var overlay_mount := Control.new()
	overlay_mount.size = Vector2(1920.0, 1080.0)
	add_child_autofree(overlay_mount)
	await get_tree().process_frame
	var mapper := WindowCoordinateMapper.new()
	assert_eq(
		mapper.configure(
			WorldViewportPolicy.new().layout_for_window(Vector2i(1920, 1080)),
			100
		),
		&""
	)
	var valid_definitions: Array[StringName] = [VALID_DEF]
	var valid_snapshot := WorldBoardSnapshotFactory.new().build_combat(
		_combat_snapshot(valid_definitions)
	)
	var allow_all_cells := func(_cell: Vector2i) -> bool:
		return true
	assert_true(valid_snapshot.is_valid())
	assert_eq(
		surface.mount_board_snapshot(
			valid_snapshot,
			mapper,
			overlay_mount,
			allow_all_cells
		),
		&""
	)
	assert_not_null(
		surface.board_renderer().unit_sprite(&"combat.factory.0")
	)
	var overlay := surface.ui_overlay()
	assert_not_null(overlay)
	var drag_target: WorldBoardDragTarget = null
	if overlay != null:
		assert_false(overlay.snapshot_clone().units.is_empty())
		assert_false(overlay.mapped_snapshot_clone().placements.is_empty())
		assert_not_null(overlay.placement_for(&"combat.factory.0"))
		drag_target = overlay.drag_target()
		assert_not_null(drag_target)
		if drag_target != null:
			assert_true(drag_target.visible)
			assert_eq(
				drag_target.mouse_filter,
				Control.MOUSE_FILTER_STOP
			)

	var invalid_snapshot := WorldBoardSnapshotFactory.new().build_combat(null)
	assert_false(invalid_snapshot.is_valid())
	assert_eq(
		surface.mount_board_snapshot(invalid_snapshot, mapper),
		ProductionWorldSurface.INVALID_SNAPSHOT
	)
	assert_true(surface.snapshot_clone().units.is_empty())
	assert_null(surface.board_renderer().unit_sprite(&"combat.factory.0"))
	assert_false(surface.board_renderer().visible)
	if overlay != null:
		assert_true(overlay.snapshot_clone().units.is_empty())
		assert_true(overlay.mapped_snapshot_clone().placements.is_empty())
		assert_null(overlay.placement_for(&"combat.factory.0"))
	if drag_target != null:
		assert_false(drag_target.visible)
		assert_eq(
			drag_target.mouse_filter,
			Control.MOUSE_FILTER_IGNORE
		)


func test_complete_pinned_visuals_build_valid_prepare_and_combat_snapshots() -> void:
	var factory := WorldBoardSnapshotFactory.new()
	var definitions: Array[StringName] = [VALID_DEF, SECOND_VALID_DEF]
	var prepare_source := _prepare_snapshot(definitions)

	var prepare := factory.build_prepare(
		prepare_source,
		prepare_source.roster.board
	)
	var combat := factory.build_combat(_combat_snapshot(definitions))

	assert_true(prepare.is_valid())
	assert_true(combat.is_valid())
	assert_eq(prepare.units.size(), 2)
	assert_eq(combat.units.size(), 2)
	_assert_units_have_complete_visuals(prepare.units)
	_assert_units_have_complete_visuals(combat.units)


func _assert_units_have_complete_visuals(
	units: Array[WorldBoardUnitSnapshot]
) -> void:
	for unit: WorldBoardUnitSnapshot in units:
		assert_not_null(unit.sprite_frames)
		assert_false(unit.animation.is_empty())
		assert_true(unit.is_valid())


func _assert_invalid_sentinel(snapshot: WorldBoardSnapshot) -> void:
	assert_not_null(snapshot)
	assert_eq(snapshot.units.size(), 1)
	assert_false(snapshot.units[0].is_valid())
	assert_false(snapshot.is_valid())


func _prepare_snapshot(
	definitions: Array[StringName]
) -> RunPresentationSnapshot:
	var placements: Array[BoardPlacementState] = []
	var units: Array[UnitInstance] = []
	for index: int in range(definitions.size()):
		var instance_id := "prepare.factory.%d" % index
		placements.append(BoardPlacementState.new(1, index, instance_id))
		var equipment: Array[String] = []
		units.append(UnitInstance.new(
			instance_id,
			definitions[index],
			1,
			equipment,
			U64Bits.zero()
		))
	var board := BoardState.new(placements)
	var strings: Array[String] = []
	var items: Array[ItemInstanceState] = []
	var relics: Array[RelicSlotState] = []
	var result := RunPresentationSnapshot.new()
	result.roster = RosterState.new(
		board,
		strings,
		units,
		items,
		strings,
		strings,
		relics
	)
	return result


func _combat_snapshot(
	definitions: Array[StringName]
) -> RunPresentationSnapshot:
	var result := RunPresentationSnapshot.new()
	for index: int in range(definitions.size()):
		var inspection := CombatUnitInspectionSnapshot.new()
		inspection.unit_serial = index + 1
		inspection.presentation_instance_id = StringName(
			"combat.factory.%d" % index
		)
		inspection.source_id = definitions[index]
		inspection.logical_cell = Vector2i(index, 5)
		inspection.stats = {
			"star": 1,
			"health": 100,
			"start_mana": 20,
			"max_mana": 80,
		}
		result.combat_inspections.append(inspection)
	return result
