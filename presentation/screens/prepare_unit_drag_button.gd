class_name PrepareUnitDragButton
extends Button

signal unit_dropped(
	unit_instance_id: String,
	target_kind: StringName,
	target_cell: Vector2i,
	target_slot: int
)
signal equipment_dropped(item_instance_id: String, unit_instance_id: String)

const PREVIEW_CUE_COLOR := Color8(244, 229, 153, 255)

var _drop_preview: Dictionary = {}


func _get_drag_data(_at_position: Vector2) -> Variant:
	var payload := unit_drag_payload()
	if payload.is_empty():
		return null
	var preview := Label.new()
	preview.text = String(get_meta(&"accessible_text", text))
	if preview.text.is_empty():
		preview.text = "◆"
	set_drag_preview(preview)
	return payload


func unit_drag_payload() -> Dictionary:
	var unit_id := String(get_meta(&"unit_instance_id", ""))
	if unit_id.is_empty():
		return {}
	return {
		"kind": &"prepare_unit",
		"unit_instance_id": unit_id,
		"source_kind": StringName(get_meta(&"drag_target_kind", &"")),
		"source_cell": Vector2i(
			int(get_meta(&"board_x", -1)),
			int(get_meta(&"board_y", -1))
		),
		"source_slot": int(get_meta(&"bench_slot", -1)),
	}


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if not data is Dictionary:
		_clear_drop_preview()
		return false
	var payload := data as Dictionary
	var kind := StringName(payload.get("kind", &""))
	if kind == &"prepare_unit":
		var legal := StringName(get_meta(&"drag_target_kind", &"")) in [
			&"board", &"bench",
		]
		if legal:
			_drop_preview = {
				"source_kind": StringName(payload.get("source_kind", &"")),
				"source_cell": payload.get("source_cell", Vector2i(-1, -1)),
				"source_slot": int(payload.get("source_slot", -1)),
				"target_kind": StringName(get_meta(&"drag_target_kind", &"")),
				"target_cell": Vector2i(
					int(get_meta(&"board_x", -1)),
					int(get_meta(&"board_y", -1))
				),
				"target_slot": int(get_meta(&"bench_slot", -1)),
				"swap": not String(get_meta(&"unit_instance_id", "")).is_empty()
					and String(get_meta(&"unit_instance_id", ""))
						!= String(payload.get("unit_instance_id", "")),
			}
			queue_redraw()
		else:
			_clear_drop_preview()
		return legal
	if kind == &"prepare_equipment":
		_clear_drop_preview()
		return not String(get_meta(&"unit_instance_id", "")).is_empty()
	_clear_drop_preview()
	return false


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	_clear_drop_preview()
	var payload := data as Dictionary
	var kind := StringName(payload.get("kind", &""))
	if kind == &"prepare_equipment":
		equipment_dropped.emit(
			String(payload.get("item_instance_id", "")),
			String(get_meta(&"unit_instance_id", ""))
		)
		return
	unit_dropped.emit(
		String(payload.get("unit_instance_id", "")),
		StringName(get_meta(&"drag_target_kind", &"")),
		Vector2i(
			int(get_meta(&"board_x", -1)),
			int(get_meta(&"board_y", -1))
		),
		int(get_meta(&"bench_slot", -1))
	)


func preview_state() -> Dictionary:
	return _drop_preview.duplicate(true)


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		_clear_drop_preview()


func _draw() -> void:
	if _drop_preview.is_empty():
		return
	var center_y := size.y * 0.5
	var source := Vector2(size.x * 0.24, center_y)
	var target := Vector2(size.x * 0.76, center_y)
	draw_circle(source, 7.0, PREVIEW_CUE_COLOR, false, 2.0, true)
	draw_rect(
		Rect2(target - Vector2(7.0, 7.0), Vector2(14.0, 14.0)),
		PREVIEW_CUE_COLOR,
		false,
		2.0
	)
	_draw_arrow(source + Vector2(9.0, 0.0), target - Vector2(9.0, 0.0))
	if bool(_drop_preview.get("swap", false)):
		_draw_arrow(
			target - Vector2(9.0, 5.0),
			source + Vector2(9.0, 5.0)
		)


func _draw_arrow(from: Vector2, to: Vector2) -> void:
	draw_line(from, to, PREVIEW_CUE_COLOR, 2.0, true)
	var direction := (to - from).normalized()
	var normal := Vector2(-direction.y, direction.x)
	draw_colored_polygon(
		PackedVector2Array([
			to,
			to - direction * 7.0 + normal * 4.0,
			to - direction * 7.0 - normal * 4.0,
		]),
		PREVIEW_CUE_COLOR
	)


func _clear_drop_preview() -> void:
	if _drop_preview.is_empty():
		return
	_drop_preview.clear()
	queue_redraw()
