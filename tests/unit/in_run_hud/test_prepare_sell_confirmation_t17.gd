extends GutTest


class SellPrepareStub:
	extends RunPrepareScreen

	var requires_confirmation: bool = false
	var sell_dispatch_count: int = 0
	var sell_rejection_code: StringName = &""
	var selected_id: String = "u.stub"
	var dispatched_ids: Array[String] = []


	func selected_unit_requires_sell_confirmation() -> bool:
		return requires_confirmation


	func selected_unit_inspection_available() -> bool:
		return true


	func selected_unit_instance_id() -> String:
		return selected_id


	func selected_unit_sell_quote() -> ShopQuoteSnapshot:
		var quote := ShopQuoteSnapshot.new()
		quote.action = &"sell"
		if not sell_rejection_code.is_empty():
			quote.rejection_code = sell_rejection_code
			return quote
		quote.available = true
		quote.affordable = true
		quote.quotable = true
		quote.gold_gain = 3
		return quote


	func sell_selected_unit() -> RunPresentationResult:
		return sell_unit_by_instance_id(selected_id)


	func sell_unit_by_instance_id(unit_id: String) -> RunPresentationResult:
		sell_dispatch_count += 1
		dispatched_ids.append(unit_id)
		return RunPresentationResult.failure(DiagnosticError.new(
			&"TEST_SELL_DISPATCHED",
			&"error.presentation.action_not_available"
		))


func test_one_star_unequipped_sells_without_modal() -> void:
	var harness := _screen_harness(false)
	var screen := harness[0] as ProductionScreen
	var composition := harness[1] as SellPrepareStub
	var trigger := harness[2] as Button

	screen.call(&"_on_action_pressed", trigger)
	assert_eq(composition.sell_dispatch_count, 1)
	assert_null(screen.get_node_or_null(^"SellUnitConfirmation"))


func test_high_value_sell_cancel_is_zero_dispatch_and_restores_background() -> void:
	var harness := _screen_harness(true)
	var screen := harness[0] as ProductionScreen
	var composition := harness[1] as SellPrepareStub
	var trigger := harness[2] as Button

	screen.call(&"_on_action_pressed", trigger)
	assert_eq(composition.sell_dispatch_count, 0)
	assert_not_null(screen.get_node_or_null(^"SellUnitConfirmation"))
	assert_true(trigger.disabled)
	var cancel := _modal_button(screen, &"run.menu.cancel")
	assert_not_null(cancel)
	if cancel == null:
		return
	screen.call(&"_on_action_pressed", cancel)
	assert_eq(composition.sell_dispatch_count, 0)
	assert_null(screen.get_node_or_null(^"SellUnitConfirmation"))
	assert_false(trigger.disabled)
	assert_eq(trigger.focus_mode, Control.FOCUS_ALL)


func test_high_value_sell_confirm_dispatches_original_action_exactly_once() -> void:
	var harness := _screen_harness(true)
	var screen := harness[0] as ProductionScreen
	var composition := harness[1] as SellPrepareStub
	var trigger := harness[2] as Button

	screen.call(&"_on_action_pressed", trigger)
	assert_eq(composition.sell_dispatch_count, 0)
	composition.selected_id = "u.changed_after_modal"
	var confirm := _modal_button(screen, &"run.menu.confirm")
	assert_not_null(confirm)
	if confirm == null:
		return
	screen.call(&"_on_action_pressed", confirm)
	assert_eq(composition.sell_dispatch_count, 1)
	assert_eq(composition.dispatched_ids, ["u.stub"])
	assert_null(screen.get_node_or_null(^"SellUnitConfirmation"))
	assert_false(bool(screen.get("_modal_open")))


func test_rejected_and_unknown_quotes_keep_sell_fail_closed_with_named_copy() -> void:
	for row: Array in [
		[&"SHOP_OFFER_STALE", &"error.shop.offer_stale", "報價失效"],
		[&"SHOP_UNKNOWN_TEST", &"error.shop.input_invalid", "無法操作"],
	]:
		var harness := _screen_harness(false)
		var screen := harness[0] as ProductionScreen
		var composition := harness[1] as SellPrepareStub
		var trigger := harness[2] as Button
		composition.sell_rejection_code = row[0]
		screen.call(&"_apply_prepare_shop_quote_controls")
		assert_true(trigger.disabled)
		assert_eq(trigger.get_meta(&"shop_quote_message_key"), row[1])
		assert_true(trigger.tooltip_text.contains(row[2]))
		assert_eq(composition.sell_dispatch_count, 0)


class LiveSellSession:
	extends RunPresentationSession

	var supplied_snapshot: RunPresentationSnapshot
	var dispatched_ids: Array[String] = []
	var sell_quote_calls: int = 0


	func configure(snapshot: RunPresentationSnapshot) -> void:
		supplied_snapshot = snapshot.deep_clone()


	func snapshot() -> RunPresentationSnapshot:
		return supplied_snapshot.deep_clone()


	func shop_refresh_quote() -> ShopQuoteSnapshot:
		var quote := ShopQuoteSnapshot.new()
		quote.action = &"refresh"
		quote.available = true
		quote.affordable = true
		quote.quotable = true
		return quote


	func shop_buy_xp_quote() -> ShopXpQuoteSnapshot:
		var quote := ShopXpQuoteSnapshot.new()
		quote.available = true
		quote.affordable = true
		quote.quotable = true
		return quote


	func shop_economy_status() -> ShopEconomySnapshot:
		var result := ShopEconomySnapshot.new()
		result.gold = 20
		result.level = 2
		result.xp_required_for_next_level = 4
		result.odds_tier_basis_points = [10000]
		return result


	func shop_sell_quote(unit_instance_id: String) -> ShopQuoteSnapshot:
		sell_quote_calls += 1
		var quote := ShopQuoteSnapshot.new()
		quote.action = &"sell"
		quote.available = unit_instance_id in ["u.a", "u.b"]
		quote.affordable = quote.available
		quote.quotable = quote.available
		quote.gold_gain = 9 if unit_instance_id == "u.a" else 1
		quote.rejection_code = (
			&"" if quote.available else &"SHOP_UNIT_MISSING"
		)
		return quote


	func trait_progress() -> Array[TraitProgressSnapshot]:
		return []


	func try_committed_board_preview() -> BoardDraftPreviewSnapshot:
		return null


	func dispatch(intent: RunPresentationIntent) -> RunPresentationResult:
		if intent != null and intent.kind == RunPresentationIntent.Kind.SELL_UNIT:
			dispatched_ids.append(intent.unit_instance_id)
		return RunPresentationResult.success(supplied_snapshot)


func test_formal_live_route_captures_unit_identity_and_freezes_background() -> void:
	var snapshot := _live_snapshot(true)
	var session := LiveSellSession.new()
	session.configure(snapshot)
	var harness := _formal_live_harness(snapshot, session)
	var screen := harness[0] as ProductionScreen
	var prepare := harness[1] as RunPrepareScreen
	var trigger := harness[2] as Button
	var selector := prepare.find_child("BuildUnitSelector", true, false) as ItemList
	assert_not_null(selector)
	if selector == null:
		return
	var a_index := _metadata_index(selector, "u.a")
	var b_index := _metadata_index(selector, "u.b")
	selector.select(a_index)
	selector.item_selected.emit(a_index)
	screen.call(&"_on_action_pressed", trigger)
	assert_eq(session.dispatched_ids, [])
	assert_not_null(screen.get_node_or_null(^"SellUnitConfirmation"))
	assert_not_null(screen.get_node_or_null(^"ModalInputBlocker"))
	assert_eq(prepare.process_mode, Node.PROCESS_MODE_DISABLED)
	assert_eq(prepare.focus_behavior_recursive, Control.FOCUS_BEHAVIOR_DISABLED)
	assert_false(screen.open_system_menu(), "modal owns ESC/system-menu precedence")
	var confirm_before := _modal_button(screen, &"run.menu.confirm")
	var cancel_before := _modal_button(screen, &"run.menu.cancel")
	assert_not_null(confirm_before)
	assert_not_null(cancel_before)
	if confirm_before != null and cancel_before != null:
		assert_eq(confirm_before.get_node(confirm_before.focus_next), cancel_before)
		assert_eq(cancel_before.get_node(cancel_before.focus_next), confirm_before)

	# Adversarial programmatic selection/world targeting simulates every lower
	# layer changing after open. Confirmation must still own the captured A id.
	selector.select(b_index)
	selector.item_selected.emit(b_index)
	prepare.call(&"_on_world_unit_targeted", "u.b")
	var confirm := _modal_button(screen, &"run.menu.confirm")
	assert_not_null(confirm)
	if confirm == null:
		return
	screen.call(&"_on_action_pressed", confirm)
	assert_eq(session.dispatched_ids, ["u.a"])
	assert_eq(prepare.process_mode, Node.PROCESS_MODE_INHERIT)
	assert_ne(prepare.focus_behavior_recursive, Control.FOCUS_BEHAVIOR_DISABLED)
	assert_null(screen.get_node_or_null(^"SellUnitConfirmation"))


func test_formal_live_route_missing_inspection_is_fail_closed() -> void:
	var snapshot := _live_snapshot(false)
	var session := LiveSellSession.new()
	session.configure(snapshot)
	var harness := _formal_live_harness(snapshot, session)
	var screen := harness[0] as ProductionScreen
	var prepare := harness[1] as RunPrepareScreen
	var trigger := harness[2] as Button
	var selector := prepare.find_child("BuildUnitSelector", true, false) as ItemList
	assert_not_null(selector)
	if selector == null:
		return
	selector.select(_metadata_index(selector, "u.a"))
	selector.item_selected.emit(_metadata_index(selector, "u.a"))
	assert_true(trigger.disabled)
	assert_eq(
		trigger.get_meta(&"shop_quote_message_key"),
		&"error.presentation.action_not_available"
	)
	screen.call(&"_on_action_pressed", trigger)
	assert_eq(session.dispatched_ids, [])
	assert_null(screen.get_node_or_null(^"SellUnitConfirmation"))


func _screen_harness(requires_confirmation: bool) -> Array:
	var screen := ProductionScreen.new()
	screen.route_kind = &"RUN_PREPARE"
	add_child_autofree(screen)
	var localized := {
		&"prepare.sell": "出售",
		&"run.menu.confirm": "確認",
		&"run.menu.cancel": "取消",
		&"error.shop.offer_stale": "報價失效",
		&"error.shop.input_invalid": "無法操作",
	}
	screen.set(
		"_context",
		StagedScreenContext.new(
			&"RUN_PREPARE", null, null, &"zh_TW", localized
		)
	)
	var live := ProductionLiveScreenContext.new()
	live.action_port = ProductionScreenActionPort.new()
	screen.set("_live_context", live)
	screen.set("_live_active", true)

	var composition := SellPrepareStub.new()
	composition.name = "Composition"
	composition.requires_confirmation = requires_confirmation
	screen.add_child(composition)
	var actions := Control.new()
	actions.name = "Actions"
	screen.add_child(actions)
	var trigger := Button.new()
	trigger.name = "SellAction"
	trigger.focus_mode = Control.FOCUS_ALL
	trigger.set_meta(&"action_id", &"prepare.sell")
	actions.add_child(trigger)
	return [screen, composition, trigger]


func _formal_live_harness(
	snapshot: RunPresentationSnapshot,
	session: LiveSellSession
) -> Array:
	var screen := ProductionScreen.new()
	screen.route_kind = &"RUN_PREPARE"
	add_child_autofree(screen)
	screen.set("_context", StagedScreenContext.new(
		&"RUN_PREPARE", snapshot, null, &"zh_TW", _localized_text()
	))
	var prepare := RunPrepareScreen.new()
	prepare.name = "Composition"
	screen.add_child(prepare)
	var actions := Control.new()
	actions.name = "Actions"
	screen.add_child(actions)
	var trigger := Button.new()
	trigger.name = "SellAction"
	trigger.focus_mode = Control.FOCUS_ALL
	trigger.set_meta(&"action_id", &"prepare.sell")
	actions.add_child(trigger)
	var registry := LiveScreenLeaseRegistry.new()
	var lease := registry.activate(AppStateMachine.State.RUN, 17)
	var intent_port := LiveScreenIntentPort.new(lease, registry, session)
	var action_port := ProductionScreenActionPort.new(lease, registry, {})
	var live := ProductionLiveScreenContext.new(
		&"RUN_PREPARE", snapshot, null, action_port, null, intent_port
	)
	assert_eq(screen.prepare_live_binding(live), &"")
	screen.activate_live()
	return [screen, prepare, trigger, registry]


func _live_snapshot(include_a_inspection: bool) -> RunPresentationSnapshot:
	var result := RunPresentationSnapshot.new()
	result.run_id = &"run.t17.formal"
	result.app_phase = &"PREPARE"
	result.manifest_digest = "manifest.t17.formal"
	var placements: Array[BoardPlacementState] = [
		BoardPlacementState.new(0, 0, "u.a"),
	]
	var bench: Array[String] = ["u.b"]
	var empty_equipment: Array[String] = []
	var equipped: Array[String] = ["item.a"]
	var units: Array[UnitInstance] = [
		UnitInstance.new("u.a", &"unit.a", 2, equipped, U64Bits.zero()),
		UnitInstance.new("u.b", &"unit.b", 1, empty_equipment, U64Bits.zero()),
	]
	var items: Array[ItemInstanceState] = [
		ItemInstanceState.new(
			"item.a", &"equipment.a", OptionalStringValue.new("u.a"), U64Bits.zero()
		),
	]
	var empty_ids: Array[String] = []
	var relics: Array[RelicSlotState] = []
	for index: int in range(5):
		relics.append(RelicSlotState.new(index, null))
	result.roster = RosterState.new(
		BoardState.new(placements), bench, units, items, empty_ids, empty_ids, relics
	)
	var offers: Array[ShopOffer] = []
	result.economy = EconomyState.new(20, 2, 0, 0, 0, 0, offers)
	var issues: Array[BoardValidationIssue] = []
	result.board_validation_report = BoardValidationReport.new(2, issues)
	if include_a_inspection:
		result.prepare_unit_inspections.append(
			_inspection("u.a", &"unit.a", 2, equipped)
		)
	result.prepare_unit_inspections.append(
		_inspection("u.b", &"unit.b", 1, empty_equipment)
	)
	return result


func _inspection(
	instance_id: String,
	def_id: StringName,
	star: int,
	equipment: Array[String]
) -> PrepareUnitInspectionSnapshot:
	var inspection := PrepareUnitInspectionSnapshot.new()
	inspection.unit_instance_id = instance_id
	inspection.unit_id = def_id
	inspection.unit_def_id = def_id
	inspection.star = star
	inspection.cost_tier = 1
	inspection.equipment_instance_ids.assign(equipment)
	return inspection


func _metadata_index(selector: ItemList, expected: String) -> int:
	for index: int in range(selector.item_count):
		if String(selector.get_item_metadata(index)) == expected:
			return index
	return -1


func _localized_text() -> Dictionary:
	return {
		&"prepare.sell": "出售",
		&"run.menu.confirm": "確認",
		&"run.menu.cancel": "取消",
		&"error.presentation.action_not_available": "目前無法執行",
		&"error.shop.input_invalid": "無法操作",
		&"prepare.resource.level_xp": "等級",
		&"prepare.resource.level_xp_max": "已達上限",
		&"prepare.resource.gold": "金幣",
		&"prepare.resource.capacity": "人口",
		&"prepare.resource.win_streak": "連勝",
		&"prepare.resource.loss_streak": "連敗",
		&"prepare.resource.shop_odds": "費用機率",
		&"prepare.panel.units": "單位",
		&"combat.inspection.none": "無",
	}


func _modal_button(screen: ProductionScreen, action_id: StringName) -> Button:
	for node: Node in screen.find_children("*", "Button", true, false):
		var button := node as Button
		if button != null and button.get_meta(&"action_id", &"") == action_id:
			return button
	return null
