class_name WorldBoardRenderer
extends Node2D

const INVALID_SNAPSHOT: StringName = &"WORLD_BOARD_RENDER_SNAPSHOT_INVALID"
const NATIVE_SPRITE_SIZE := Vector2i(64, 64)
const FOOT_PIVOT := Vector2(32.0, 56.0)
const UNIT_LAYER_BASE: int = 100

var _projection := BoardProjection.new()
var _snapshot := WorldBoardSnapshot.new()
var _unit_sprites: Dictionary = {}
var _ordered_unit_ids: Array[StringName] = []
var _background_texture: Texture2D


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	visible = not _snapshot.units.is_empty()
	queue_redraw()


func render_snapshot(snapshot: WorldBoardSnapshot) -> StringName:
	if snapshot == null or not snapshot.is_valid():
		clear_snapshot()
		return INVALID_SNAPSHOT
	_snapshot = snapshot.deep_clone()
	visible = true
	_clear_units()
	# The renderer starts hidden with an empty snapshot. Becoming visible later
	# does not guarantee the initial _draw cache was built, so explicitly
	# schedule the projected 8x8 board surface on every mount.
	queue_redraw()
	var ordered: Array[WorldBoardUnitSnapshot] = []
	for unit: WorldBoardUnitSnapshot in _snapshot.units:
		ordered.append(unit.deep_clone())
	ordered.sort_custom(_unit_precedes)
	for index: int in range(ordered.size()):
		var unit: WorldBoardUnitSnapshot = ordered[index]
		var sprite := AnimatedSprite2D.new()
		sprite.name = "Unit_%s" % String(unit.presentation_instance_id)
		sprite.sprite_frames = unit.sprite_frames
		sprite.animation = unit.animation
		sprite.frame = 0
		sprite.centered = false
		sprite.offset = -FOOT_PIVOT
		sprite.position = _projection.project_cell(unit.logical_cell).round()
		sprite.scale = Vector2.ONE
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sprite.z_index = UNIT_LAYER_BASE + index
		sprite.set_meta(&"presentation_instance_id", unit.presentation_instance_id)
		sprite.set_meta(&"logical_cell", unit.logical_cell)
		add_child(sprite)
		sprite.play(unit.animation)
		_unit_sprites[unit.presentation_instance_id] = sprite
		_ordered_unit_ids.append(unit.presentation_instance_id)
	return &""


func clear_snapshot() -> void:
	_snapshot = WorldBoardSnapshot.new()
	visible = false
	_clear_units()
	queue_redraw()


func snapshot_clone() -> WorldBoardSnapshot:
	return _snapshot.deep_clone()


func unit_sprite(
	presentation_instance_id: StringName
) -> AnimatedSprite2D:
	var value: Variant = _unit_sprites.get(presentation_instance_id)
	return value as AnimatedSprite2D if value is AnimatedSprite2D else null


func ordered_unit_ids() -> Array[StringName]:
	return _ordered_unit_ids.duplicate()


func projection() -> BoardProjection:
	return BoardProjection.new()


func set_background_texture(texture: Texture2D) -> void:
	_background_texture = texture
	queue_redraw()


func background_texture() -> Texture2D:
	return _background_texture


func _draw() -> void:
	var world_rect := Rect2(Vector2.ZERO, Vector2(BoardProjection.WORLD_SIZE))
	if _background_texture != null:
		draw_texture_rect(
			_background_texture,
			world_rect,
			false,
			ExpeditionLayoutMetrics.COMBAT_BACKGROUND_MODULATE
		)
	else:
		draw_rect(world_rect, Color8(10, 18, 31), true)
	for logical_y: int in range(BoardProjection.BOARD_SIZE.y):
		for logical_x: int in range(BoardProjection.BOARD_SIZE.x):
			var cell := Vector2i(logical_x, logical_y)
			var player_half: bool = logical_y <= 3
			var base_color := (
				Color8(38, 72, 88, 230)
				if player_half
				else Color8(47, 53, 73, 230)
			)
			if (logical_x + logical_y) % 2 == 1:
				base_color = base_color.lightened(0.08)
			var polygon := _projection.cell_polygon(cell)
			draw_colored_polygon(polygon, base_color)
			var outline := PackedVector2Array(polygon)
			outline.append(polygon[0])
			draw_polyline(outline, Color8(92, 126, 137), 1.0)


func _unit_precedes(
	left: WorldBoardUnitSnapshot,
	right: WorldBoardUnitSnapshot
) -> bool:
	var left_foot_y: float = _projection.project_cell(left.logical_cell).y
	var right_foot_y: float = _projection.project_cell(right.logical_cell).y
	if left_foot_y != right_foot_y:
		return left_foot_y < right_foot_y
	if left.logical_cell.x != right.logical_cell.x:
		return left.logical_cell.x < right.logical_cell.x
	return (
		String(left.presentation_instance_id)
		< String(right.presentation_instance_id)
	)


func _clear_units() -> void:
	for value: Variant in _unit_sprites.values():
		if value is AnimatedSprite2D:
			var sprite := value as AnimatedSprite2D
			if sprite.get_parent() == self:
				remove_child(sprite)
			sprite.free()
	_unit_sprites.clear()
	_ordered_unit_ids.clear()
