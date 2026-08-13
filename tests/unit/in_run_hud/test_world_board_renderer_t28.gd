extends GutTest

const RendererScene = preload("res://scenes/production/world_board.tscn")
const SnapshotScript = preload(
	"res://presentation/viewport/world_board_snapshot.gd"
)
const UnitSnapshotScript = preload(
	"res://presentation/viewport/world_board_unit_snapshot.gd"
)
const ProductionFrames = preload(
	"res://assets/production/units/slice_player_00.tres"
)


func test_renderer_preserves_native_sprite_pivot_filter_and_integer_pixels() -> void:
	var renderer := RendererScene.instantiate()
	add_child_autofree(renderer)
	await get_tree().process_frame
	var snapshot := SnapshotScript.new()
	snapshot.append_unit(_unit(&"native", Vector2i(4, 2)))
	assert_eq(renderer.render_snapshot(snapshot), &"")

	var sprite: AnimatedSprite2D = renderer.unit_sprite(&"native")
	assert_not_null(sprite)
	assert_eq(sprite.scale, Vector2.ONE, "64x64 frames must never be downsampled")
	assert_false(sprite.centered)
	assert_eq(sprite.offset, Vector2(-32.0, -56.0), "foot pivot is (32,56)")
	assert_eq(sprite.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST)
	assert_eq(sprite.position, sprite.position.round())
	var texture := sprite.sprite_frames.get_frame_texture(sprite.animation, 0)
	assert_eq(Vector2i(texture.get_size()), Vector2i(64, 64))


func test_depth_order_uses_projected_foot_y_then_x_for_unique_cells() -> void:
	var renderer := RendererScene.instantiate()
	add_child_autofree(renderer)
	await get_tree().process_frame
	var snapshot := SnapshotScript.new()
	snapshot.append_unit(_unit(&"front", Vector2i(0, 0)))
	snapshot.append_unit(_unit(&"right", Vector2i(1, 2)))
	snapshot.append_unit(_unit(&"alpha", Vector2i(0, 2)))
	snapshot.append_unit(_unit(&"beta", Vector2i(2, 2)))
	snapshot.append_unit(_unit(&"far", Vector2i(7, 3)))
	assert_eq(renderer.render_snapshot(snapshot), &"")
	assert_eq(
		renderer.ordered_unit_ids(),
		[&"far", &"alpha", &"right", &"beta", &"front"]
	)

	var previous_z: int = -1
	for presentation_id: StringName in renderer.ordered_unit_ids():
		var sprite: AnimatedSprite2D = renderer.unit_sprite(presentation_id)
		assert_true(sprite.z_index > previous_z)
		previous_z = sprite.z_index


func test_renderer_keeps_a_clone_instead_of_the_callers_mutable_snapshot() -> void:
	var renderer := RendererScene.instantiate()
	add_child_autofree(renderer)
	await get_tree().process_frame
	var snapshot := SnapshotScript.new()
	snapshot.append_unit(_unit(&"clone", Vector2i(3, 1)))
	assert_eq(renderer.render_snapshot(snapshot), &"")
	snapshot.units[0].logical_cell = Vector2i(7, 7)
	assert_eq(renderer.snapshot_clone().units[0].logical_cell, Vector2i(3, 1))


func test_missing_sprite_frames_or_animation_fails_closed_without_a_stale_sprite() -> void:
	var renderer := RendererScene.instantiate()
	add_child_autofree(renderer)
	await get_tree().process_frame
	var valid_snapshot := SnapshotScript.new()
	valid_snapshot.append_unit(_unit(&"previous", Vector2i(1, 1)))
	assert_eq(renderer.render_snapshot(valid_snapshot), &"")
	assert_not_null(renderer.unit_sprite(&"previous"))

	var invalid_snapshot := SnapshotScript.new()
	var missing_frames := UnitSnapshotScript.new()
	missing_frames.presentation_instance_id = &"missing"
	missing_frames.logical_cell = Vector2i(2, 2)
	missing_frames.animation = &"idle_n_star1"
	invalid_snapshot.units.append(missing_frames)
	assert_eq(renderer.render_snapshot(invalid_snapshot), renderer.INVALID_SNAPSHOT)
	assert_null(renderer.unit_sprite(&"previous"))
	assert_false(renderer.visible)

	var missing_animation := _unit(&"missing_animation", Vector2i(2, 2))
	missing_animation.animation = &""
	invalid_snapshot.units.clear()
	invalid_snapshot.units.append(missing_animation)
	assert_eq(renderer.render_snapshot(invalid_snapshot), renderer.INVALID_SNAPSHOT)
	assert_null(renderer.unit_sprite(&"missing_animation"))


func _unit(
	presentation_id: StringName,
	logical_cell: Vector2i
) -> WorldBoardUnitSnapshot:
	var unit := UnitSnapshotScript.new()
	unit.presentation_instance_id = presentation_id
	unit.logical_cell = logical_cell
	unit.sprite_frames = ProductionFrames
	unit.animation = &"idle_n_star1"
	unit.health = 75
	unit.max_health = 100
	unit.mana = 25
	unit.max_mana = 50
	return unit
