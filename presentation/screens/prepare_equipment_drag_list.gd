class_name PrepareEquipmentDragList
extends ItemList

signal forge_pair_dropped(first_item_id: String, second_item_id: String)

var _component_instance_ids: Dictionary = {}
var _pair_preview: Callable
var _component_rejection_text: String = ""


func configure_forge_components(
	component_instance_ids: Array[String],
	pair_preview: Callable,
	component_rejection_text: String
) -> void:
	_component_instance_ids.clear()
	for instance_id: String in component_instance_ids:
		if not instance_id.is_empty():
			_component_instance_ids[instance_id] = true
	_pair_preview = pair_preview
	_component_rejection_text = component_rejection_text


func item_drag_payload(index: int) -> Dictionary:
	if index < 0 or index >= item_count:
		return {}
	var item_id := String(get_item_metadata(index))
	if item_id.is_empty():
		return {}
	return {
		"kind": &"prepare_equipment",
		"item_instance_id": item_id,
		"is_component": _component_instance_ids.has(item_id),
		"component_rejection_text": _component_rejection_text,
	}


func _get_drag_data(at_position: Vector2) -> Variant:
	var index := get_item_at_position(at_position, true)
	var payload := item_drag_payload(index)
	if payload.is_empty():
		return null
	var preview := Label.new()
	preview.text = get_item_text(index)
	set_drag_preview(preview)
	return payload


func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	return can_drop_pair_at_index(
		get_item_at_position(at_position, true), data
	)


func can_drop_pair_at_index(target_index: int, data: Variant) -> bool:
	if not data is Dictionary:
		_clear_pair_preview()
		return false
	var payload := data as Dictionary
	if (
		StringName(payload.get("kind", &"")) != &"prepare_equipment"
		or target_index < 0
	):
		_clear_pair_preview()
		return false
	var first := String(payload.get("item_instance_id", ""))
	var second := String(get_item_metadata(target_index))
	if (
		first.is_empty()
		or second.is_empty()
		or first == second
		or not bool(payload.get("is_component", false))
		or not _component_instance_ids.has(second)
	):
		_clear_pair_preview()
		return false
	return _preview_pair(first, second)


func _drop_data(at_position: Vector2, data: Variant) -> void:
	var target_index := get_item_at_position(at_position, true)
	drop_pair_at_index(target_index, data)


func drop_pair_at_index(target_index: int, data: Variant) -> void:
	if not can_drop_pair_at_index(target_index, data):
		return
	var first := String((data as Dictionary).get("item_instance_id", ""))
	var second := String(get_item_metadata(target_index))
	forge_pair_dropped.emit(first, second)
	_clear_pair_preview()


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		_clear_pair_preview()


func _preview_pair(first: String, second: String) -> bool:
	if not _pair_preview.is_valid():
		return false
	return bool(_pair_preview.call(first, second))


func _clear_pair_preview() -> void:
	if _pair_preview.is_valid():
		_pair_preview.call("", "")
