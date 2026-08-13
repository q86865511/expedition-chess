class_name PrepareUnitDragButton
extends Button

signal unit_dropped(
	unit_instance_id: String,
	target_kind: StringName,
	target_cell: Vector2i,
	target_slot: int
)
signal equipment_dropped(item_instance_id: String, unit_instance_id: String)
signal unit_preview_cleared()

const PREVIEW_CUE_COLOR := Color8(244, 229, 153, 255)

var _drop_preview: Dictionary = {}
var _rejection_tooltip_restore: String = ""
var _has_rejection_tooltip_restore: bool = false
var _unit_drop_resolver: Callable


func configure_unit_drop_resolver(resolver: Callable) -> void:
	_unit_drop_resolver = resolver


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
		var target_kind := StringName(get_meta(&"drag_target_kind", &""))
		var target_cell := Vector2i(
			int(get_meta(&"board_x", -1)),
			int(get_meta(&"board_y", -1))
		)
		var target_slot := int(get_meta(&"bench_slot", -1))
		var resolution: Dictionary = {}
		if _unit_drop_resolver.is_valid():
			var resolved: Variant = _unit_drop_resolver.call(
				String(payload.get("unit_instance_id", "")),
				target_kind,
				target_cell,
				target_slot
			)
			if resolved is Dictionary:
				resolution = (resolved as Dictionary).duplicate(true)
		var legal := bool(resolution.get("legal", false))
		if legal:
			_drop_preview = {
				"source_kind": StringName(payload.get("source_kind", &"")),
				"source_cell": payload.get("source_cell", Vector2i(-1, -1)),
				"source_slot": int(payload.get("source_slot", -1)),
				"target_kind": target_kind,
				"target_cell": target_cell,
				"target_slot": target_slot,
				"swap": not String(get_meta(&"unit_instance_id", "")).is_empty()
					and String(get_meta(&"unit_instance_id", ""))
						!= String(payload.get("unit_instance_id", "")),
			}
			queue_redraw()
		else:
			_drop_preview = {"rejected": true}
			queue_redraw()
		return legal
	if kind == &"prepare_equipment":
		if bool(payload.get("is_component", false)):
			_set_component_rejection(
				String(payload.get("component_rejection_text", ""))
			)
			return false
		_clear_drop_preview()
		return not String(get_meta(&"unit_instance_id", "")).is_empty()
	_clear_drop_preview()
	return false


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	_clear_drop_preview()
	var payload := data as Dictionary
	var kind := StringName(payload.get("kind", &""))
	if kind == &"prepare_equipment":
		if bool(payload.get("is_component", false)):
			return
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
	if bool(_drop_preview.get("rejected", false)):
		var inset := Vector2(10.0, 10.0)
		draw_line(inset, size - inset, PREVIEW_CUE_COLOR, 3.0, true)
		draw_line(
			Vector2(size.x - inset.x, inset.y),
			Vector2(inset.x, size.y - inset.y),
			PREVIEW_CUE_COLOR,
			3.0,
			true
		)
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
	if _has_rejection_tooltip_restore:
		tooltip_text = _rejection_tooltip_restore
		_rejection_tooltip_restore = ""
		_has_rejection_tooltip_restore = false
	if _drop_preview.is_empty():
		unit_preview_cleared.emit()
		return
	_drop_preview.clear()
	queue_redraw()
	unit_preview_cleared.emit()


func _set_component_rejection(rejection_text: String) -> void:
	if not _has_rejection_tooltip_restore:
		_rejection_tooltip_restore = tooltip_text
		_has_rejection_tooltip_restore = true
	_drop_preview = {
		"rejected": true,
		"rejection_text": rejection_text,
	}
	tooltip_text = rejection_text
	queue_redraw()
