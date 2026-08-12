class_name PrepareEquipmentDragList
extends ItemList

signal forge_pair_dropped(first_item_id: String, second_item_id: String)


func _get_drag_data(at_position: Vector2) -> Variant:
	var index := get_item_at_position(at_position, true)
	if index < 0:
		return null
	var item_id := String(get_item_metadata(index))
	if item_id.is_empty():
		return null
	var preview := Label.new()
	preview.text = get_item_text(index)
	set_drag_preview(preview)
	return {
		"kind": &"prepare_equipment",
		"item_instance_id": item_id,
	}


func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	return (
		data is Dictionary
		and StringName((data as Dictionary).get("kind", &""))
		== &"prepare_equipment"
		and get_item_at_position(at_position, true) >= 0
	)


func _drop_data(at_position: Vector2, data: Variant) -> void:
	var target_index := get_item_at_position(at_position, true)
	if target_index < 0:
		return
	var first := String((data as Dictionary).get("item_instance_id", ""))
	var second := String(get_item_metadata(target_index))
	if not first.is_empty() and not second.is_empty() and first != second:
		forge_pair_dropped.emit(first, second)
