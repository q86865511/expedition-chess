extends GutTest

## in-run-hud T10 上游：RunPresentationSession 的鍛造／商店供給讀取面。
##
## 契約：局內畫面拿不到 RunController、ForgeRecipeTable 或 EconomyExpeditionCatalog
## （spec §10.3 禁止呈現層自行接 catalog 與複製公式），要看的鍛造配方與商店報價一律
## 經 session 的唯讀方法取得。因此本 suite 對每個方法斷言「與直接呼叫 ForgeViewModel／
## ShopEconomyViewModel／ShopService 的結果逐欄位一致」，另外守住兩件事：
##   1. 建構子新增的四個供給參數都有預設值——既有 29 個 `RunPresentationSession.new`
##      呼叫端（只傳前五個參數）不得因此壞掉，且供給缺席時必須回空狀態而非 crash。
##   2. 回傳值都是 clone：改動回傳物件不影響 canonical，也不影響之後的讀取。

const OTHER_MANIFEST: String = \
	"3333333333333333333333333333333333333333333333333333333333333333"
const SHOP_NODE_ID: String = "node_fixture"
const SHOP_UNIT_INSTANCE: String = "u_0000000000000201"


# ---------------------------------------------------------------------------
# 鍛造：零件清單／配方預覽／拖曳配對
# ---------------------------------------------------------------------------

func test_forge_inventory_components_match_forge_view_model() -> void:
	var run := _forge_run()
	var controller := _forge_controller(run)
	var table := ForgeEquipmentTestFixture.forge_table()
	var session := _forge_session(controller, table)

	var components := session.forge_inventory_components()
	var direct := ForgeViewModel.new(controller, table).inventory_components()
	assert_eq(components.size(), direct.size(), "零件清單必須與 ForgeViewModel 同源")
	assert_eq(components.size(), 2)
	for index: int in range(components.size()):
		assert_eq(components[index].instance_id, direct[index].instance_id)
		assert_eq(components[index].def_id, direct[index].def_id)

	# clone-out：改動回傳物件不得影響 canonical 或之後的讀取。
	components[0].def_id = &"item_component.mutated"
	for item: ItemInstanceState in session.forge_inventory_components():
		assert_ne(item.def_id, &"item_component.mutated")
	for item: ItemInstanceState in controller.roster_snapshot().item_instances:
		assert_ne(item.def_id, &"item_component.mutated")


func test_forge_recipes_containing_match_forge_view_model() -> void:
	var run := _forge_run()
	var controller := _forge_controller(run)
	var table := ForgeEquipmentTestFixture.forge_table()
	var session := _forge_session(controller, table)

	var previews := session.forge_recipes_containing(
		ForgeEquipmentTestFixture.COMPONENT_ALPHA
	)
	var direct := ForgeViewModel.new(controller, table).recipe_preview(
		ForgeEquipmentTestFixture.COMPONENT_ALPHA
	)
	assert_eq(previews.size(), direct.size(), "配方預覽必須與 ForgeViewModel 同源")
	assert_eq(previews.size(), 2, "alpha 同時在自配與交叉配方中")
	var equipment_ids: Array[StringName] = []
	for rule: ForgeRecipeRule in previews:
		equipment_ids.append(rule.equipment_id)
	assert_true(equipment_ids.has(ForgeEquipmentTestFixture.EQUIPMENT_ALPHA_ALPHA))
	assert_true(equipment_ids.has(ForgeEquipmentTestFixture.EQUIPMENT_ALPHA_BETA))
	assert_eq(
		session.forge_recipes_containing(&"").size(),
		0,
		"空 def_id 沒有可預覽的配方"
	)


func test_forge_pair_recipe_matches_the_pinned_table_and_fails_closed() -> void:
	var run := _forge_run()
	var controller := _forge_controller(run)
	var table := ForgeEquipmentTestFixture.forge_table()
	var session := _forge_session(controller, table)
	var component_a := ForgeEquipmentTestFixture.item_id(1)
	var component_b := ForgeEquipmentTestFixture.item_id(2)

	var paired := session.try_forge_pair_recipe(component_a, component_b)
	assert_not_null(paired, "alpha+beta 是已註冊配方")
	if paired == null:
		return
	var direct := table.try_recipe(
		ForgeEquipmentTestFixture.COMPONENT_ALPHA,
		ForgeEquipmentTestFixture.COMPONENT_BETA
	)
	assert_eq(
		paired.equipment_id,
		direct.equipment_id,
		"成品必須取自 pinned ForgeRecipeTable，不得由呈現層推算"
	)
	assert_eq(paired.equipment_id, ForgeEquipmentTestFixture.EQUIPMENT_ALPHA_BETA)
	assert_eq(
		session.try_forge_pair_recipe(component_b, component_a).equipment_id,
		paired.equipment_id,
		"配對是無序的"
	)
	assert_null(
		session.try_forge_pair_recipe(component_a, component_a),
		"同一個 instance 不能被消耗兩次（同 ForgeEquipmentCommand 的判準）"
	)
	assert_null(
		session.try_forge_pair_recipe(component_a, "it_does_not_exist"),
		"不在 inventory 的 instance 不是可用零件"
	)
	assert_null(session.try_forge_pair_recipe("", component_b))


func test_forge_pair_recipe_rejects_unregistered_pairs_and_bound_items() -> void:
	var run := ForgeEquipmentTestFixture.base_run()
	var beta_a := ForgeEquipmentTestFixture.item_id(1)
	var beta_b := ForgeEquipmentTestFixture.item_id(2)
	run.roster_state.item_instances = [
		ForgeEquipmentTestFixture.item(
			beta_a, ForgeEquipmentTestFixture.COMPONENT_BETA
		),
		ForgeEquipmentTestFixture.item(
			beta_b, ForgeEquipmentTestFixture.COMPONENT_BETA
		),
	]
	run.roster_state.inventory_item_instance_ids = [beta_a, beta_b]
	var session := _forge_session(
		_forge_controller(run), ForgeEquipmentTestFixture.forge_table()
	)

	assert_null(
		session.try_forge_pair_recipe(beta_a, beta_b),
		"beta+beta 沒有註冊配方，預覽必須是 null 而不是猜一個成品"
	)

	# 綁在單位上的物品不是可用零件（同 ForgeEquipmentCommand 的
	# _find_available_component 判準），即使它仍列在 inventory 裡。
	var bound_run := ForgeEquipmentTestFixture.base_run()
	var alpha := ForgeEquipmentTestFixture.item_id(1)
	var bound_beta := ForgeEquipmentTestFixture.item_id(2)
	bound_run.roster_state.item_instances = [
		ForgeEquipmentTestFixture.item(
			alpha, ForgeEquipmentTestFixture.COMPONENT_ALPHA
		),
		ForgeEquipmentTestFixture.item(
			bound_beta, ForgeEquipmentTestFixture.COMPONENT_BETA, "u_0000000000000001"
		),
	]
	bound_run.roster_state.inventory_item_instance_ids = [alpha, bound_beta]
	var bound_session := _forge_session(
		_forge_controller(bound_run), ForgeEquipmentTestFixture.forge_table()
	)
	assert_null(
		bound_session.try_forge_pair_recipe(alpha, bound_beta),
		"已綁在單位上的物品不得被當成可合成的零件"
	)


# ---------------------------------------------------------------------------
# 商店：四個報價轉發
# ---------------------------------------------------------------------------

func test_shop_quotes_match_shop_economy_view_model_and_shop_service() -> void:
	var run := _shop_run(EconomyState.new(20, 3, 0, 2, 0, 0, []))
	var run_session := _session_for(run)
	var catalog := _shop_catalog()
	var session := _shop_presentation_session(run_session, catalog)
	var view_model := ShopEconomyViewModel.new(_session_for(run), catalog)

	var refresh := session.shop_refresh_quote()
	var direct_refresh := ShopService.new().quote_refresh(
		_refresh_request(run, catalog)
	)
	assert_true(direct_refresh.ok, "前提：直接呼叫 domain 的刷新報價必須成立")
	if not direct_refresh.ok:
		return
	assert_true(refresh.available)
	assert_eq(refresh.rejection_code, &"")
	assert_eq(refresh.gold_before, 20)
	assert_eq(
		refresh.gold_cost,
		run.economy_state.gold - direct_refresh.transaction.economy_state.gold,
		"刷新價必須等於 domain 報價的實際扣款"
	)
	assert_eq(refresh.gold_cost, view_model.refresh_quote().gold_cost)

	var xp := session.shop_buy_xp_quote()
	var direct_xp := view_model.buy_xp_quote()
	assert_eq(xp.gold_cost, direct_xp.gold_cost)
	assert_eq(xp.xp_gain, direct_xp.xp_gain)
	assert_eq(xp.level_after, direct_xp.level_after)
	assert_eq(xp.xp_after, direct_xp.xp_after)
	assert_false(xp.at_max_level)

	var sell := session.shop_sell_quote(SHOP_UNIT_INSTANCE)
	var direct_sell := ShopService.new().quote_sell(
		_sell_request(run, catalog, SHOP_UNIT_INSTANCE)
	)
	assert_true(direct_sell.ok, "前提：直接呼叫 domain 的出售報價必須成立")
	if not direct_sell.ok:
		return
	assert_true(sell.available)
	assert_eq(
		sell.gold_gain,
		direct_sell.transaction.economy_state.gold - run.economy_state.gold,
		"出售所得必須等於 domain 報價的實際入袋"
	)

	var status := session.shop_economy_status()
	var direct_status := view_model.economy_status()
	assert_eq(status.gold, direct_status.gold)
	assert_eq(status.gold_cap, direct_status.gold_cap)
	assert_eq(status.level, direct_status.level)
	assert_eq(status.xp_required_for_next_level, direct_status.xp_required_for_next_level)
	assert_eq(status.odds_tier_basis_points, direct_status.odds_tier_basis_points)


func test_shop_quotes_are_read_only_and_isolated_between_calls() -> void:
	var run := _shop_run(EconomyState.new(20, 3, 0, 0, 0, 0, []))
	var run_session := _session_for(run)
	var session := _shop_presentation_session(run_session, _shop_catalog())

	var first := session.shop_refresh_quote()
	session.shop_buy_xp_quote()
	session.shop_sell_quote(SHOP_UNIT_INSTANCE)
	var after := run_session.run_snapshot()
	assert_eq(after.economy_state.gold, 20, "報價不得動到 canonical 金幣")
	assert_eq(after.economy_state.shop_refresh_index, 0, "報價不得推進刷新序號")
	assert_eq(
		after.roster_state.unit_instances.size(), 1, "出售報價不得移除 canonical 單位"
	)

	first.gold_cost = 999
	assert_eq(
		session.shop_refresh_quote().gold_cost,
		2,
		"改動先前回傳的報價不得影響之後的讀取"
	)


func test_shop_quotes_report_named_generation_mismatch() -> void:
	var run := _shop_run(EconomyState.new(20, 3, 0, 0, 0, 0, []))
	var session := _shop_presentation_session(
		_session_for(run), EconomyTestFixture.catalog(OTHER_MANIFEST)
	)

	assert_eq(
		session.shop_refresh_quote().rejection_code,
		ShopError.GENERATION_MISMATCH,
		"世代不符必須在報價層就明示"
	)
	assert_eq(
		session.shop_buy_xp_quote().rejection_code, ShopError.GENERATION_MISMATCH
	)
	assert_eq(
		session.shop_sell_quote(SHOP_UNIT_INSTANCE).rejection_code,
		ShopError.GENERATION_MISMATCH
	)


# ---------------------------------------------------------------------------
# 供給缺席：既有呼叫端（只傳前五個參數）與 release() 之後
# ---------------------------------------------------------------------------

func test_absent_supply_returns_empty_state_instead_of_crashing() -> void:
	var session := RunPresentationSession.new()

	assert_eq(session.forge_inventory_components(), [], "無供給時沒有零件可列")
	assert_eq(session.forge_recipes_containing(&"item_component.alpha"), [])
	assert_null(session.try_forge_pair_recipe("it_a", "it_b"))
	var status := session.shop_economy_status()
	assert_eq(status.gold, 0)
	assert_eq(status.level, 0)
	assert_false(status.at_max_level)
	assert_eq(
		session.shop_refresh_quote().rejection_code,
		ShopError.INPUT_INVALID,
		"沒有 run 供給時要給具名碼，不能讓面板顯示可按"
	)
	assert_eq(session.shop_buy_xp_quote().rejection_code, ShopError.INPUT_INVALID)
	assert_eq(
		session.shop_sell_quote(SHOP_UNIT_INSTANCE).rejection_code,
		ShopError.INPUT_INVALID
	)


func test_release_clears_supply_and_keeps_reads_answerable() -> void:
	var run := _forge_run()
	var session := _forge_session(
		_forge_controller(run), ForgeEquipmentTestFixture.forge_table()
	)
	assert_eq(session.forge_inventory_components().size(), 2)

	session.release()

	assert_eq(
		session.forge_inventory_components(), [], "release 之後供給一併解除"
	)
	assert_null(
		session.try_forge_pair_recipe(
			ForgeEquipmentTestFixture.item_id(1),
			ForgeEquipmentTestFixture.item_id(2)
		)
	)
	assert_eq(
		session.shop_refresh_quote().rejection_code, ShopError.INPUT_INVALID
	)


# ---------------------------------------------------------------------------
# fixtures
# ---------------------------------------------------------------------------

func _forge_run() -> RunState:
	var run := ForgeEquipmentTestFixture.base_run()
	var component_a := ForgeEquipmentTestFixture.item_id(1)
	var component_b := ForgeEquipmentTestFixture.item_id(2)
	run.roster_state.item_instances = [
		ForgeEquipmentTestFixture.item(
			component_a, ForgeEquipmentTestFixture.COMPONENT_ALPHA
		),
		ForgeEquipmentTestFixture.item(
			component_b, ForgeEquipmentTestFixture.COMPONENT_BETA
		),
	]
	run.roster_state.inventory_item_instance_ids = [component_a, component_b]
	return run


func _forge_controller(run: RunState) -> RunController:
	var repository := ForgeEquipmentTestFixture.repository_for(FakeSaveStorage.new())
	add_child_autofree(repository)
	var battle_catalog := EquipDismantleTestFixture.battle_catalog(
		run.content_snapshot.manifest_digest_value()
	)
	return ViewModelTestFixture.controller_for(run, battle_catalog, repository)


func _forge_session(
	controller: RunController,
	table: ForgeRecipeTable
) -> RunPresentationSession:
	var no_effects: Array[StringName] = []
	return RunPresentationSession.new(
		controller, null, null, no_effects, null, null, table
	)


func _shop_presentation_session(
	run_session: RunSession,
	catalog: EconomyExpeditionCatalog
) -> RunPresentationSession:
	var no_effects: Array[StringName] = []
	return RunPresentationSession.new(
		null, null, null, no_effects, null, run_session, null, catalog
	)


func _shop_catalog() -> EconomyExpeditionCatalog:
	return EconomyTestFixture.catalog(SaveRootFixture.MANIFEST_DIGEST)


func _shop_run(economy: EconomyState) -> RunState:
	var run := SaveRootFixture.create_valid_root().run
	run.run_phase = RunState.RunPhase.PREPARE
	run.current_node_id = OptionalStringValue.new(SHOP_NODE_ID)
	run.economy_state = economy
	var pool := _shop_catalog().create_initial_pool()
	var entry := pool.entries[0]
	entry.remaining_copies -= 3
	entry.held_copies = 3
	run.unit_pool_state = pool
	var no_equipment: Array[String] = []
	var units: Array[UnitInstance] = [
		UnitInstance.new(
			SHOP_UNIT_INSTANCE, entry.unit_def_id, 2, no_equipment, U64Bits.one()
		),
	]
	var bench: Array[String] = [SHOP_UNIT_INSTANCE]
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


func _refresh_request(
	run: RunState,
	catalog: EconomyExpeditionCatalog
) -> RefreshShopRequest:
	return RefreshShopRequest.new(
		StringName(run.run_id), StringName(SHOP_NODE_ID), run.economy_state,
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
		StringName(run.run_id), StringName(SHOP_NODE_ID), unit_instance_id,
		run.economy_state, run.unit_pool_state, run.roster_state,
		run.reservation_owners, EconomyCommandSupport.try_shop_rng(run),
		run.next_transaction_serial, run.next_unit_serial, catalog
	)
