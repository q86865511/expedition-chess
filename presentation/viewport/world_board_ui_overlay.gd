class_name WorldBoardUiOverlay
extends Control

signal unit_dropped(unit_instance_id: String, target_cell: Vector2i)
signal equipment_dropped(item_instance_id: String, unit_instance_id: String)
signal unit_targeted(unit_instance_id: String)
signal unit_hovered(unit_instance_id: String)

const INVALID_SNAPSHOT: StringName = &"WORLD_BOARD_UI_OVERLAY_SNAPSHOT_INVALID"
# UI CanvasLayer already renders this overlay above the SubViewport world.
# Keep it inside the HUD band so transition/system/modal layers remain the
# authoritative visual and input surfaces.
const OVERLAY_Z_INDEX: int = 40

const HEALTH_BACKGROUND := Color8(35, 18, 23, 245)
const HEALTH_FILL := Color8(75, 214, 111, 255)
const MANA_BACKGROUND := Color8(17, 27, 48, 245)
const MANA_FILL := Color8(72, 155, 239, 255)
const SELECTION_COLOR := Color8(255, 221, 91, 255)
const DRAG_LEGAL_COLOR := Color8(83, 224, 137, 220)
const DRAG_ILLEGAL_COLOR := Color8(239, 91, 91, 220)
const DRAG_CUE_COLOR := Color8(255, 244, 184, 255)

var _source_snapshot := WorldBoardSnapshot.new()
var _mapped_snapshot := WorldBoardOverlaySnapshot.new()
var _mapper := WorldBoardOverlayMapper.new()
var _projection: BoardProjection
var _coordinate_mapper: Object
var _cell_validator: Callable
var _drag_target: WorldBoardDragTarget


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = OVERLAY_Z_INDEX
	clip_contents = false
	_ensure_drag_target()
	queue_redraw()


func apply_snapshot(
	snapshot: WorldBoardSnapshot,
	projection: BoardProjection,
	coordinate_mapper: Object,
	cell_validator: Callable = Callable()
) -> StringName:
	if snapshot == null or not snapshot.is_valid():
		clear_snapshot()
		return INVALID_SNAPSHOT
	var source_clone := snapshot.deep_clone()
	var mapped := _mapper.map_snapshot(
		source_clone,
		projection,
		coordinate_mapper
	)
	if not mapped.error.is_empty():
		var mapping_error := mapped.error
		clear_snapshot()
		return mapping_error
	_source_snapshot = source_clone
	_mapped_snapshot = mapped
	_projection = projection
	_coordinate_mapper = coordinate_mapper
	_cell_validator = cell_validator
	_ensure_drag_target()
	_drag_target.visible = true
	_drag_target.mouse_filter = Control.MOUSE_FILTER_STOP
	var target_error := _drag_target.configure(
		_source_snapshot,
		_projection,
		_coordinate_mapper,
		_cell_validator
	)
	if not target_error.is_empty():
		clear_snapshot()
		return target_error
	queue_redraw()
	return &""


func clear_snapshot() -> void:
	_source_snapshot = WorldBoardSnapshot.new()
	_mapped_snapshot = WorldBoardOverlaySnapshot.new()
	_projection = null
	_coordinate_mapper = null
	_cell_validator = Callable()
	if is_instance_valid(_drag_target):
		_drag_target.visible = false
		_drag_target.mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()


func snapshot_clone() -> WorldBoardSnapshot:
	return _source_snapshot.deep_clone()


func mapped_snapshot_clone() -> WorldBoardOverlaySnapshot:
	return _mapped_snapshot.deep_clone()


func placement_for(
	presentation_instance_id: StringName
) -> WorldBoardOverlayPlacement:
	return _mapped_snapshot.placement_for(presentation_instance_id)


func hud_visible_for(presentation_instance_id: StringName) -> bool:
	var placement := placement_for(presentation_instance_id)
	return placement != null and placement.hud_visible


func selection_visible_for(presentation_instance_id: StringName) -> bool:
	var placement := placement_for(presentation_instance_id)
	return placement != null and placement.selected


func drag_preview_visible() -> bool:
	return _mapped_snapshot.drag_preview_visible


func drag_target() -> WorldBoardDragTarget:
	_ensure_drag_target()
	return _drag_target


func _draw() -> void:
	for placement: WorldBoardOverlayPlacement in _mapped_snapshot.placements:
		if not placement.hud_visible:
			continue
		_draw_ratio_bar(
			_screen_rect_to_local(placement.health_rect),
			placement.health_ratio,
			HEALTH_BACKGROUND,
			HEALTH_FILL
		)
		_draw_ratio_bar(
			_screen_rect_to_local(placement.mana_rect),
			placement.mana_ratio,
			MANA_BACKGROUND,
			MANA_FILL
		)
		if placement.selected:
			draw_rect(
				_screen_rect_to_local(placement.selection_rect),
				SELECTION_COLOR,
				false,
				1.0
			)
	if _mapped_snapshot.drag_preview_visible:
		var preview_color := (
			DRAG_LEGAL_COLOR
			if _mapped_snapshot.drag_preview_legal
			else DRAG_ILLEGAL_COLOR
		)
		draw_rect(
			_screen_rect_to_local(_mapped_snapshot.drag_preview_rect),
			preview_color,
			false,
			2.0
		)
		_draw_drag_direction_cue()


func _draw_ratio_bar(
	local_rect: Rect2,
	ratio: float,
	background: Color,
	fill: Color
) -> void:
	draw_rect(local_rect, background, true)
	draw_rect(
		Rect2(
			local_rect.position,
			Vector2(local_rect.size.x * clampf(ratio, 0.0, 1.0), local_rect.size.y)
		),
		fill,
		true
	)


func _screen_rect_to_local(screen_rect: Rect2) -> Rect2:
	var inverse := get_global_transform_with_canvas().affine_inverse()
	var local_start := inverse * screen_rect.position
	var local_end := inverse * screen_rect.end
	return Rect2(local_start, local_end - local_start).abs()


func _ensure_drag_target() -> void:
	if is_instance_valid(_drag_target):
		return
	_drag_target = WorldBoardDragTarget.new()
	_drag_target.name = "ProjectedBoardDragTarget"
	add_child(_drag_target)
	_drag_target.unit_dropped.connect(_on_unit_dropped)
	_drag_target.equipment_dropped.connect(_on_equipment_dropped)
	_drag_target.unit_targeted.connect(_on_unit_targeted)
	_drag_target.unit_hovered.connect(_on_unit_hovered)
	_drag_target.preview_changed.connect(_on_preview_changed)
	_drag_target.preview_cleared.connect(_on_preview_cleared)


func _on_unit_dropped(unit_instance_id: String, target_cell: Vector2i) -> void:
	unit_dropped.emit(unit_instance_id, target_cell)


func _on_equipment_dropped(
	item_instance_id: String,
	unit_instance_id: String
) -> void:
	equipment_dropped.emit(item_instance_id, unit_instance_id)


func _on_unit_targeted(unit_instance_id: String) -> void:
	unit_targeted.emit(unit_instance_id)


func _on_unit_hovered(unit_instance_id: String) -> void:
	unit_hovered.emit(unit_instance_id)


func _on_preview_changed(
	source_kind: StringName,
	source_cell: Vector2i,
	source_slot: int,
	source_instance_id: StringName,
	target_cell: Vector2i,
	target_instance_id: StringName,
	legal: bool
) -> void:
	if _projection == null or _coordinate_mapper == null:
		return
	var preview := _source_snapshot.deep_clone()
	preview.drag_preview_visible = true
	preview.drag_preview_cell = target_cell
	preview.drag_preview_legal = legal
	_source_snapshot = preview
	var base_mapped := _mapper.map_snapshot(
		_source_snapshot,
		_projection,
		_coordinate_mapper
	)
	_mapped_snapshot = _mapper.apply_drag_context(
		base_mapped,
		_projection,
		_coordinate_mapper,
		source_kind,
		source_cell,
		source_slot,
		source_instance_id,
		target_cell,
		target_instance_id,
		legal
	)
	queue_redraw()


func _on_preview_cleared() -> void:
	if _projection == null or _coordinate_mapper == null:
		return
	var cleared := _source_snapshot.deep_clone()
	cleared.drag_preview_visible = false
	_source_snapshot = cleared
	_mapped_snapshot = _mapper.map_snapshot(
		_source_snapshot,
		_projection,
		_coordinate_mapper
	)
	queue_redraw()


func _draw_drag_direction_cue() -> void:
	var inverse := get_global_transform_with_canvas().affine_inverse()
	var source := inverse * _mapped_snapshot.drag_preview_arrow_start
	var target := inverse * _mapped_snapshot.drag_preview_arrow_end
	var local_source_rect := _screen_rect_to_local(
		_mapped_snapshot.drag_preview_source_rect
	)
	draw_circle(
		local_source_rect.get_center(),
		minf(local_source_rect.size.x, local_source_rect.size.y) * 0.5,
		DRAG_CUE_COLOR,
		false,
		2.0,
		true
	)
	var target_half_size := Vector2(8.0, 8.0)
	draw_rect(
		Rect2(target - target_half_size, target_half_size * 2.0),
		DRAG_CUE_COLOR,
		false,
		2.0
	)
	_draw_arrow(source, target)
	if _mapped_snapshot.drag_preview_swap:
		var direction := (target - source).normalized()
		var normal := Vector2(-direction.y, direction.x) * 5.0
		_draw_arrow(target + normal, source + normal)


func _draw_arrow(from: Vector2, to: Vector2) -> void:
	if from.is_equal_approx(to):
		return
	draw_line(from, to, DRAG_CUE_COLOR, 2.0, true)
	var direction := (to - from).normalized()
	var normal := Vector2(-direction.y, direction.x)
	draw_colored_polygon(
		PackedVector2Array([
			to,
			to - direction * 8.0 + normal * 4.0,
			to - direction * 8.0 - normal * 4.0,
		]),
		DRAG_CUE_COLOR
	)
