extends GutTest

const Support = preload(
	"res://tests/integration/presentation_ui_r14_accessibility_joint/"
	+ "r14_accessibility_joint_test_support.gd"
)

const REQUIRED_FOCUS_ACTIONS: Array[StringName] = [
	&"prepare.refresh",
	&"prepare.equip",
	&"prepare.start",
]


func test_keyboard_only_purchase_deploy_equip_and_start_combat() -> void:
	var harness := Support.boot(self)
	assert_true(harness.boot_error.is_empty(), String(harness.boot_error))
	assert_true(harness.settings_bind_error.is_empty(), String(harness.settings_bind_error))
	if not harness.boot_error.is_empty() or not harness.settings_bind_error.is_empty():
		return
	var driven := Support.drive_to_run_prepare(harness)
	assert_true(bool(driven.get("ok", false)), String(driven.get("error", &"")))
	if not bool(driven.get("ok", false)):
		return
	await wait_process_frames(3)

	var seeded := _seed_production_equipment(harness)
	assert_true(bool(seeded.get("ok", false)), String(seeded.get("error", &"")))
	if not bool(seeded.get("ok", false)):
		return
	var equipment_instance_id := String(seeded.get("item_instance_id", ""))
	var seed_reload_error := Support.reload_current_route(harness)
	assert_eq(
		seed_reload_error,
		&"",
		"the production route must rebuild after the fixture commits gold/equipment"
	)
	if not seed_reload_error.is_empty():
		return
	await wait_process_frames(4)
	var before_purchase := _snapshot(harness)
	assert_not_null(before_purchase)
	if before_purchase == null:
		return
	var existing_unit_ids := _unit_ids(before_purchase)

	var screen := Support.active_screen(harness)
	assert_not_null(screen)
	if screen == null:
		return
	_assert_required_focus_graph(screen)
	assert_true(
		await _tab_to_action(harness, &"prepare.refresh"),
		_focus_diagnostic(harness, &"prepare.refresh")
	)
	var focused_refresh := _focus_owner(harness) as Button
	assert_not_null(focused_refresh)
	if focused_refresh == null:
		return
	if focused_refresh.disabled:
		assert_false(
			focused_refresh.tooltip_text.is_empty(),
			"a rejected typed refresh quote must expose its localized reason"
		)
		var direct_refresh := Support.active_screen(harness).request_intent(
			RunPresentationIntent.new(RunPresentationIntent.Kind.REFRESH_SHOP)
		)
		assert_true(
			direct_refresh.ok,
			"the fixture's committed gold must make the canonical refresh succeed"
		)
		await wait_process_frames(4)
		assert_true(await _tab_to_action(harness, &"prepare.refresh"))
	await _press_action(&"ui_accept")
	assert_true(await _wait_for_prepare_inventory(harness, equipment_instance_id))

	assert_true(await _tab_to_meta(harness, &"shop_offer_id"))
	var shop_card := _focus_owner(harness) as Button
	assert_not_null(shop_card)
	if shop_card == null:
		return
	var offer_id := String(shop_card.get_meta(&"shop_offer_id", ""))
	assert_false(offer_id.is_empty(), "keyboard focus must land on an exact shop offer")
	await _press_action(&"ui_accept")
	var purchased_unit_id := await _wait_for_purchased_unit(harness, existing_unit_ids)
	assert_false(
		purchased_unit_id.is_empty(),
		"Enter on the focused shop card must purchase one canonical unit"
	)
	if purchased_unit_id.is_empty():
		return

	assert_true(await _select_unit_with_keyboard(harness, purchased_unit_id))
	await _press_key(KEY_W, 119)
	assert_true(
		await _wait_for_unit_on_board(harness, purchased_unit_id),
		"W on the focused unit selector must commit the unit to the board"
	)

	# W commits and recomposes RUN_PREPARE. Reacquire both selectors entirely
	# through the authored focus cycle before invoking Equip.
	assert_true(await _select_unit_with_keyboard(harness, purchased_unit_id))
	assert_true(await _tab_to_name(harness, &"InventorySelector"))
	var inventory_before := _focus_owner(harness) as ItemList
	if inventory_before != null:
		await _select_metadata_with_keyboard(
			inventory_before, equipment_instance_id
		)
	await wait_process_frames(2)
	var inventory := _focus_owner(harness) as ItemList
	assert_not_null(inventory)
	if inventory == null:
		return
	assert_eq(
		str(_selected_metadata(inventory)),
		equipment_instance_id,
		"Home must select the seeded production equipment"
	)
	assert_true(await _tab_to_action(harness, &"prepare.equip"))
	await _press_action(&"ui_accept")
	assert_true(
		await _wait_for_equipped_item(
			harness, purchased_unit_id, equipment_instance_id
		),
		_equip_failure_diagnostic(harness)
	)

	assert_true(await _tab_to_action(harness, &"prepare.start"))
	await _press_action(&"ui_accept")
	assert_true(
		await _wait_for_route(harness, &"RUN_COMBAT", 240),
		"Enter on prepare.start must commit combat through the production route"
	)
	var final_snapshot := _snapshot(harness)
	assert_not_null(final_snapshot)
	if final_snapshot != null:
		assert_eq(final_snapshot.app_phase, &"COMBAT")
		assert_true(_unit_has_item(
			final_snapshot, purchased_unit_id, equipment_instance_id
		))


func _seed_production_equipment(harness: Variant) -> Dictionary:
	var presentation_result: RunPresentationSessionResult = (
		harness.root.current_run_presentation()
	)
	if presentation_result == null or not presentation_result.ok:
		return {"ok": false, "error": &"T21_PRESENTATION_SESSION_MISSING"}
	var presentation := presentation_result.session
	var controller := presentation.get(&"_controller") as RunController
	var run_session := controller.get(&"_session") as RunSession if controller != null else null
	var battle_catalog := presentation.get(&"_battle_catalog") as BattleRuleCatalog
	if run_session == null or battle_catalog == null:
		return {"ok": false, "error": &"T21_PRODUCTION_SUPPLY_MISSING"}
	var draft := run_session.run_snapshot()
	# T14 now correctly removes unaffordable refresh from the focus cycle.
	# This keyboard E2E fixture therefore seeds enough canonical gold together
	# with its test-only equipment so Refresh remains a legitimate focus target;
	# all subsequent spending still goes through production commands/quotes.
	draft.economy_state.gold = 99
	var receipt := harness.registry.call(
		&"_receipt_for_digest", draft.content_snapshot.manifest_digest_value()
	) as PinnedCatalogBuildReceipt
	if receipt == null:
		return {"ok": false, "error": &"T21_PINNED_RECEIPT_MISSING"}
	var equipment_def_id: StringName
	for content_id: StringName in receipt.active_entry_ids:
		if battle_catalog.try_equipment_rule(content_id) != null:
			equipment_def_id = content_id
			break
	if equipment_def_id.is_empty():
		return {"ok": false, "error": &"T21_EQUIPMENT_DEF_MISSING"}
	var created := InstanceIdFactory.new().create(&"it", draft.next_item_serial)
	if not created.ok:
		return {"ok": false, "error": &"T21_ITEM_SERIAL_INVALID"}
	var item_instance_id := String(created.instance_id)
	draft.roster_state.item_instances.append(ItemInstanceState.new(
		item_instance_id,
		equipment_def_id,
		null,
		draft.next_item_serial
	))
	draft.roster_state.inventory_item_instance_ids.append(item_instance_id)
	draft.next_item_serial = created.next_serial.deep_clone()
	run_session.call(&"_commit_saved_draft", draft)
	return {
		"ok": true,
		"error": &"",
		"item_instance_id": item_instance_id,
	}


func _assert_required_focus_graph(screen: ProductionScreen) -> void:
	var authored := KeyboardFocusGraph.new().focus_order(&"RUN_PREPARE", 100, [])
	for action_id: StringName in REQUIRED_FOCUS_ACTIONS:
		assert_true(authored.has(action_id), "%s must be in RUN_PREPARE focus graph" % action_id)
	var ordered := screen.call(&"_ordered_focus_controls") as Array
	for action_id: StringName in REQUIRED_FOCUS_ACTIONS:
		assert_true(
			_ordered_has_action(ordered, action_id),
			"production focus controls must include %s" % action_id
		)
	assert_true(_ordered_has_name(ordered, &"BuildUnitSelector"))
	assert_true(_ordered_has_name(ordered, &"InventorySelector"))
	assert_true(_ordered_has_meta(ordered, &"shop_offer_id"))


func _ordered_has_action(ordered: Array, action_id: StringName) -> bool:
	for control: Control in ordered:
		if (
			control.has_meta(&"action_id")
			and StringName(control.get_meta(&"action_id")) == action_id
		):
			return true
	return false


func _ordered_has_name(ordered: Array, control_name: StringName) -> bool:
	for control: Control in ordered:
		if control.name == control_name:
			return true
	return false


func _ordered_has_meta(ordered: Array, meta_name: StringName) -> bool:
	for control: Control in ordered:
		if control.has_meta(meta_name):
			return true
	return false


func _tab_to_action(harness: Variant, action_id: StringName) -> bool:
	return await _tab_to(harness, func(control: Control) -> bool:
		return (
			control is Button
			and control.has_meta(&"action_id")
			and StringName(control.get_meta(&"action_id")) == action_id
		)
	)


func _tab_to_meta(harness: Variant, meta_name: StringName) -> bool:
	return await _tab_to(harness, func(control: Control) -> bool:
		return control.has_meta(meta_name)
	)


func _tab_to_name(harness: Variant, control_name: StringName) -> bool:
	return await _tab_to(harness, func(control: Control) -> bool:
		return control.name == control_name
	)


func _tab_to(harness: Variant, predicate: Callable) -> bool:
	for _attempt: int in range(120):
		var screen := Support.active_screen(harness)
		if screen == null or screen.route_kind != &"RUN_PREPARE":
			return false
		var focused := _focus_owner(harness)
		if focused == null:
			# Headless GUT has no focused OS window, so activate_live() cannot retain
			# its deferred first focus. Seed that first stop from the production
			# graph; every functional transition after this remains InputEvent-driven.
			var ordered := screen.call(&"_ordered_focus_controls") as Array
			if ordered.is_empty():
				return false
			(ordered[0] as Control).grab_focus()
			await wait_process_frames(1)
			focused = _focus_owner(harness)
		if focused is Control and predicate.call(focused as Control):
			return true
		await _press_action(&"ui_focus_next")
		await wait_process_frames(1)
	return false


func _select_unit_with_keyboard(harness: Variant, unit_instance_id: String) -> bool:
	if not await _tab_to_name(harness, &"BuildUnitSelector"):
		return false
	var selector := _focus_owner(harness) as ItemList
	if selector == null:
		return false
	if not await _select_metadata_with_keyboard(selector, unit_instance_id):
		return false
	await wait_process_frames(2)
	return str(_selected_metadata(selector)) == unit_instance_id


func _select_metadata_with_keyboard(selector: ItemList, expected: String) -> bool:
	if str(_selected_metadata(selector)) == expected:
		return true
	var target_index := _metadata_index(selector, expected)
	if target_index < 0:
		return false
	# Focus entry selects row zero; physical Down events traverse the custom W
	# selector and the native equipment list without direct screen calls.
	for _step: int in range(target_index):
		await _press_key(KEY_DOWN)
	await wait_process_frames(2)
	return str(_selected_metadata(selector)) == expected


func _metadata_index(selector: ItemList, expected: String) -> int:
	for index: int in range(selector.item_count):
		if str(selector.get_item_metadata(index)) == expected:
			return index
	return -1


func _selected_metadata(selector: ItemList) -> Variant:
	var selected := selector.get_selected_items()
	return selector.get_item_metadata(selected[0]) if not selected.is_empty() else null


func _press_key(keycode: Key, unicode_value: int = 0) -> void:
	var pressed := InputEventKey.new()
	pressed.keycode = keycode
	pressed.physical_keycode = keycode
	pressed.unicode = unicode_value
	pressed.pressed = true
	pressed.echo = false
	Input.parse_input_event(pressed)
	await wait_process_frames(1)
	var released := pressed.duplicate() as InputEventKey
	released.pressed = false
	Input.parse_input_event(released)
	await wait_process_frames(1)


func _press_action(action_id: StringName) -> void:
	var pressed := InputEventAction.new()
	pressed.action = action_id
	pressed.pressed = true
	get_viewport().push_input(pressed, true)
	await wait_process_frames(1)
	var released := pressed.duplicate() as InputEventAction
	released.pressed = false
	get_viewport().push_input(released, true)
	await wait_process_frames(1)


func _focus_owner(harness: Variant) -> Control:
	var screen := Support.active_screen(harness)
	return (
		screen.get_viewport().gui_get_focus_owner()
		if screen != null and screen.get_viewport() != null
		else null
	)


func _focus_diagnostic(harness: Variant, target: StringName) -> String:
	var owner := _focus_owner(harness)
	var owner_path := String(owner.get_path()) if owner != null else "<none>"
	var screen := Support.active_screen(harness)
	var controls: Array = screen.call(&"_ordered_focus_controls") if screen != null else []
	var names := PackedStringArray()
	for control: Control in controls:
		names.append(String(control.name))
	return "keyboard focus did not reach %s; owner=%s; order=%s" % [
		String(target), owner_path, ",".join(names)
	]


func _wait_for_prepare_inventory(harness: Variant, item_instance_id: String) -> bool:
	for _frame: int in range(120):
		var screen := Support.active_screen(harness)
		var snapshot := _snapshot(harness)
		if (
			screen != null
			and screen.route_kind == &"RUN_PREPARE"
			and snapshot != null
			and snapshot.roster != null
			and snapshot.roster.inventory_item_instance_ids.has(item_instance_id)
			and screen.find_child("InventorySelector", true, false) != null
		):
			return true
		await wait_process_frames(1)
	return false


func _wait_for_purchased_unit(harness: Variant, existing_ids: Array[String]) -> String:
	for _frame: int in range(180):
		var snapshot := _snapshot(harness)
		if snapshot != null and snapshot.roster != null:
			for unit: UnitInstance in snapshot.roster.unit_instances:
				if not existing_ids.has(unit.instance_id):
					return unit.instance_id
		await wait_process_frames(1)
	return ""


func _wait_for_unit_on_board(harness: Variant, unit_instance_id: String) -> bool:
	for _frame: int in range(120):
		var snapshot := _snapshot(harness)
		if snapshot != null and snapshot.roster != null:
			for placement: BoardPlacementState in snapshot.roster.board.placements:
				if placement.unit_instance_id == unit_instance_id:
					return true
		await wait_process_frames(1)
	return false


func _wait_for_equipped_item(
	harness: Variant,
	unit_instance_id: String,
	item_instance_id: String
) -> bool:
	for _frame: int in range(180):
		var snapshot := _snapshot(harness)
		if _unit_has_item(snapshot, unit_instance_id, item_instance_id):
			return true
		await wait_process_frames(1)
	return false


func _wait_for_route(harness: Variant, route_kind: StringName, frames: int) -> bool:
	for _frame: int in range(frames):
		var screen := Support.active_screen(harness)
		if screen != null and screen.route_kind == route_kind:
			return true
		await wait_process_frames(1)
	return false


func _snapshot(harness: Variant) -> RunPresentationSnapshot:
	var result: RunPresentationSessionResult = harness.root.current_run_presentation()
	return result.session.snapshot() if result != null and result.ok else null


func _unit_ids(snapshot: RunPresentationSnapshot) -> Array[String]:
	var result: Array[String] = []
	if snapshot != null and snapshot.roster != null:
		for unit: UnitInstance in snapshot.roster.unit_instances:
			result.append(unit.instance_id)
	return result


func _unit_has_item(
	snapshot: RunPresentationSnapshot,
	unit_instance_id: String,
	item_instance_id: String
) -> bool:
	if snapshot == null or snapshot.roster == null:
		return false
	for unit: UnitInstance in snapshot.roster.unit_instances:
		if unit.instance_id == unit_instance_id:
			return unit.equipment_instance_ids.has(item_instance_id)
	return false


func _equip_failure_diagnostic(harness: Variant) -> String:
	var screen := Support.active_screen(harness)
	if screen == null:
		return "equip failed after route replacement: screen missing"
	var result: Variant = screen.last_control_result()
	if result == null:
		return "equip failed without a typed control result"
	var error: Variant = result.get("error") if result is Object else null
	var source := str(error.get("source_code")) if error is Object else ""
	var incompatible := str(error.get("incompatible_marker")) if error is Object else ""
	return "equip failed: source=%s incompatible=%s" % [source, incompatible]
