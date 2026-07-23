extends GutTest

## T06 (specs/build-systems) — 經濟型遺物在 ShopService 的 shop odds/價格決策點生效。
## Covers：REQ-RELIC-001、S4-AC-011（經濟型於 shop 決策點生效、決定性）。
## 依據 design.md §6：「經濟 -> IncomeService/ShopService 決策點 -> RunRelicTable ...
## 與 shop odds/價格決策前，依槽序套用 intent」。
##
## 假設聲明（見 test_run_relic_table_operations.gd 的總說明）：economy 類 RunRelicRule 的
## kind == &"shop_discount"（W2-F3 前為 add_gold，裁決後拆分：add_gold 只供 income、
## shop_discount 只供 shop）之 run_operations.amount 加總，做為每筆商店 offer 的 flat 折扣
## （maxi(1, base_cost - bonus)，下限 1 金，不得折成 0 或負值）。GenerateOffersRequest／
## RefreshShopRequest 各自新增兩個尾端可選建構參數 relic_table/active_relic_ids（預設
## null/[]），對既有呼叫端（test_shop_service.gd 等）折扣等於 0、完全不改變既有行為。
## odds（抽取哪個 tier/unit）本身不受影響——本片只鎖定「價格」子點，tier 機率調整不在此鎖定
## （design.md 對 shop 只寫「odds/價格」，未給 odds 具體調整規則，屬可另立任務的開放點）。

func test_baseline_without_relic_params_matches_existing_shop_cost() -> void:
	var catalog := _catalog_with_unit_cost(5)
	var generated := ShopService.new().generate_offers(GenerateOffersRequest.new(
		&"run_fixture", &"node_fixture", EconomyState.new(50, 3, 0, 0, 0, 0, []),
		catalog.create_initial_pool(), EconomyTestFixture.empty_roster(),
		EconomyTestFixture.empty_owners(), EconomyTestFixture.shop_rng(),
		U64Bits.zero(), U64Bits.one(), catalog
	))
	assert_true(generated.ok)
	if not generated.ok:
		return
	for offer: ShopOffer in generated.transaction.economy_state.shop_offers:
		assert_eq(offer.cost, 5)

func test_generate_offers_applies_economy_relic_discount_to_every_offer_cost() -> void:
	var catalog := _catalog_with_unit_cost(5)
	var table := RunRelicTable.new(EconomyTestFixture.MANIFEST, [_economy_rule(&"relic.eco_a", 2)])
	var generated := ShopService.new().generate_offers(GenerateOffersRequest.new(
		&"run_fixture", &"node_fixture", EconomyState.new(50, 3, 0, 0, 0, 0, []),
		catalog.create_initial_pool(), EconomyTestFixture.empty_roster(),
		EconomyTestFixture.empty_owners(), EconomyTestFixture.shop_rng(),
		U64Bits.zero(), U64Bits.one(), catalog, table, [&"relic.eco_a"]
	))
	assert_true(generated.ok)
	if not generated.ok:
		return
	assert_eq(generated.transaction.economy_state.shop_offers.size(), 5)
	for offer: ShopOffer in generated.transaction.economy_state.shop_offers:
		assert_eq(offer.cost, 3, "5 base cost - 2 relic bonus")

func test_generate_offers_discount_floors_at_one_gold() -> void:
	var catalog := _catalog_with_unit_cost(1)
	var table := RunRelicTable.new(EconomyTestFixture.MANIFEST, [_economy_rule(&"relic.eco_a", 10)])
	var generated := ShopService.new().generate_offers(GenerateOffersRequest.new(
		&"run_fixture", &"node_fixture", EconomyState.new(50, 3, 0, 0, 0, 0, []),
		catalog.create_initial_pool(), EconomyTestFixture.empty_roster(),
		EconomyTestFixture.empty_owners(), EconomyTestFixture.shop_rng(),
		U64Bits.zero(), U64Bits.one(), catalog, table, [&"relic.eco_a"]
	))
	assert_true(generated.ok)
	if not generated.ok:
		return
	for offer: ShopOffer in generated.transaction.economy_state.shop_offers:
		assert_eq(offer.cost, 1, "discount must floor at 1 gold, never 0 or negative")

func test_refresh_shop_applies_the_same_economy_relic_discount() -> void:
	var catalog := _catalog_with_unit_cost(5)
	var table := RunRelicTable.new(EconomyTestFixture.MANIFEST, [_economy_rule(&"relic.eco_a", 2)])
	var generated := ShopService.new().generate_offers(GenerateOffersRequest.new(
		&"run_fixture", &"node_fixture", EconomyState.new(50, 3, 0, 0, 0, 0, []),
		catalog.create_initial_pool(), EconomyTestFixture.empty_roster(),
		EconomyTestFixture.empty_owners(), EconomyTestFixture.shop_rng(),
		U64Bits.zero(), U64Bits.one(), catalog, table, [&"relic.eco_a"]
	))
	assert_true(generated.ok)
	if not generated.ok:
		return
	var refreshed := ShopService.new().quote_refresh(RefreshShopRequest.new(
		&"run_fixture", &"node_fixture", generated.transaction.economy_state,
		generated.transaction.unit_pool_state, generated.transaction.roster_state,
		generated.transaction.reservation_owners, generated.transaction.next_shop_rng_snapshot,
		generated.transaction.next_transaction_serial, generated.transaction.next_unit_serial,
		catalog, table, [&"relic.eco_a"]
	))
	assert_true(refreshed.ok)
	if not refreshed.ok:
		return
	for offer: ShopOffer in refreshed.transaction.economy_state.shop_offers:
		assert_eq(offer.cost, 3, "refresh must re-apply the same economy relic discount as generate")

func test_route_category_relic_does_not_affect_shop_price() -> void:
	var catalog := _catalog_with_unit_cost(5)
	var route_operation := RunRelicOperationRule.new()
	route_operation.operation_index = 0
	route_operation.kind = &"add_gold"
	route_operation.amount = 50
	route_operation.claim_scope = &"once_per_node"
	var route_rule := RunRelicRule.new()
	route_rule.relic_id = &"relic.route_a"
	route_rule.category = &"route"
	route_rule.effect_ids = [&"effect.fixture"]
	route_rule.run_operations = [route_operation]
	var table := RunRelicTable.new(EconomyTestFixture.MANIFEST, [route_rule])
	var generated := ShopService.new().generate_offers(GenerateOffersRequest.new(
		&"run_fixture", &"node_fixture", EconomyState.new(50, 3, 0, 0, 0, 0, []),
		catalog.create_initial_pool(), EconomyTestFixture.empty_roster(),
		EconomyTestFixture.empty_owners(), EconomyTestFixture.shop_rng(),
		U64Bits.zero(), U64Bits.one(), catalog, table, [&"relic.route_a"]
	))
	assert_true(generated.ok)
	if not generated.ok:
		return
	for offer: ShopOffer in generated.transaction.economy_state.shop_offers:
		assert_eq(offer.cost, 5, "a route-category relic must never discount shop prices")

func _catalog_with_unit_cost(cost: int) -> EconomyExpeditionCatalog:
	var base := EconomyTestFixture.catalog()
	var units: Array[ShopUnitRule] = [
		ShopUnitRule.new(&"unit.test_a", 1, cost),
		ShopUnitRule.new(&"unit.test_b", 1, cost),
	]
	var nodes: Array[MapNodeRule] = []
	for kind: int in range(7):
		nodes.append_array(base.map_nodes_for(kind))
	return EconomyExpeditionCatalog.new(base.manifest_digest_value(), base.config(), units, nodes)

func _economy_rule(relic_id: StringName, add_gold_amount: int) -> RunRelicRule:
	var operation := RunRelicOperationRule.new()
	operation.operation_index = 0
	# W2-F3：shop 折扣改由 economy×shop_discount 消費（income 仍走 add_gold）。
	operation.kind = &"shop_discount"
	operation.amount = add_gold_amount
	operation.claim_scope = &"once_per_node"
	var rule := RunRelicRule.new()
	rule.relic_id = relic_id
	rule.category = &"economy"
	rule.effect_ids = [&"effect.fixture"]
	rule.run_operations = [operation]
	return rule
