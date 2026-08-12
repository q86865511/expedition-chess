class_name WorldBoardDragTarget
extends Control

signal unit_dropped(unit_instance_id: String, target_cell: Vector2i)
signal equipment_dropped(item_instance_id: String, unit_instance_id: String)
signal unit_targeted(unit_instance_id: String)
signal unit_hovered(unit_instance_id: String)
signal preview_changed(
	source_kind: StringName,
	source_cell: Vector2i,
	source_slot: int,
	source_instance_id: StringName,
	target_cell: Vector2i,
	target_instance_id: StringName,
	legal: bool
)
signal preview_cleared()

const INVALID_CELL := Vector2i(-1, -1)
const PREVIEW_SIZE := Vector2(48.0, 48.0)

var _snapshot := WorldBoardSnapshot.new()
var _projection: BoardProjection
var _coordinate_mapper: Object
var _cell_validator: Callable
var _hovered_unit_id: String = ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	clip_contents = false
	if not mouse_exited.is_connected(_on_mouse_exited):
		mouse_exited.connect(_on_mouse_exited)


func configure(
	snapshot: WorldBoardSnapshot,
	projection: BoardProjection,
	coordinate_mapper: Object,
	cell_validator: Callable = Callable()
) -> StringName:
	if (
		snapshot == null
		or not snapshot.is_valid()
		or projection == null
		or coordinate_mapper == null
		or not coordinate_mapper.has_method(&"world_to_screen")
		or not coordinate_mapper.has_method(&"screen_to_world")
	):
		return WorldBoardUiOverlay.INVALID_SNAPSHOT
	_snapshot = snapshot.deep_clone()
	_projection = projection
	_coordinate_mapper = coordinate_mapper
	_cell_validator = (
		cell_validator
		if cell_validator.is_valid()
		else Callable(self, &"_cell_in_board")
	)
	var had_hover_target := not _hovered_unit_id.is_empty()
	_hovered_unit_id = ""
	if had_hover_target:
		# Resize/remount is an input lifecycle boundary. Clear the consumer's W
		# target before the next pointer motion instead of retaining a stale id.
		unit_hovered.emit("")
	return _refresh_board_rect()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_publish_hover_at((event as InputEventMouseMotion).position)
		return
	if (
		event is InputEventMouseButton
		and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT
		and (event as InputEventMouseButton).pressed
	):
		var unit_id := _unit_at(_cell_at((event as InputEventMouseButton).position))
		if not unit_id.is_empty():
			unit_targeted.emit(unit_id)


func _publish_hover_at(local_position: Vector2) -> void:
	var unit_id := _unit_at(_cell_at(local_position))
	if unit_id == _hovered_unit_id:
		return
	_hovered_unit_id = unit_id
	unit_hovered.emit(unit_id)


func _on_mouse_exited() -> void:
	if _hovered_unit_id.is_empty():
		return
	_hovered_unit_id = ""
	unit_hovered.emit("")


func _get_drag_data(at_position: Vector2) -> Variant:
	var source_cell := _cell_at(at_position)
	var unit_id := _unit_at(source_cell)
	if unit_id.is_empty():
		return null
	var preview := Label.new()
	preview.text = "◆"
	preview.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	preview.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ExpeditionLayoutMetrics.set_fixed_min(
		preview,
		PREVIEW_SIZE.x,
		PREVIEW_SIZE.y
	)
	set_drag_preview(preview)
	return {
		"kind": &"prepare_unit",
		"unit_instance_id": unit_id,
		"source_kind": &"board",
		"source_cell": source_cell,
		"source_slot": -1,
	}


func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	if not data is Dictionary:
		preview_cleared.emit()
		return false
	var payload := data as Dictionary
	var cell := _cell_at(at_position)
	var kind := StringName(payload.get("kind", &""))
	var legal := false
	if kind == &"prepare_unit":
		legal = (
			cell != INVALID_CELL
			and not String(payload.get("unit_instance_id", "")).is_empty()
		)
	elif kind == &"prepare_equipment":
		legal = (
			cell != INVALID_CELL
			and not String(payload.get("item_instance_id", "")).is_empty()
			and not _unit_at(cell).is_empty()
		)
	if cell == INVALID_CELL:
		preview_cleared.emit()
	else:
		var source_instance_id := StringName(
			String(payload.get("unit_instance_id", ""))
		)
		var source_kind := StringName(payload.get("source_kind", &""))
		var source_cell: Vector2i = payload.get(
			"source_cell",
			_cell_for(source_instance_id)
		)
		if source_kind.is_empty():
			if kind == &"prepare_equipment":
				source_kind = &"equipment"
			else:
				source_kind = (
					&"board" if source_cell != INVALID_CELL else &"bench"
				)
		preview_changed.emit(
			source_kind,
			source_cell,
			int(payload.get("source_slot", -1)),
			source_instance_id,
			cell,
			StringName(_unit_at(cell)),
			legal
		)
	return legal


func _drop_data(at_position: Vector2, data: Variant) -> void:
	if not data is Dictionary:
		return
	var payload := data as Dictionary
	var cell := _cell_at(at_position)
	if cell == INVALID_CELL:
		return
	var kind := StringName(payload.get("kind", &""))
	if kind == &"prepare_equipment":
		var target_unit_id := _unit_at(cell)
		if not target_unit_id.is_empty():
			equipment_dropped.emit(
				String(payload.get("item_instance_id", "")),
				target_unit_id
			)
	else:
		var unit_id := String(payload.get("unit_instance_id", ""))
		if not unit_id.is_empty():
			unit_dropped.emit(unit_id, cell)
	preview_cleared.emit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		preview_cleared.emit()


func _cell_at(local_position: Vector2) -> Vector2i:
	if _projection == null or _coordinate_mapper == null:
		return INVALID_CELL
	var screen_position := get_global_transform_with_canvas() * local_position
	return _projection.try_screen_to_cell(
		screen_position,
		_coordinate_mapper,
		_cell_validator
	)


func _unit_at(cell: Vector2i) -> String:
	if cell == INVALID_CELL:
		return ""
	for unit: WorldBoardUnitSnapshot in _snapshot.units:
		if unit != null and unit.logical_cell == cell:
			return String(unit.presentation_instance_id)
	return ""


func _cell_for(presentation_instance_id: StringName) -> Vector2i:
	if presentation_instance_id.is_empty():
		return INVALID_CELL
	for unit: WorldBoardUnitSnapshot in _snapshot.units:
		if unit != null and unit.presentation_instance_id == presentation_instance_id:
			return unit.logical_cell
	return INVALID_CELL


func _refresh_board_rect() -> StringName:
	var parent_control := get_parent() as Control
	if parent_control == null:
		return WorldBoardUiOverlay.INVALID_SNAPSHOT
	var parent_inverse := (
		parent_control.get_global_transform_with_canvas().affine_inverse()
	)
	var minimum := Vector2(INF, INF)
	var maximum := Vector2(-INF, -INF)
	var fractional_min := Vector2(-0.5, -0.5)
	var fractional_max := Vector2(
		float(BoardPreparationValidator.BOARD_WIDTH) - 0.5,
		float(BoardPreparationValidator.BOARD_HEIGHT) - 0.5
	)
	for logical_corner: Vector2 in [
		fractional_min,
		Vector2(fractional_max.x, fractional_min.y),
		fractional_max,
		Vector2(fractional_min.x, fractional_max.y),
	]:
		var screen_value: Variant = _coordinate_mapper.call(
			&"world_to_screen",
			_projection.logical_to_world(logical_corner)
		)
		if not screen_value is Vector2:
			return WorldBoardOverlayMapper.INVALID_COORDINATE_MAPPER
		var local_corner := parent_inverse * (screen_value as Vector2)
		minimum = minimum.min(local_corner)
		maximum = maximum.max(local_corner)
	position = minimum.floor()
	size = maximum.ceil() - position
	return &""


func _cell_in_board(cell: Vector2i) -> bool:
	return (
		cell.x >= 0
		and cell.x < BoardPreparationValidator.BOARD_WIDTH
		and cell.y >= 0
		and cell.y < BoardPreparationValidator.BOARD_HEIGHT
	)
