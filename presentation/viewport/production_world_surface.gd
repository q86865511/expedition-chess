class_name ProductionWorldSurface
extends Control

signal target_activated(target_id: StringName)
signal unit_dropped(unit_instance_id: String, target_cell: Vector2i)
signal equipment_dropped(item_instance_id: String, unit_instance_id: String)
signal unit_targeted(unit_instance_id: String)
signal unit_hovered(unit_instance_id: String)

const MOUNT_GROUP: StringName = &"production_world_surface"
const OVERLAY_MOUNT_GROUP: StringName = &"world_board_ui_overlay_mount"
const INVALID_SNAPSHOT: StringName = &"PRODUCTION_WORLD_SNAPSHOT_INVALID"
const INVALID_OVERLAY_MOUNT: StringName = &"PRODUCTION_WORLD_OVERLAY_MOUNT_INVALID"
const INVALID_COORDINATE_MAPPER: StringName = &"PRODUCTION_WORLD_COORDINATE_MAPPER_INVALID"

const WORLD_BOARD_SCENE := preload("res://scenes/production/world_board.tscn")
const WORLD_BOARD_OVERLAY_SCENE := preload(
	"res://scenes/production/world_board_ui_overlay.tscn"
)

var _projection := BoardProjection.new()
var _snapshot := WorldBoardSnapshot.new()
var _board_renderer: WorldBoardRenderer
var _ui_overlay: WorldBoardUiOverlay
var _coordinate_mapper: Object
var _cell_validator: Callable


func _ready() -> void:
	add_to_group(MOUNT_GROUP)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ensure_board_renderer()
	for target_name: StringName in [
		&"BoardTileTarget",
		&"CampHotspotTarget",
	]:
		var target := get_node_or_null(NodePath(String(target_name))) as Control
		if target != null:
			target.gui_input.connect(
				_on_target_gui_input.bind(
					StringName(target.get_meta(&"target_id", &""))
				)
			)


func _exit_tree() -> void:
	if _ui_overlay_available():
		_ui_overlay.free()
	_ui_overlay = null


func _draw() -> void:
	# Preserve the neutral production world while no run-board snapshot is
	# mounted. The renderer paints over it only for RUN_PREPARE/RUN_COMBAT.
	draw_rect(Rect2(Vector2.ZERO, size), Color8(12, 22, 38), true)
	for x: int in range(0, 641, 32):
		draw_line(Vector2(x, 0), Vector2(x, 360), Color8(30, 55, 76), 1.0)
	for y: int in range(0, 361, 32):
		draw_line(Vector2(0, y), Vector2(640, y), Color8(30, 55, 76), 1.0)


# WorldBoardMountAdapter resolves exactly one surface and calls this typed
# boundary directly. The overlay mount may also be discovered through
# OVERLAY_MOUNT_GROUP.
func mount_board_snapshot(
	snapshot: WorldBoardSnapshot,
	coordinate_mapper: Object = null,
	overlay_mount: Control = null,
	cell_validator: Callable = Callable()
) -> StringName:
	# A direct mount is a route snapshot boundary, even when the same persistent
	# surface and overlay nodes are reused. Mapper-only refresh_overlay() calls do
	# not pass here and therefore retain the current route's resolver.
	if _ui_overlay_available():
		_ui_overlay.clear_unit_drop_resolver()
	if snapshot == null or not snapshot.is_valid():
		clear_board_snapshot()
		return INVALID_SNAPSHOT
	var mapper_source: Object = (
		coordinate_mapper
		if coordinate_mapper != null
		else _coordinate_mapper
	)
	var mapper_error := _coordinate_mapper_error(mapper_source)
	if not mapper_error.is_empty():
		clear_board_snapshot()
		_invalidate_overlay_mapping()
		return mapper_error
	var owned_coordinate_mapper := _coordinate_mapper_clone(mapper_source)
	if owned_coordinate_mapper == null:
		clear_board_snapshot()
		_invalidate_overlay_mapping()
		return INVALID_COORDINATE_MAPPER
	var next_snapshot := snapshot.deep_clone()
	_ensure_board_renderer()
	var render_error := _board_renderer.render_snapshot(next_snapshot)
	if not render_error.is_empty():
		clear_board_snapshot()
		return render_error
	_snapshot = next_snapshot
	# A mount is a route boundary. An empty validator deliberately replaces the
	# previous route's callable; only mapper refreshes/binds of the same mounted
	# snapshot may reuse the current validator.
	var next_validator := (
		cell_validator if cell_validator.is_valid() else Callable()
	)
	if overlay_mount != null:
		var bind_error := _bind_overlay_mount_transactional(
			overlay_mount,
			owned_coordinate_mapper,
			next_validator
		)
		if not bind_error.is_empty():
			clear_board_snapshot()
			return bind_error
		return &""
	elif not _ui_overlay_available():
		var grouped_mount := _overlay_mount_from_group()
		if grouped_mount != null:
			var grouped_bind_error := _bind_overlay_mount_transactional(
				grouped_mount,
				owned_coordinate_mapper,
				next_validator
			)
			if not grouped_bind_error.is_empty():
				clear_board_snapshot()
				return grouped_bind_error
			return &""

	if _ui_overlay_available():
		var overlay_error := _apply_ui_overlay_snapshot(
			_snapshot,
			owned_coordinate_mapper,
			next_validator
		)
		if not overlay_error.is_empty():
			clear_board_snapshot()
			_invalidate_overlay_mapping()
			return overlay_error
	_coordinate_mapper = owned_coordinate_mapper
	_cell_validator = next_validator
	return &""


func bind_overlay_mount(
	overlay_mount: Control,
	coordinate_mapper: Object,
	cell_validator: Callable = Callable()
) -> StringName:
	var next_validator := (
		cell_validator
		if cell_validator.is_valid()
		else _cell_validator
	)
	return _bind_overlay_mount_transactional(
		overlay_mount,
		coordinate_mapper,
		next_validator
	)


func _bind_overlay_mount_transactional(
	overlay_mount: Control,
	coordinate_mapper: Object,
	cell_validator: Callable
) -> StringName:
	if (
		overlay_mount == null
		or not is_instance_valid(overlay_mount)
		or overlay_mount.is_queued_for_deletion()
		or not overlay_mount.is_inside_tree()
	):
		return INVALID_OVERLAY_MOUNT
	var mapper_error := _coordinate_mapper_error(coordinate_mapper)
	if not mapper_error.is_empty():
		_invalidate_overlay_mapping()
		return mapper_error
	var owned_coordinate_mapper := _coordinate_mapper_clone(coordinate_mapper)
	if owned_coordinate_mapper == null:
		_invalidate_overlay_mapping()
		return INVALID_COORDINATE_MAPPER
	var next_validator := (
		cell_validator if cell_validator.is_valid() else Callable()
	)
	var created_overlay := false
	if not _ui_overlay_available():
		_ui_overlay = null
		_ui_overlay = WORLD_BOARD_OVERLAY_SCENE.instantiate() as WorldBoardUiOverlay
		created_overlay = true
		_connect_overlay_signals()
	var previous_parent := _ui_overlay.get_parent()
	var previous_index := (
		_ui_overlay.get_index() if previous_parent != null else -1
	)
	if _ui_overlay.get_parent() != overlay_mount:
		if previous_parent != null:
			previous_parent.remove_child(_ui_overlay)
		overlay_mount.add_child(_ui_overlay)
	_ui_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if _snapshot.is_valid():
		var overlay_error := _apply_ui_overlay_snapshot(
			_snapshot,
			owned_coordinate_mapper,
			next_validator
		)
		if not overlay_error.is_empty():
			_rollback_overlay_parent(
				previous_parent,
				previous_index,
				created_overlay
			)
			_invalidate_overlay_mapping()
			return overlay_error
	else:
		_set_drag_target_enabled(false)
	_coordinate_mapper = owned_coordinate_mapper
	_cell_validator = next_validator
	return &""


func refresh_overlay() -> StringName:
	if not _ui_overlay_available():
		return INVALID_OVERLAY_MOUNT
	var mapper_error := _coordinate_mapper_error(_coordinate_mapper)
	if not mapper_error.is_empty():
		_invalidate_overlay_mapping()
		return mapper_error
	if not _snapshot.is_valid():
		_ui_overlay.clear_snapshot()
		return INVALID_SNAPSHOT
	var overlay_error := _apply_ui_overlay_snapshot(
		_snapshot,
		_coordinate_mapper,
		_cell_validator
	)
	if not overlay_error.is_empty():
		_invalidate_overlay_mapping()
	return overlay_error


## Resize is an event boundary, not a per-frame dependency. The viewport
## coordinator pushes its newly configured mapper here; clone-in prevents the
## surface and overlay from retaining the coordinator's mutable mapper.
func refresh_coordinate_mapper(coordinate_mapper: Object) -> StringName:
	var mapper_error := _coordinate_mapper_error(coordinate_mapper)
	if not mapper_error.is_empty():
		_invalidate_overlay_mapping()
		return mapper_error
	var owned_coordinate_mapper := _coordinate_mapper_clone(coordinate_mapper)
	if owned_coordinate_mapper == null:
		_invalidate_overlay_mapping()
		return INVALID_COORDINATE_MAPPER
	if not _snapshot.is_valid() or not _ui_overlay_available():
		_coordinate_mapper = owned_coordinate_mapper
		return &""
	var overlay_error := _apply_ui_overlay_snapshot(
		_snapshot,
		owned_coordinate_mapper,
		_cell_validator
	)
	if not overlay_error.is_empty():
		_invalidate_overlay_mapping()
		return overlay_error
	_coordinate_mapper = owned_coordinate_mapper
	return &""


func clear_board_snapshot() -> void:
	_snapshot = WorldBoardSnapshot.new()
	_cell_validator = Callable()
	if _board_renderer != null:
		_board_renderer.clear_snapshot()
	if _ui_overlay_available():
		_ui_overlay.clear_snapshot()


func snapshot_clone() -> WorldBoardSnapshot:
	return _snapshot.deep_clone()


func board_renderer() -> WorldBoardRenderer:
	_ensure_board_renderer()
	return _board_renderer


func ui_overlay() -> WorldBoardUiOverlay:
	return _ui_overlay if _ui_overlay_available() else null


func try_screen_to_cell(
	screen_position: Vector2,
	coordinate_mapper: Object,
	cell_validator: Callable
) -> Vector2i:
	return _projection.try_screen_to_cell(
		screen_position,
		coordinate_mapper,
		cell_validator
	)


func _on_target_gui_input(
	event: InputEvent,
	target_id: StringName
) -> void:
	if (
		event is InputEventMouseButton
		and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT
		and (event as InputEventMouseButton).pressed
		and not target_id.is_empty()
	):
		target_activated.emit(target_id)


func _ensure_board_renderer() -> void:
	if _board_renderer != null:
		return
	_board_renderer = WORLD_BOARD_SCENE.instantiate() as WorldBoardRenderer
	add_child(_board_renderer)
	move_child(_board_renderer, 0)


func _overlay_mount_from_group() -> Control:
	if get_tree() == null:
		return null
	for candidate: Node in get_tree().get_nodes_in_group(OVERLAY_MOUNT_GROUP):
		if candidate is Control:
			return candidate as Control
	return null


func _coordinate_mapper_valid(coordinate_mapper: Object) -> bool:
	return _coordinate_mapper_error(coordinate_mapper).is_empty()


func _coordinate_mapper_error(coordinate_mapper: Object) -> StringName:
	if (
		coordinate_mapper == null
		or not coordinate_mapper.has_method(&"world_to_screen")
		or not coordinate_mapper.has_method(&"screen_to_world")
		or not coordinate_mapper.has_method(&"configuration_error")
	):
		return INVALID_COORDINATE_MAPPER
	var error_value: Variant = coordinate_mapper.call(&"configuration_error")
	if not error_value is StringName and not error_value is String:
		return INVALID_COORDINATE_MAPPER
	return StringName(error_value)


func _coordinate_mapper_clone(coordinate_mapper: Object) -> Object:
	if (
		coordinate_mapper == null
		or not coordinate_mapper.has_method(&"deep_clone")
	):
		return null
	var clone_value: Variant = coordinate_mapper.call(&"deep_clone")
	if not clone_value is Object:
		return null
	var clone := clone_value as Object
	return clone if _coordinate_mapper_valid(clone) else null


func _apply_ui_overlay_snapshot(
	snapshot: WorldBoardSnapshot,
	coordinate_mapper: Object,
	cell_validator: Callable
) -> StringName:
	if not _ui_overlay_available():
		return INVALID_OVERLAY_MOUNT
	# WorldBoardDragTarget has a permissive board fallback for standalone use.
	# At the production surface boundary an absent route validator instead means
	# read-only combat HUD: keep health/mana projection, but reject and ignore all
	# board drag input.
	var overlay_validator := (
		cell_validator
		if cell_validator.is_valid()
		else Callable(self, &"_reject_world_cell")
	)
	var overlay_error := _ui_overlay.apply_snapshot(
		snapshot,
		_projection,
		coordinate_mapper,
		overlay_validator
	)
	if overlay_error.is_empty():
		_set_drag_target_enabled(cell_validator.is_valid())
	return overlay_error


func _set_drag_target_enabled(enabled: bool) -> void:
	if not _ui_overlay_available():
		return
	var drag_target := _ui_overlay.drag_target()
	if drag_target == null:
		return
	if not enabled:
		drag_target.clear_unit_drop_resolver()
	drag_target.visible = enabled
	drag_target.mouse_filter = (
		Control.MOUSE_FILTER_STOP
		if enabled
		else Control.MOUSE_FILTER_IGNORE
	)


func _reject_world_cell(_cell: Vector2i) -> bool:
	return false


func _rollback_overlay_parent(
	previous_parent: Node,
	previous_index: int,
	created_overlay: bool
) -> void:
	if not _ui_overlay_available():
		return
	var current_parent := _ui_overlay.get_parent()
	if current_parent != null:
		current_parent.remove_child(_ui_overlay)
	if created_overlay:
		_ui_overlay.free()
		_ui_overlay = null
		return
	if (
		previous_parent != null
		and is_instance_valid(previous_parent)
		and not previous_parent.is_queued_for_deletion()
	):
		previous_parent.add_child(_ui_overlay)
		if previous_index >= 0:
			previous_parent.move_child(
				_ui_overlay,
				mini(previous_index, previous_parent.get_child_count() - 1)
			)
		return
	_ui_overlay.free()
	_ui_overlay = null


func _invalidate_overlay_mapping() -> void:
	_coordinate_mapper = null
	if _ui_overlay_available():
		_ui_overlay.clear_snapshot()


func _ui_overlay_available() -> bool:
	return (
		is_instance_valid(_ui_overlay)
		and not _ui_overlay.is_queued_for_deletion()
	)


func _connect_overlay_signals() -> void:
	if not _ui_overlay_available():
		return
	if not _ui_overlay.unit_dropped.is_connected(_on_overlay_unit_dropped):
		_ui_overlay.unit_dropped.connect(_on_overlay_unit_dropped)
	if not _ui_overlay.equipment_dropped.is_connected(
		_on_overlay_equipment_dropped
	):
		_ui_overlay.equipment_dropped.connect(_on_overlay_equipment_dropped)
	if not _ui_overlay.unit_targeted.is_connected(_on_overlay_unit_targeted):
		_ui_overlay.unit_targeted.connect(_on_overlay_unit_targeted)
	if not _ui_overlay.unit_hovered.is_connected(_on_overlay_unit_hovered):
		_ui_overlay.unit_hovered.connect(_on_overlay_unit_hovered)


func _on_overlay_unit_dropped(
	unit_instance_id: String,
	target_cell: Vector2i
) -> void:
	unit_dropped.emit(unit_instance_id, target_cell)


func _on_overlay_equipment_dropped(
	item_instance_id: String,
	unit_instance_id: String
) -> void:
	equipment_dropped.emit(item_instance_id, unit_instance_id)


func _on_overlay_unit_targeted(unit_instance_id: String) -> void:
	unit_targeted.emit(unit_instance_id)


func _on_overlay_unit_hovered(unit_instance_id: String) -> void:
	unit_hovered.emit(unit_instance_id)
