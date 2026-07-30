extends GutTest

## G2 wave2-B M4 regression (fix/g2-ui-review-findings): the formal RUN_PREPARE
## composition rendered raw instance ids for board/bench/shop/inventory/unit
## selectors and the raw BoardValidationIssue enum string for deployment
## issues, with zero localization calls in the whole file even though
## deployment_issue_message_keys() already existed unused. This locks the fix:
## every selector must show resolved display text, never the raw identifier.

const BOARD_UNIT_INSTANCE_ID := "unit.instance.alpha"
const BOARD_UNIT_DEF_ID: StringName = &"unit.test_alpha"
const BENCH_UNIT_INSTANCE_ID := "unit.instance.bravo"
const BENCH_UNIT_DEF_ID: StringName = &"unit.test_bravo"
const ITEM_INSTANCE_ID := "item.instance.component"
const ITEM_DEF_ID: StringName = &"item.test_component"
const OFFER_UNIT_DEF_ID: StringName = &"unit.test_offer"


func test_run_prepare_renders_localized_names_instead_of_raw_ids() -> void:
	var snapshot := _fixture_snapshot()
	var registry := LiveScreenLeaseRegistry.new()
	var lease := registry.activate(AppStateMachine.State.RUN, 4201)
	var session := RunPresentationSession.new()
	var screen := ProductionSceneCatalog.new().instantiate(&"RUN_PREPARE")
	assert_not_null(screen)
	if screen == null:
		return
	autofree(screen)

	var localized_text := {
		&"loc.unit_test_alpha": "測試戰士艾法",
		&"loc.unit_test_bravo": "測試戰士布拉沃",
		&"loc.item_test_component": "測試零件",
		&"loc.unit_test_offer": "測試商品",
		&"error.board.board_over_capacity": "戰場超出人口上限",
	}
	var staged := StagedScreenContext.new(
		&"RUN_PREPARE", snapshot, null, &"zh_TW", localized_text
	)
	assert_eq(screen.bind(staged), &"")
	var live := ProductionLiveScreenContext.new(
		&"RUN_PREPARE",
		snapshot,
		null,
		ProductionScreenActionPort.new(lease, registry, {}),
		LiveScreenNavigationPort.new(),
		LiveScreenIntentPort.new(lease, registry, session)
	)
	assert_eq(screen.prepare_live_binding(live), &"")
	add_child_autofree(screen)
	screen.activate_live()

	var composition := screen.get_node_or_null(^"Composition") as RunPrepareScreen
	assert_not_null(composition)
	if composition == null:
		return

	var board := composition.get_node_or_null(^"BoardSelector") as ItemList
	assert_not_null(board)
	if board != null:
		assert_eq(board.item_count, 1)
		assert_string_contains(board.get_item_text(0), "測試戰士艾法")
		assert_false(
			board.get_item_text(0).contains(BOARD_UNIT_INSTANCE_ID),
			"board selector must not leak the raw unit instance id"
		)

	var bench := composition.get_node_or_null(^"BenchSelector") as ItemList
	assert_not_null(bench)
	if bench != null:
		assert_eq(bench.item_count, 1)
		assert_eq(bench.get_item_text(0), "測試戰士布拉沃")
		assert_false(bench.get_item_text(0).contains(BENCH_UNIT_INSTANCE_ID))

	var shop := composition.get_node_or_null(^"ShopSelector") as ItemList
	assert_not_null(shop)
	if shop != null:
		assert_eq(shop.item_count, 1)
		assert_string_contains(shop.get_item_text(0), "測試商品")
		assert_false(shop.get_item_text(0).contains(String(OFFER_UNIT_DEF_ID)))

	var inventory := composition.get_node_or_null(^"InventorySelector") as ItemList
	assert_not_null(inventory)
	if inventory != null:
		assert_eq(inventory.item_count, 1)
		assert_string_contains(inventory.get_item_text(0), "測試零件")
		assert_false(inventory.get_item_text(0).contains(String(ITEM_DEF_ID)))

	var units := composition.get_node_or_null(^"BuildUnitSelector") as ItemList
	assert_not_null(units)
	if units != null:
		assert_eq(units.item_count, 2)
		var unit_text := units.get_item_text(0) + units.get_item_text(1)
		assert_string_contains(unit_text, "測試戰士艾法")
		assert_string_contains(unit_text, "測試戰士布拉沃")
		assert_false(unit_text.contains(String(BOARD_UNIT_DEF_ID)))
		assert_false(unit_text.contains(String(BENCH_UNIT_DEF_ID)))

	var issues := composition.get_node_or_null(^"DeploymentIssues") as ItemList
	assert_not_null(issues)
	if issues != null:
		assert_eq(issues.item_count, 1)
		assert_eq(issues.get_item_text(0), "戰場超出人口上限")
		assert_ne(issues.get_item_text(0), String(BoardValidationIssue.OVER_CAPACITY))
		assert_eq(
			StringName(issues.get_item_metadata(0)),
			BoardValidationIssue.OVER_CAPACITY,
			"selection metadata must keep the raw code even though display text is localized"
		)


func _fixture_snapshot() -> RunPresentationSnapshot:
	var snapshot := RunPresentationSnapshot.new()
	snapshot.run_id = &"run.g2.wave2b.prepare"
	snapshot.app_phase = &"PREPARE"
	snapshot.manifest_digest = "manifest.g2.wave2b"

	var board_unit := UnitInstance.new(
		BOARD_UNIT_INSTANCE_ID, BOARD_UNIT_DEF_ID, 1, [], U64Bits.one()
	)
	var bench_unit := UnitInstance.new(
		BENCH_UNIT_INSTANCE_ID, BENCH_UNIT_DEF_ID, 1, [], U64Bits.one()
	)
	var placements: Array[BoardPlacementState] = [
		BoardPlacementState.new(0, 0, BOARD_UNIT_INSTANCE_ID),
	]
	var item := ItemInstanceState.new(
		ITEM_INSTANCE_ID, ITEM_DEF_ID, null, U64Bits.one()
	)
	snapshot.roster = RosterState.new(
		BoardState.new(placements),
		[BENCH_UNIT_INSTANCE_ID],
		[board_unit, bench_unit],
		[item],
		[ITEM_INSTANCE_ID],
		[],
		[]
	)

	var shop_owner := ReservationOwnerKeyState.create(
		&"run.g2.wave2b.prepare", &"prepare", &"shop", &"refresh.1", 0, &"owner.shop"
	)
	var shop_offers: Array[ShopOffer] = [
		ShopOffer.new(0, "offer.0", OFFER_UNIT_DEF_ID, 3, 1, shop_owner),
	]
	snapshot.economy = EconomyState.new(10, 9, 0, 0, 0, 1, shop_offers)

	var issues: Array[BoardValidationIssue] = [
		BoardValidationIssue.new(BoardValidationIssue.OVER_CAPACITY),
	]
	snapshot.board_validation_report = BoardValidationReport.new(11, issues)
	return snapshot
