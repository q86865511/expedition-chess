extends GutTest


class SpySupplySession:
	extends RunPresentationSession

	var item := ItemInstanceState.new(
		"it_supply", &"item_component.alpha", null, U64Bits.one()
	)
	var status := ShopEconomySnapshot.new()

	func _init() -> void:
		status.gold = 17
		status.level = 4

	func forge_inventory_components() -> Array[ItemInstanceState]:
		return [item.deep_clone()]

	func shop_economy_status() -> ShopEconomySnapshot:
		return status.deep_clone()

	func shop_refresh_quote() -> ShopQuoteSnapshot:
		var quote := ShopQuoteSnapshot.new()
		quote.action = &"refresh"
		quote.available = true
		quote.affordable = true
		quote.quotable = true
		quote.gold_cost = 2
		return quote

	func shop_buy_xp_quote() -> ShopXpQuoteSnapshot:
		var quote := ShopXpQuoteSnapshot.new()
		quote.available = true
		quote.xp_gain = 4
		return quote


func test_context_derives_supply_port_without_exposing_session() -> void:
	var registry := LiveScreenLeaseRegistry.new()
	var lease := registry.activate(AppStateMachine.State.RUN, 41)
	var session := SpySupplySession.new()
	var intent := LiveScreenIntentPort.new(lease, registry, session)
	var context := ProductionLiveScreenContext.new(
		&"RUN_PREPARE", RunPresentationSnapshot.new(), null, null, null, intent
	)

	assert_not_null(context.supply_port)
	assert_eq(context.supply_port.shop_economy_status().gold, 17)
	assert_eq(context.supply_port.shop_refresh_quote().gold_cost, 2)
	assert_eq(context.supply_port.shop_buy_xp_quote().xp_gain, 4)

	var first := context.supply_port.forge_inventory_components()
	assert_eq(first.size(), 1)
	first[0].def_id = &"item_component.mutated"
	assert_eq(
		context.supply_port.forge_inventory_components()[0].def_id,
		&"item_component.alpha",
		"每次 supply read 都必須 clone-out"
	)
	assert_eq(session.item.def_id, &"item_component.alpha")


func test_revoked_supply_port_fails_closed_and_reveals_no_previous_values() -> void:
	var registry := LiveScreenLeaseRegistry.new()
	var lease := registry.activate(AppStateMachine.State.RUN, 42)
	var port := LiveScreenSupplyPort.new(lease, registry, SpySupplySession.new())
	assert_eq(port.shop_economy_status().gold, 17)
	registry.revoke(lease)

	assert_true(port.forge_inventory_components().is_empty())
	assert_true(port.forge_recipes_containing(&"item_component.alpha").is_empty())
	assert_null(port.try_forge_pair_recipe("it_a", "it_b"))
	assert_eq(port.shop_economy_status().gold, 0)
	assert_eq(port.shop_refresh_quote().rejection_code, &"SCREEN_NOT_ACTIVE")
	assert_eq(port.shop_buy_xp_quote().rejection_code, &"SCREEN_NOT_ACTIVE")
	assert_eq(port.shop_sell_quote("u_a").rejection_code, &"SCREEN_NOT_ACTIVE")
	var placements: Array[BoardPlacementState] = []
	var bench_ids: Array[String] = []
	assert_null(port.try_board_draft_preview(placements, bench_ids))
	assert_null(port.try_committed_board_preview())
	assert_true(port.trait_progress().is_empty())
