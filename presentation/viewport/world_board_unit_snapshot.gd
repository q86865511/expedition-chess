class_name WorldBoardUnitSnapshot
extends RefCounted

const NATIVE_SPRITE_SIZE := Vector2i(64, 64)

var presentation_instance_id: StringName = &""
var logical_cell := Vector2i(-1, -1)
var sprite_frames: SpriteFrames
var animation: StringName = &""
var health: int
var max_health: int = 1
var mana: int
var max_mana: int = 1
var selected: bool
var overlay_visible: bool = true


func deep_clone() -> WorldBoardUnitSnapshot:
	var clone := WorldBoardUnitSnapshot.new()
	clone.presentation_instance_id = presentation_instance_id
	clone.logical_cell = logical_cell
	# SpriteFrames is an authored visual Resource. Keeping this immutable asset
	# handle does not retain a mutable domain object.
	clone.sprite_frames = sprite_frames
	clone.animation = animation
	clone.health = health
	clone.max_health = max_health
	clone.mana = mana
	clone.max_mana = max_mana
	clone.selected = selected
	clone.overlay_visible = overlay_visible
	return clone


func is_valid() -> bool:
	if presentation_instance_id.is_empty():
		return false
	if (
		logical_cell.x < 0
		or logical_cell.x >= BoardPreparationValidator.BOARD_WIDTH
	):
		return false
	if (
		logical_cell.y < 0
		or logical_cell.y >= BoardPreparationValidator.BOARD_HEIGHT
	):
		return false
	if sprite_frames == null or animation.is_empty():
		return false
	if not sprite_frames.has_animation(animation):
		return false
	if sprite_frames.get_frame_count(animation) <= 0:
		return false
	var frame_texture := sprite_frames.get_frame_texture(animation, 0)
	return (
		frame_texture != null
		and Vector2i(frame_texture.get_size()) == NATIVE_SPRITE_SIZE
	)


func health_ratio() -> float:
	if max_health <= 0:
		return 0.0
	return clampf(float(health) / float(max_health), 0.0, 1.0)


func mana_ratio() -> float:
	if max_mana <= 0:
		return 0.0
	return clampf(float(mana) / float(max_mana), 0.0, 1.0)
