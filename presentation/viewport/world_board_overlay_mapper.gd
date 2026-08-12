class_name WorldBoardOverlayMapper
extends RefCounted

const INVALID_SNAPSHOT: StringName = &"WORLD_BOARD_OVERLAY_SNAPSHOT_INVALID"
const INVALID_COORDINATE_MAPPER: StringName = &"WORLD_BOARD_OVERLAY_MAPPER_INVALID"

const HEALTH_BAR_SIZE := Vector2(40.0, 4.0)
const MANA_BAR_SIZE := Vector2(40.0, 3.0)
const SELECTION_SIZE := Vector2(48.0, 14.0)
const DRAG_PREVIEW_SIZE := Vector2(52.0, 18.0)
const DRAG_SOURCE_SIZE := Vector2(16.0, 16.0)
const NON_BOARD_SOURCE_OFFSET := Vector2(-64.0, 0.0)
const SPRITE_HEAD_WORLD_OFFSET := Vector2(0.0, -56.0)
const HEALTH_SCREEN_OFFSET_FROM_HEAD := Vector2(-20.0, -6.0)
const MANA_SCREEN_OFFSET_FROM_HEAD := Vector2(-20.0, -1.0)
const SELECTION_OFFSET := Vector2(-24.0, -10.0)
const DRAG_PREVIEW_OFFSET := Vector2(-26.0, -12.0)


func map_snapshot(
	snapshot: WorldBoardSnapshot,
	projection: BoardProjection,
	coordinate_mapper: Object
) -> WorldBoardOverlaySnapshot:
	var mapped := WorldBoardOverlaySnapshot.new()
	if snapshot == null or projection == null or not snapshot.is_valid():
		mapped.error = INVALID_SNAPSHOT
		return mapped
	if (
		coordinate_mapper == null
		or not coordinate_mapper.has_method(&"world_to_screen")
	):
		mapped.error = INVALID_COORDINATE_MAPPER
		return mapped

	var source := snapshot.deep_clone()
	var ordered_units: Array[WorldBoardUnitSnapshot] = []
	for unit: WorldBoardUnitSnapshot in source.units:
		ordered_units.append(unit)
	ordered_units.sort_custom(
		func(
			left: WorldBoardUnitSnapshot,
			right: WorldBoardUnitSnapshot
		) -> bool:
			return _unit_precedes(left, right, projection)
	)
	for unit: WorldBoardUnitSnapshot in ordered_units:
		var world_foot := projection.project_cell(unit.logical_cell)
		var screen_value: Variant = coordinate_mapper.call(
			&"world_to_screen",
			world_foot
		)
		if not screen_value is Vector2:
			mapped.error = INVALID_COORDINATE_MAPPER
			mapped.placements.clear()
			return mapped
		var screen_foot: Vector2 = screen_value.round()
		var screen_head_value: Variant = coordinate_mapper.call(
			&"world_to_screen",
			world_foot + SPRITE_HEAD_WORLD_OFFSET
		)
		if not screen_head_value is Vector2:
			mapped.error = INVALID_COORDINATE_MAPPER
			mapped.placements.clear()
			return mapped
		var screen_head: Vector2 = screen_head_value.round()
		var placement := WorldBoardOverlayPlacement.new()
		placement.presentation_instance_id = unit.presentation_instance_id
		placement.screen_foot_position = screen_foot
		placement.health_rect = Rect2(
			screen_head + HEALTH_SCREEN_OFFSET_FROM_HEAD,
			HEALTH_BAR_SIZE
		)
		placement.mana_rect = Rect2(
			screen_head + MANA_SCREEN_OFFSET_FROM_HEAD,
			MANA_BAR_SIZE
		)
		placement.selection_rect = Rect2(
			screen_foot + SELECTION_OFFSET,
			SELECTION_SIZE
		)
		placement.health_ratio = unit.health_ratio()
		placement.mana_ratio = unit.mana_ratio()
		placement.hud_visible = unit.overlay_visible
		placement.selected = unit.overlay_visible and unit.selected
		mapped.placements.append(placement)

	if source.drag_preview_visible:
		var drag_screen_value: Variant = coordinate_mapper.call(
			&"world_to_screen",
			projection.project_cell(source.drag_preview_cell)
		)
		if not drag_screen_value is Vector2:
			mapped.error = INVALID_COORDINATE_MAPPER
			mapped.placements.clear()
			return mapped
		var drag_screen: Vector2 = drag_screen_value.round()
		mapped.drag_preview_visible = true
		mapped.drag_preview_legal = source.drag_preview_legal
		mapped.drag_preview_rect = Rect2(
			drag_screen + DRAG_PREVIEW_OFFSET,
			DRAG_PREVIEW_SIZE
		)
	return mapped


func _unit_precedes(
	left: WorldBoardUnitSnapshot,
	right: WorldBoardUnitSnapshot,
	projection: BoardProjection
) -> bool:
	# Match WorldBoardRenderer exactly so overlapping HUD paint follows the same
	# deterministic logical depth as its sprite. This is presentation ordering,
	# not a duplicated gameplay rule.
	var left_foot_y: float = projection.project_cell(left.logical_cell).y
	var right_foot_y: float = projection.project_cell(right.logical_cell).y
	if left_foot_y != right_foot_y:
		return left_foot_y < right_foot_y
	if left.logical_cell.x != right.logical_cell.x:
		return left.logical_cell.x < right.logical_cell.x
	return (
		String(left.presentation_instance_id)
		< String(right.presentation_instance_id)
	)


func apply_drag_context(
	mapped_snapshot: WorldBoardOverlaySnapshot,
	projection: BoardProjection,
	coordinate_mapper: Object,
	source_kind: StringName,
	source_cell: Vector2i,
	source_slot: int,
	source_instance_id: StringName,
	target_cell: Vector2i,
	target_instance_id: StringName,
	legal: bool
) -> WorldBoardOverlaySnapshot:
	var mapped := (
		mapped_snapshot.deep_clone()
		if mapped_snapshot != null
		else WorldBoardOverlaySnapshot.new()
	)
	if (
		mapped_snapshot == null
		or projection == null
		or coordinate_mapper == null
		or not coordinate_mapper.has_method(&"world_to_screen")
	):
		mapped.error = INVALID_COORDINATE_MAPPER
		mapped.drag_preview_visible = false
		return mapped
	var target_value: Variant = coordinate_mapper.call(
		&"world_to_screen",
		projection.project_cell(target_cell)
	)
	if not target_value is Vector2:
		mapped.error = INVALID_COORDINATE_MAPPER
		mapped.drag_preview_visible = false
		return mapped
	var target_screen: Vector2 = (target_value as Vector2).round()
	var source_screen := target_screen + NON_BOARD_SOURCE_OFFSET
	if source_kind == &"board":
		var source_value: Variant = coordinate_mapper.call(
			&"world_to_screen",
			projection.project_cell(source_cell)
		)
		if not source_value is Vector2:
			mapped.error = INVALID_COORDINATE_MAPPER
			mapped.drag_preview_visible = false
			return mapped
		source_screen = (source_value as Vector2).round()
	mapped.drag_preview_visible = true
	mapped.drag_preview_legal = legal
	mapped.drag_preview_rect = Rect2(
		target_screen + DRAG_PREVIEW_OFFSET,
		DRAG_PREVIEW_SIZE
	)
	mapped.drag_preview_source_kind = source_kind
	mapped.drag_preview_source_cell = source_cell
	mapped.drag_preview_source_slot = source_slot
	mapped.drag_preview_target_cell = target_cell
	mapped.drag_preview_source_instance_id = source_instance_id
	mapped.drag_preview_target_instance_id = target_instance_id
	mapped.drag_preview_swap = (
		not source_instance_id.is_empty()
		and not target_instance_id.is_empty()
		and source_instance_id != target_instance_id
	)
	mapped.drag_preview_source_rect = Rect2(
		source_screen - DRAG_SOURCE_SIZE * 0.5,
		DRAG_SOURCE_SIZE
	)
	mapped.drag_preview_arrow_start = source_screen
	mapped.drag_preview_arrow_end = target_screen
	return mapped
