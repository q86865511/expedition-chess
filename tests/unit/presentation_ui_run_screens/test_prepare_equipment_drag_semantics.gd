extends GutTest

var _preview_calls: Array[Array] = []
var _forge_drop: Array[String] = []


func test_component_pair_preview_gates_drop_and_emits_only_valid_recipe() -> void:
	var inventory := PrepareEquipmentDragList.new()
	inventory.size = Vector2(360.0, 180.0)
	add_child_autofree(inventory)
	for entry: Dictionary in [
		{"id": "alpha", "name": "Alpha"},
		{"id": "beta", "name": "Beta"},
		{"id": "beta_two", "name": "Beta Two"},
		{"id": "equipment", "name": "Equipment"},
	]:
		inventory.add_item(String(entry["name"]))
		inventory.set_item_metadata(
			inventory.item_count - 1, String(entry["id"])
		)
	var component_ids: Array[String] = ["alpha", "beta", "beta_two"]
	inventory.configure_forge_components(
		component_ids,
		Callable(self, &"_preview_pair"),
		"component cannot be equipped"
	)
	inventory.forge_pair_dropped.connect(_on_forge_drop)
	await wait_process_frames(2)

	var alpha_payload := inventory.item_drag_payload(0)
	assert_true(bool(alpha_payload.get("is_component", false)))
	assert_false(bool(inventory.item_drag_payload(3).get("is_component", true)))
	var beta_position := inventory.get_item_rect(1).get_center()
	assert_true(bool(inventory.call(&"_can_drop_data", beta_position, alpha_payload)))
	assert_eq(_preview_calls[-1], ["alpha", "beta"])
	inventory.call(&"_drop_data", beta_position, alpha_payload)
	assert_eq(_forge_drop, ["alpha", "beta"])

	var beta_payload := inventory.item_drag_payload(1)
	var beta_two_position := inventory.get_item_rect(2).get_center()
	assert_false(bool(inventory.call(
		&"_can_drop_data", beta_two_position, beta_payload
	)))
	var before_drop_count := _forge_drop.size()
	inventory.call(&"_drop_data", beta_two_position, beta_payload)
	assert_eq(_forge_drop.size(), before_drop_count)


func test_component_to_unit_is_rejected_with_non_color_cue_and_copy() -> void:
	var target := PrepareUnitDragButton.new()
	target.size = Vector2(120.0, 72.0)
	target.set_meta(&"unit_instance_id", "unit_a")
	target.tooltip_text = "unit"
	add_child_autofree(target)
	var payload := {
		"kind": &"prepare_equipment",
		"item_instance_id": "component_a",
		"is_component": true,
		"component_rejection_text": "✕ Equip · Action unavailable",
	}
	assert_false(bool(target.call(&"_can_drop_data", Vector2.ZERO, payload)))
	var state := target.preview_state()
	assert_true(bool(state.get("rejected", false)))
	assert_eq(
		String(state.get("rejection_text", "")),
		"✕ Equip · Action unavailable"
	)
	assert_eq(target.tooltip_text, "✕ Equip · Action unavailable")
	var emitted := [false]
	target.equipment_dropped.connect(func(_item: String, _unit: String) -> void:
		emitted[0] = true
	)
	target.call(&"_drop_data", Vector2.ZERO, payload)
	assert_false(bool(emitted[0]), "a rejected component must never emit prepare.equip")
	var equipment_payload := payload.duplicate(true)
	equipment_payload["is_component"] = false
	assert_true(bool(target.call(
		&"_can_drop_data", Vector2.ZERO, equipment_payload
	)))
	assert_true(target.preview_state().is_empty())
	assert_eq(target.tooltip_text, "unit")


func _preview_pair(first: String, second: String) -> bool:
	_preview_calls.append([first, second])
	return first == "alpha" and second == "beta"


func _on_forge_drop(first: String, second: String) -> void:
	_forge_drop.assign([first, second])
