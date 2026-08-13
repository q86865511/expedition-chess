extends GutTest

## IRH-REQ-011／IRH-REQ-014（specs/in-run-hud）-- ShopEconomyViewModel。
##
## 契約：經濟資訊列與商店按鈕的每一個數字都必須來自 ShopService.quote_* 與 pinned
## EconomyConfigRule，呈現層零公式（spec §10.3）。因此本 suite 對每個報價斷言
## 「逐欄位等於直接呼叫 domain 的結果」，並確認拒絕時給的是 domain 的具名 ShopError 碼。

const NODE_ID: String = "node_fixture"
const UNIT_INSTANCE: String = "u_0000000000000201"
const OTHER_MANIFEST: String = \
	"3333333333333333333333333333333333333333333333333333333333333333"


func test_refresh_quote_matches_direct_quote_refresh() -> void:
	var run := _shop_run(EconomyState.new(20, 3, 0, 2, 0, 0, []))
	var catalog := _catalog()
	var view_model := ShopEconomyViewModel.new(_session_for(run), catalog)

	var quote := view_model.refresh_quote()
	var direct := ShopService.new().quote_refresh(_refresh_request(run, catalog))
	assert_true(direct.ok, "前提：直接呼叫 domain 的刷新報價必須成立")
	if not direct.ok:
		return
	assert_true(quote.available)
	assert_true(quote.quotable)
	assert_true(quote.affordable)
	assert_eq(quote.rejection_code, &"")
	assert_eq(quote.gold_before, 20)
	assert_eq(
		quote.gold_cost,
		run.economy_state.gold - direct.transaction.economy_state.gold,
		"刷新成本必須等於 domain 報價的實際扣款"
	)
	assert_eq(quote.gold_cost, 2, "EconomyTestFixture 的 reroll_cost")


func test_refresh_quote_reports_named_gold_insufficient_but_still_prices() -> void:
	var run := _shop_run(EconomyState.new(1, 3, 0, 0, 0, 0, []))
	var view_model := ShopEconomyViewModel.new(_session_for(run), _catalog())

	var quote := view_model.refresh_quote()
	assert_false(quote.available, "金幣不足時不可用")
	assert_eq(quote.rejection_code, ShopError.GOLD_INSUFFICIENT, "必須是 domain 的具名碼")
	assert_true(quote.quotable, "金幣不足仍要能顯示價格")
	assert_eq(quote.gold_cost, 2)
	assert_false(quote.affordable)


func test_buy_xp_quote_matches_domain_level_folding() -> void:
	var run := _shop_run(EconomyState.new(20, 3, 0, 0, 0, 0, []))
	var catalog := _catalog()
	var view_model := ShopEconomyViewModel.new(_session_for(run), catalog)

	var quote := view_model.buy_xp_quote()
	var direct := ShopService.new().quote_buy_xp(_buy_xp_request(run, catalog))
	assert_true(direct.ok, "前提：直接呼叫 domain 的買經驗報價必須成立")
	if not direct.ok:
		return
	assert_true(quote.available)
	assert_true(quote.quotable)
	assert_true(quote.affordable)
	assert_false(quote.at_max_level)
	assert_eq(quote.gold_cost, 20 - direct.transaction.economy_state.gold)
	assert_eq(quote.gold_cost, 4, "EconomyTestFixture 的 xp_buy_cost")
	assert_eq(quote.xp_gain, 4, "EconomyTestFixture 的 xp_buy_amount")
	assert_eq(quote.level_before, 3)
	assert_eq(
		quote.level_after, direct.transaction.economy_state.level,
		"升級折算必須取自 domain，不得由面板推算"
	)
	assert_eq(quote.xp_after, direct.transaction.economy_state.xp)
	assert_eq(quote.level_after, 4, "level 3 的門檻為 4，買 4 點即升級")


func test_buy_xp_quote_reports_max_level_instead_of_a_price() -> void:
	var run := _shop_run(EconomyState.new(99, 9, 0, 0, 0, 0, []))
	var view_model := ShopEconomyViewModel.new(_session_for(run), _catalog())

	var quote := view_model.buy_xp_quote()
	assert_true(quote.at_max_level, "等級 9 必須明示 MAX")
	assert_false(quote.available)
	assert_eq(quote.rejection_code, ShopError.LEVEL_MAX)
	assert_false(quote.quotable, "MAX 時沒有價格可報")
	assert_eq(quote.level_after, 9, "MAX 時折算後等級即目前等級")


func test_sell_quote_matches_quote_sell_and_unknown_id_is_named() -> void:
	var run := _shop_run(EconomyState.new(20, 3, 0, 0, 0, 0, []))
	var catalog := _catalog()
	var view_model := ShopEconomyViewModel.new(_session_for(run), catalog)

	var quote := view_model.sell_quote(UNIT_INSTANCE)
	var direct := ShopService.new().quote_sell(_sell_request(run, catalog, UNIT_INSTANCE))
	assert_true(direct.ok, "前提：直接呼叫 domain 的出售報價必須成立")
	if not direct.ok:
		return
	assert_true(quote.available)
	assert_true(quote.quotable)
	assert_eq(
		quote.gold_gain,
		direct.transaction.economy_state.gold - run.economy_state.gold,
		"出售所得必須等於 domain 報價的實際入袋"
	)
	assert_eq(quote.gold_gain, 2, "星 2 單位：3 * cost(1) - 1")

	var unknown := view_model.sell_quote("u_does_not_exist")
	assert_false(unknown.available)
	assert_eq(unknown.rejection_code, ShopError.UNIT_MISSING)
	assert_false(unknown.quotable)
	assert_eq(unknown.gold_gain, 0)
	var empty := view_model.sell_quote("")
	assert_false(empty.available)
	assert_eq(empty.rejection_code, ShopError.INPUT_INVALID)


func test_economy_status_projects_streaks_progress_and_authored_odds() -> void:
	var run := _shop_run(EconomyState.new(17, 3, 2, 4, 1, 6, []))
	var view_model := ShopEconomyViewModel.new(_session_for(run), _catalog())

	var status := view_model.economy_status()
	assert_eq(status.gold, 17)
	assert_eq(status.gold_cap, 99)
	assert_eq(status.level, 3)
	assert_eq(status.xp, 2)
	assert_eq(status.xp_required_for_next_level, 4, "xp_thresholds[level=3] 的 authored 值")
	assert_false(status.at_max_level)
	assert_eq(status.win_streak, 4)
	assert_eq(status.loss_streak, 1)
	assert_eq(status.shop_refresh_index, 6)
	assert_eq(status.odds_level, 3)
	assert_eq(
		status.odds_tier_basis_points, [10000, 0, 0, 0, 0],
		"費用機率列必須是 authored 原值"
	)


func test_economy_status_reports_max_level_when_thresholds_are_exhausted() -> void:
	var run := _shop_run(EconomyState.new(30, 9, 0, 0, 0, 0, []))
	var view_model := ShopEconomyViewModel.new(_session_for(run), _catalog())

	var status := view_model.economy_status()
	assert_eq(status.level, 9)
	assert_eq(status.xp_required_for_next_level, -1, "門檻用盡時明示 -1")
	assert_true(status.at_max_level)


func test_quotes_never_mutate_the_run_and_snapshots_are_isolated() -> void:
	var run := _shop_run(EconomyState.new(20, 3, 0, 0, 0, 0, []))
	var session := _session_for(run)
	var view_model := ShopEconomyViewModel.new(session, _catalog())

	var first := view_model.refresh_quote()
	view_model.buy_xp_quote()
	view_model.sell_quote(UNIT_INSTANCE)
	var after := session.run_snapshot()
	assert_eq(after.economy_state.gold, 20, "報價不得動到 canonical 金幣")
	assert_eq(after.economy_state.shop_refresh_index, 0, "報價不得推進刷新序號")
	assert_eq(after.economy_state.shop_offers.size(), 0, "報價不得寫入商店牌面")
	assert_eq(
		after.roster_state.unit_instances.size(), 1, "出售報價不得移除 canonical 單位"
	)

	first.gold_cost = 999
	var second := view_model.refresh_quote()
	assert_eq(second.gold_cost, 2, "改動先前回傳的快照不應影響之後的讀取")
	var status := view_model.economy_status()
	status.odds_tier_basis_points.append(1)
	assert_eq(view_model.economy_status().odds_tier_basis_points.size(), 5)


func test_catalog_generation_mismatch_is_reported_with_a_named_code() -> void:
	var run := _shop_run(EconomyState.new(20, 3, 0, 0, 0, 0, []))
	var view_model := ShopEconomyViewModel.new(
		_session_for(run), EconomyTestFixture.catalog(OTHER_MANIFEST)
	)

	assert_eq(
		view_model.refresh_quote().rejection_code, ShopError.GENERATION_MISMATCH,
		"世代不符必須在報價層就明示，不能讓面板顯示可按"
	)
	assert_eq(view_model.buy_xp_quote().rejection_code, ShopError.GENERATION_MISMATCH)
	assert_eq(
		view_model.sell_quote(UNIT_INSTANCE).rejection_code,
		ShopError.GENERATION_MISMATCH
	)


# ---------------------------------------------------------------------------
# fixtures：PREPARE 期、節點 node_fixture、pool 已扣 3 份 unit.test_a（對應一個星 2 單位）
# ---------------------------------------------------------------------------

func _catalog() -> EconomyExpeditionCatalog:
	return EconomyTestFixture.catalog(SaveRootFixture.MANIFEST_DIGEST)


func _shop_run(economy: EconomyState) -> RunState:
	var run := SaveRootFixture.create_valid_root().run
	run.run_phase = RunState.RunPhase.PREPARE
	run.current_node_id = OptionalStringValue.new(NODE_ID)
	run.economy_state = economy
	var pool := _catalog().create_initial_pool()
	var entry := pool.entries[0]
	entry.remaining_copies -= 3
	entry.held_copies = 3
	run.unit_pool_state = pool
	var no_equipment: Array[String] = []
	var units: Array[UnitInstance] = [
		UnitInstance.new(UNIT_INSTANCE, entry.unit_def_id, 2, no_equipment, U64Bits.one()),
	]
	var bench: Array[String] = [UNIT_INSTANCE]
	var no_placements: Array[BoardPlacementState] = []
	var no_items: Array[ItemInstanceState] = []
	var no_ids: Array[String] = []
	var relics: Array[RelicSlotState] = []
	for index: int in range(5):
		relics.append(RelicSlotState.new(index, null))
	run.roster_state = RosterState.new(
		BoardState.new(no_placements), bench, units, no_items, no_ids, no_ids, relics
	)
	return run


func _session_for(run: RunState) -> RunSession:
	var profile := SaveRootFixture.create_valid_root().profile
	var lease := TestCatalogLease.new(run.content_snapshot.manifest_digest_value())
	return RunSession.new(profile, run, lease)


func _refresh_request(run: RunState, catalog: EconomyExpeditionCatalog) -> RefreshShopRequest:
	return RefreshShopRequest.new(
		StringName(run.run_id), StringName(NODE_ID), run.economy_state,
		run.unit_pool_state, run.roster_state, run.reservation_owners,
		EconomyCommandSupport.try_shop_rng(run), run.next_transaction_serial,
		run.next_unit_serial, catalog
	)


func _buy_xp_request(run: RunState, catalog: EconomyExpeditionCatalog) -> BuyXpRequest:
	return BuyXpRequest.new(
		StringName(run.run_id), StringName(NODE_ID), run.economy_state,
		run.unit_pool_state, run.roster_state, run.reservation_owners,
		EconomyCommandSupport.try_shop_rng(run), run.next_transaction_serial,
		run.next_unit_serial, catalog
	)


func _sell_request(
	run: RunState,
	catalog: EconomyExpeditionCatalog,
	unit_instance_id: String
) -> SellUnitRequest:
	return SellUnitRequest.new(
		StringName(run.run_id), StringName(NODE_ID), unit_instance_id,
		run.economy_state, run.unit_pool_state, run.roster_state,
		run.reservation_owners, EconomyCommandSupport.try_shop_rng(run),
		run.next_transaction_serial, run.next_unit_serial, catalog
	)
