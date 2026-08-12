extends GutTest


class CapturingIntentPort:
	extends LiveScreenIntentPort

	var intents: Array[RunPresentationIntent] = []
	var _response: RunPresentationSnapshot


	func _init(snapshot: RunPresentationSnapshot) -> void:
		_response = snapshot.deep_clone()


	func dispatch(intent: RunPresentationIntent) -> RunPresentationResult:
		intents.append(intent.deep_clone())
		var canonical := _response.deep_clone()
		if intent.kind == RunPresentationIntent.Kind.COMMIT_BOARD_LAYOUT:
			canonical.roster.board = intent.board.deep_clone()
			canonical.roster.bench_unit_instance_ids.assign(
				intent.bench_unit_instance_ids
			)
		_response = canonical.deep_clone()
		return RunPresentationResult.success(canonical)


func test_drag_button_and_stable_focus_w_commit_the_same_canonical_layout() -> void:
	var button := _fixture()
	var button_screen := button["screen"] as RunPrepareScreen
	var button_port := button["port"] as CapturingIntentPort
	var bench_selector := button_screen.find_child(
		"BenchSelector", true, false
	) as ItemList
	assert_not_null(bench_selector)
	if bench_selector == null:
		return
	bench_selector.select(0)
	assert_true(button_screen.move_selected_to_board().ok)
	assert_true(button_screen.commit_board_draft().ok)

	var drag := _fixture()
	var drag_screen := drag["screen"] as RunPrepareScreen
	var drag_port := drag["port"] as CapturingIntentPort
	drag_screen.call(
		&"_on_world_unit_dropped",
		"bench_a",
		Vector2i(1, 0)
	)

	var keyboard := _fixture()
	var keyboard_screen := keyboard["screen"] as RunPrepareScreen
	var keyboard_port := keyboard["port"] as CapturingIntentPort
	var focused_cell := keyboard_screen.find_child(
		"BenchCell0", true, false
	) as PrepareUnitDragButton
	assert_not_null(focused_cell)
	if focused_cell == null:
		return
	assert_eq(focused_cell.get_meta(&"drag_target_kind"), &"bench")
	assert_eq(focused_cell.get_meta(&"bench_slot"), 0)
	assert_eq(focused_cell.get_meta(&"unit_instance_id"), "bench_a")
	focused_cell.focus_entered.emit()
	var toggle := InputEventAction.new()
	toggle.action = &"prepare_quick_toggle_unit"
	toggle.pressed = true
	keyboard_screen.call(&"_unhandled_input", toggle)

	assert_eq(button_port.intents.size(), 1)
	assert_eq(drag_port.intents.size(), 1)
	assert_eq(keyboard_port.intents.size(), 1)
	if (
		button_port.intents.is_empty()
		or drag_port.intents.is_empty()
		or keyboard_port.intents.is_empty()
	):
		return
	for intent: RunPresentationIntent in [
		button_port.intents[0],
		drag_port.intents[0],
		keyboard_port.intents[0],
	]:
		assert_eq(intent.kind, RunPresentationIntent.Kind.COMMIT_BOARD_LAYOUT)
	assert_eq(
		_layout_digest(button_port.intents[0]),
		_layout_digest(drag_port.intents[0])
	)
	assert_eq(
		_layout_digest(button_port.intents[0]),
		_layout_digest(keyboard_port.intents[0])
	)


func test_keyboard_exact_board_target_matches_drag_and_supports_swap() -> void:
	var keyboard := _fixture(false, _swap_snapshot())
	var keyboard_screen := keyboard["screen"] as RunPrepareScreen
	var keyboard_port := keyboard["port"] as CapturingIntentPort
	var units := keyboard_screen.find_child(
		"BuildUnitSelector", true, false
	) as ItemList
	var targets := keyboard_screen.find_child(
		"UnitSelector", true, false
	) as ItemList
	assert_not_null(units)
	assert_not_null(targets)
	if units == null or targets == null:
		return
	assert_eq(targets.item_count, 41)
	assert_eq(targets.get_meta(&"stable_focus_id"), &"prepare.placement_targets")
	assert_eq(
		targets.get_meta(&"target_order"),
		&"board_row_major_then_bench_slot"
	)
	var source_index := _item_index_for_identity(units, "board_a")
	var target_index := _target_index(
		targets,
		&"board",
		Vector2i(1, 0),
		-1
	)
	assert_gte(source_index, 0)
	assert_gte(target_index, 0)
	if source_index < 0 or target_index < 0:
		return
	units.select(source_index)
	units.item_selected.emit(source_index)
	targets.select(target_index)
	targets.item_selected.emit(target_index)
	targets.item_activated.emit(target_index)

	var drag := _fixture(false, _swap_snapshot())
	var drag_screen := drag["screen"] as RunPrepareScreen
	var drag_port := drag["port"] as CapturingIntentPort
	drag_screen.call(
		&"_on_unit_dropped",
		"board_a",
		&"board",
		Vector2i(1, 0),
		-1
	)

	assert_eq(keyboard_port.intents.size(), 1)
	assert_eq(drag_port.intents.size(), 1)
	if keyboard_port.intents.is_empty() or drag_port.intents.is_empty():
		return
	assert_eq(
		_layout_digest(keyboard_port.intents[0]),
		_layout_digest(drag_port.intents[0]),
		"keyboard target activation and world drop must share the same swap draft"
	)
	assert_eq(
		_cell_for(keyboard_port.intents[0].board, "board_a"),
		Vector2i(1, 0)
	)
	assert_eq(
		_cell_for(keyboard_port.intents[0].board, "board_b"),
		Vector2i(0, 0)
	)


func test_keyboard_exact_bench_slot_matches_drag_swap() -> void:
	var keyboard := _fixture()
	var keyboard_screen := keyboard["screen"] as RunPrepareScreen
	var keyboard_port := keyboard["port"] as CapturingIntentPort
	var units := keyboard_screen.find_child(
		"BuildUnitSelector", true, false
	) as ItemList
	var targets := keyboard_screen.find_child(
		"UnitSelector", true, false
	) as ItemList
	assert_not_null(units)
	assert_not_null(targets)
	if units == null or targets == null:
		return
	var source_index := _item_index_for_identity(units, "board_a")
	var target_index := _target_index(
		targets,
		&"bench",
		Vector2i(-1, -1),
		0
	)
	assert_gte(source_index, 0)
	assert_gte(target_index, 0)
	if source_index < 0 or target_index < 0:
		return
	units.select(source_index)
	units.item_selected.emit(source_index)
	targets.select(target_index)
	targets.item_activated.emit(target_index)

	var drag := _fixture()
	var drag_screen := drag["screen"] as RunPrepareScreen
	var drag_port := drag["port"] as CapturingIntentPort
	drag_screen.call(
		&"_on_unit_dropped",
		"board_a",
		&"bench",
		Vector2i(-1, -1),
		0
	)

	assert_eq(keyboard_port.intents.size(), 1)
	assert_eq(drag_port.intents.size(), 1)
	if keyboard_port.intents.is_empty() or drag_port.intents.is_empty():
		return
	assert_eq(
		_layout_digest(keyboard_port.intents[0]),
		_layout_digest(drag_port.intents[0])
	)
	assert_eq(keyboard_port.intents[0].bench_unit_instance_ids, ["board_a"])
	assert_eq(
		_cell_for(keyboard_port.intents[0].board, "bench_a"),
		Vector2i(0, 0),
		"occupied bench target swaps back to the source board cell"
	)


func test_inventory_selector_resolves_only_canonical_inventory_membership() -> void:
	var fixture := _fixture(false, _inventory_membership_snapshot())
	var screen := fixture["screen"] as RunPrepareScreen
	var port := fixture["port"] as CapturingIntentPort
	var inventory := screen.find_child(
		"InventorySelector", true, false
	) as ItemList
	assert_not_null(inventory)
	if inventory == null:
		return
	assert_eq(inventory.item_count, 1)
	assert_eq(inventory.get_item_metadata(0), "inventory_item")
	assert_eq(
		_item_index_for_identity(inventory, "equipped_item"),
		-1,
		"equipped resolver entries must not become inventory drag sources"
	)
	assert_eq(
		_item_index_for_identity(inventory, "overflow_item"),
		-1,
		"overflow resolver entries must remain outside inventory"
	)
	assert_eq(
		_item_index_for_identity(inventory, "missing_resolver_item"),
		-1,
		"canonical id without a resolver entry must fail closed"
	)
	screen.call(&"_on_equipment_dropped", "equipped_item", "board_a")
	screen.call(&"_on_equipment_dropped", "overflow_item", "board_a")
	assert_true(port.intents.is_empty())


func test_real_input_delivery_w_bypasses_build_selector_search_and_guard() -> void:
	var fixture := _fixture(true)
	var screen := fixture["screen"] as RunPrepareScreen
	var route_screen := fixture["route_screen"] as ProductionScreen
	var port := fixture["port"] as CapturingIntentPort
	var units := screen.find_child(
		"BuildUnitSelector", true, false
	) as ItemList
	assert_not_null(units)
	if units == null:
		return
	var source_index := _item_index_for_identity(units, "bench_a")
	assert_gte(source_index, 0)
	if source_index < 0:
		return
	units.select(source_index)
	units.item_selected.emit(source_index)
	units.grab_focus()
	await get_tree().process_frame
	assert_eq(get_viewport().gui_get_focus_owner(), units)

	# Keep focus on the ItemList while simulating a modal owner. The typed
	# selector must claim W before incremental search but still obey the shared
	# background-input guard.
	route_screen.set(&"_modal_open", true)
	Input.parse_input_event(_w_key_event(true))
	await get_tree().process_frame
	Input.parse_input_event(_w_key_event(false))
	await get_tree().process_frame
	assert_true(port.intents.is_empty())

	route_screen.set(&"_modal_open", false)
	Input.parse_input_event(_w_key_event(true))
	await get_tree().process_frame
	Input.parse_input_event(_w_key_event(false))
	await get_tree().process_frame
	assert_eq(
		port.intents.size(),
		1,
		"focused BuildUnitSelector must relay physical W through real GUI input"
	)


func test_real_input_delivery_w_bypasses_placement_target_search() -> void:
	var fixture := _fixture()
	var screen := fixture["screen"] as RunPrepareScreen
	var port := fixture["port"] as CapturingIntentPort
	var targets := screen.find_child("UnitSelector", true, false) as ItemList
	assert_not_null(targets)
	if targets == null:
		return
	var target_index := _target_index(
		targets,
		&"board",
		Vector2i(0, 0),
		-1
	)
	assert_gte(target_index, 0)
	if target_index < 0:
		return
	targets.select(target_index)
	targets.item_selected.emit(target_index)
	targets.grab_focus()
	await get_tree().process_frame
	assert_eq(get_viewport().gui_get_focus_owner(), targets)
	Input.parse_input_event(_w_key_event(true))
	await get_tree().process_frame
	Input.parse_input_event(_w_key_event(false))
	await get_tree().process_frame
	assert_eq(
		port.intents.size(),
		1,
		"focused placement ItemList must relay physical W instead of searching"
	)
	if port.intents.is_empty():
		return
	assert_true(port.intents[0].bench_unit_instance_ids.has("board_a"))


func test_empty_focus_metadata_clears_stale_w_target() -> void:
	var fixture := _fixture()
	var screen := fixture["screen"] as RunPrepareScreen
	var port := fixture["port"] as CapturingIntentPort
	var occupied := screen.find_child("BenchCell0", true, false) as Button
	var empty := screen.find_child("BenchCell1", true, false) as Button
	assert_not_null(occupied)
	assert_not_null(empty)
	if occupied == null or empty == null:
		return
	occupied.focus_entered.emit()
	empty.focus_entered.emit()
	var toggle := InputEventAction.new()
	toggle.action = &"prepare_quick_toggle_unit"
	toggle.pressed = true
	screen.call(&"_unhandled_input", toggle)
	assert_true(port.intents.is_empty())


func test_w_is_blocked_by_system_menu_states_and_confirmation_modal() -> void:
	var fixture := _fixture(true)
	var screen := fixture["screen"] as RunPrepareScreen
	var route_screen := fixture["route_screen"] as ProductionScreen
	var overlay := fixture["overlay"] as SystemMenuOverlay
	var port := fixture["port"] as CapturingIntentPort
	var occupied := screen.find_child("BenchCell0", true, false) as Button
	var units := screen.find_child("BuildUnitSelector", true, false) as ItemList
	var targets := screen.find_child("UnitSelector", true, false) as ItemList
	assert_not_null(occupied)
	assert_not_null(units)
	assert_not_null(targets)
	if occupied == null or units == null or targets == null:
		return
	occupied.focus_entered.emit()
	var source_index := _item_index_for_identity(units, "bench_a")
	var target_index := _target_index(
		targets,
		&"board",
		Vector2i(1, 0),
		-1
	)
	assert_gte(source_index, 0)
	assert_gte(target_index, 0)
	if source_index < 0 or target_index < 0:
		return
	units.select(source_index)
	units.item_selected.emit(source_index)
	var before_digest := _snapshot_layout_digest(port._response)

	assert_true(overlay.open())
	assert_eq(overlay.state_name(), &"ROOT")
	_assert_w_does_not_dispatch(screen, port, before_digest, "ROOT")
	targets.item_activated.emit(target_index)
	assert_true(
		port.intents.is_empty(),
		"exact keyboard placement must not dispatch below system menu"
	)

	assert_true(_press_overlay(overlay, &"system_menu.settings"))
	assert_eq(overlay.state_name(), &"SETTINGS_EMBEDDED")
	_assert_w_does_not_dispatch(screen, port, before_digest, "SETTINGS")
	assert_true(overlay.handle_system_menu_action())

	assert_true(_press_overlay(overlay, &"run.menu"))
	assert_eq(overlay.state_name(), &"CONFIRM_MENU")
	_assert_w_does_not_dispatch(screen, port, before_digest, "CONFIRM_MENU")
	assert_true(overlay.handle_system_menu_action())
	assert_true(overlay.close())

	route_screen.set(&"_modal_open", true)
	assert_true(route_screen.is_background_input_blocked())
	_assert_w_does_not_dispatch(screen, port, before_digest, "confirmation modal")
	targets.item_activated.emit(target_index)
	assert_true(
		port.intents.is_empty(),
		"exact keyboard placement must not dispatch below confirmation modal"
	)
	route_screen.set(&"_modal_open", false)
	assert_false(route_screen.is_background_input_blocked())

	screen.call(&"_unhandled_input", _quick_toggle_event())
	assert_eq(port.intents.size(), 1, "closed overlays restore W input")
	assert_ne(
		_snapshot_layout_digest(port._response),
		before_digest,
		"the first unblocked W commits the canonical board draft"
	)


func test_prepare_button_preview_exposes_source_target_and_non_color_swap_cue() -> void:
	var source := PrepareUnitDragButton.new()
	add_child_autofree(source)
	source.set_meta(&"unit_instance_id", "bench_a")
	source.set_meta(&"drag_target_kind", &"bench")
	source.set_meta(&"bench_slot", 0)
	var target := PrepareUnitDragButton.new()
	add_child_autofree(target)
	target.set_meta(&"unit_instance_id", "bench_b")
	target.set_meta(&"drag_target_kind", &"bench")
	target.set_meta(&"bench_slot", 1)
	var payload: Variant = source.unit_drag_payload()
	assert_true(target._can_drop_data(Vector2.ZERO, payload))
	var preview := target.preview_state()
	assert_eq(preview.get("source_kind"), &"bench")
	assert_eq(preview.get("source_slot"), 0)
	assert_eq(preview.get("target_kind"), &"bench")
	assert_eq(preview.get("target_slot"), 1)
	assert_true(bool(preview.get("swap", false)))


func _fixture(
	with_route_shell: bool = false,
	snapshot_override: RunPresentationSnapshot = null
) -> Dictionary:
	var snapshot := (
		snapshot_override.deep_clone()
		if snapshot_override != null
		else _snapshot()
	)
	var port := CapturingIntentPort.new(snapshot)
	var screen := RunPrepareScreen.new()
	var route_screen: ProductionScreen
	var overlay: SystemMenuOverlay
	if with_route_shell:
		route_screen = ProductionScreen.new()
		route_screen.route_kind = &"RUN_PREPARE"
		add_child_autofree(route_screen)
		overlay = SystemMenuOverlay.new()
		overlay.name = "SystemMenuOverlay"
		route_screen.add_child(overlay)
		overlay.configure(_system_menu_localized())
		route_screen.set(&"_system_menu_overlay", overlay)
		screen.name = "Composition"
		route_screen.add_child(screen)
	else:
		add_child_autofree(screen)
	var issues: Array[BoardValidationIssue] = []
	assert_eq(
		screen.compose(snapshot, BoardValidationReport.new(2, issues), port),
		&""
	)
	return {
		"screen": screen,
		"route_screen": route_screen,
		"overlay": overlay,
		"port": port,
	}


func _snapshot() -> RunPresentationSnapshot:
	var snapshot := RunPresentationSnapshot.new()
	snapshot.run_id = &"run_input_equivalence"
	snapshot.app_phase = &"PREPARE"
	var placements: Array[BoardPlacementState] = [
		BoardPlacementState.new(0, 0, "board_a"),
	]
	var bench: Array[String] = ["bench_a"]
	var no_equipment: Array[String] = []
	var units: Array[UnitInstance] = [
		UnitInstance.new(
			"board_a", &"unit.board", 1, no_equipment, U64Bits.zero()
		),
		UnitInstance.new(
			"bench_a", &"unit.bench", 1, no_equipment, U64Bits.one()
		),
	]
	var items: Array[ItemInstanceState] = []
	var inventory: Array[String] = []
	var overflow: Array[String] = []
	var relics: Array[RelicSlotState] = []
	snapshot.roster = RosterState.new(
		BoardState.new(placements),
		bench,
		units,
		items,
		inventory,
		overflow,
		relics
	)
	var issues: Array[BoardValidationIssue] = []
	snapshot.board_validation_report = BoardValidationReport.new(2, issues)
	return snapshot


func _swap_snapshot() -> RunPresentationSnapshot:
	var snapshot := _snapshot()
	snapshot.roster.board.placements.append(
		BoardPlacementState.new(0, 1, "board_b")
	)
	var equipment: Array[String] = []
	snapshot.roster.unit_instances.append(UnitInstance.new(
		"board_b",
		&"unit.board_b",
		1,
		equipment,
		U64Bits.from_hex("0000000000000002").value
	))
	return snapshot


func _inventory_membership_snapshot() -> RunPresentationSnapshot:
	var snapshot := _snapshot()
	var equipped_ids: Array[String] = ["equipped_item"]
	snapshot.roster.unit_instances[0] = UnitInstance.new(
		"board_a",
		&"unit.board",
		1,
		equipped_ids,
		U64Bits.zero()
	)
	var no_owner: OptionalStringValue
	snapshot.roster.item_instances.assign([
		ItemInstanceState.new(
			"inventory_item",
			&"item.inventory",
			no_owner,
			U64Bits.from_hex("0000000000000010").value
		),
		ItemInstanceState.new(
			"equipped_item",
			&"item.equipped",
			OptionalStringValue.new("board_a"),
			U64Bits.from_hex("0000000000000011").value
		),
		ItemInstanceState.new(
			"overflow_item",
			&"item.overflow",
			no_owner,
			U64Bits.from_hex("0000000000000012").value
		),
	])
	snapshot.roster.inventory_item_instance_ids.assign([
		"inventory_item",
		"missing_resolver_item",
	])
	snapshot.roster.pending_item_overflow.assign(["overflow_item"])
	return snapshot


func _item_index_for_identity(selector: ItemList, identity: String) -> int:
	for index: int in selector.item_count:
		if String(selector.get_item_metadata(index)) == identity:
			return index
	return -1


func _target_index(
	selector: ItemList,
	target_kind: StringName,
	target_cell: Vector2i,
	target_slot: int
) -> int:
	for index: int in selector.item_count:
		var value: Variant = selector.get_item_metadata(index)
		if not value is Dictionary:
			continue
		var target := value as Dictionary
		if (
			StringName(target.get("target_kind", &"")) == target_kind
			and target.get("target_cell", Vector2i(-1, -1)) == target_cell
			and int(target.get("target_slot", -1)) == target_slot
		):
			return index
	return -1


func _cell_for(board: BoardState, unit_id: String) -> Vector2i:
	if board != null:
		for placement: BoardPlacementState in board.placements:
			if placement != null and placement.unit_instance_id == unit_id:
				return Vector2i(placement.logical_x, placement.logical_y)
	return Vector2i(-1, -1)


func _layout_digest(intent: RunPresentationIntent) -> String:
	var placements := PackedStringArray()
	for placement: BoardPlacementState in intent.board.placements:
		placements.append(
			"%d:%d:%s" % [
				placement.logical_y,
				placement.logical_x,
				placement.unit_instance_id,
			]
		)
	placements.sort()
	var bench := PackedStringArray(intent.bench_unit_instance_ids)
	return ("%s#%s" % [",".join(placements), ",".join(bench)]).sha256_text()


func _snapshot_layout_digest(snapshot: RunPresentationSnapshot) -> String:
	var intent := RunPresentationIntent.new(
		RunPresentationIntent.Kind.COMMIT_BOARD_LAYOUT
	)
	intent.board = snapshot.roster.board.deep_clone()
	intent.bench_unit_instance_ids.assign(
		snapshot.roster.bench_unit_instance_ids
	)
	return _layout_digest(intent)


func _assert_w_does_not_dispatch(
	screen: RunPrepareScreen,
	port: CapturingIntentPort,
	expected_digest: String,
	state_label: String
) -> void:
	screen.call(&"_unhandled_input", _quick_toggle_event())
	assert_true(
		port.intents.is_empty(),
		"W must not dispatch while %s owns input" % state_label
	)
	assert_eq(
		_snapshot_layout_digest(port._response),
		expected_digest,
		"%s must preserve the canonical layout digest" % state_label
	)


func _quick_toggle_event() -> InputEventAction:
	var event := InputEventAction.new()
	event.action = &"prepare_quick_toggle_unit"
	event.pressed = true
	return event


func _w_key_event(pressed: bool) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = KEY_W
	event.unicode = 119
	event.pressed = pressed
	event.echo = false
	return event


func _press_overlay(
	overlay: SystemMenuOverlay,
	action_id: StringName
) -> bool:
	for node: Node in overlay.find_children("*", "Button", true, false):
		var button := node as Button
		if (
			button != null
			and button.has_meta(&"action_id")
			and StringName(button.get_meta(&"action_id")) == action_id
		):
			button.pressed.emit()
			return true
	return false


func _system_menu_localized() -> Dictionary:
	return {
		&"system_menu.title": "系統選單",
		&"menu.continue": "繼續遠征",
		&"system_menu.settings": "設定",
		&"run.menu": "返回主選單",
		&"menu.exit": "離開遊戲",
		&"run.menu.status": "返回主選單？",
		&"run.menu.confirm": "確認返回",
		&"run.menu.cancel": "取消",
		&"menu.exit.status": "離開遊戲？",
		&"menu.exit.confirm": "確認離開",
		&"menu.exit.cancel": "取消",
		&"settings.apply": "套用",
		&"settings.back": "返回",
	}
