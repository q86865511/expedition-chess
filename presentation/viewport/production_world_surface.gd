class_name ProductionWorldSurface
extends Control

signal target_activated(target_id: StringName)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color8(12, 22, 38), true)
	for x: int in range(0, 641, 32):
		draw_line(Vector2(x, 0), Vector2(x, 360), Color8(30, 55, 76), 1.0)
	for y: int in range(0, 361, 32):
		draw_line(Vector2(0, y), Vector2(640, y), Color8(30, 55, 76), 1.0)


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
