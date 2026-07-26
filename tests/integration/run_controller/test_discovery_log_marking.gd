extends GutTest

## T09 (specs/meta-progression/design.md §8; requirements.md S5-AC-012;
## tasks.md T09 驗收): 圖鑑發現局內即時標記 -- 四類事件(上場/購得棋子、
## 商店出現、遭遇敵人、取得裝備/遺物)於所屬 command 的 apply_to() 內經
## RunDiscoveryLog.mark() 把 content_id union 進 draft.discovered_content_ids;
## RunController._commit_draft 再把 draft.discovered_content_ids union 進
## profile'(profile 於 run 期唯一可變面),兩者在同一 copy-validate-save-swap
## 交易內原子完成。本檔透過真正的 command + 真正的 RunController.dispatch()/
## transition() 分派(不直接呼叫 RunDiscoveryLog),驗證可觀察的端到端契約;
## RunDiscoveryLog.mark() 本身的純函式行為由
## tests/unit/meta_progression/test_run_discovery_log.gd 覆蓋,
## CollectionViewModel 由 tests/unit/meta_progression/test_collection_view_model.gd
## 覆蓋。
##
## 四類事件 -> command 的對應(design.md §8 逐條列出):
##   上場/購得棋子 -> BuyOfferCommand(購得)／CommitBoardLayoutCommand(上場)
##   商店出現      -> RefreshShopCommand
##   遭遇敵人      -> EnterNodeEvent 的 encounter preview
##   取得裝備/遺物 -> ForgeEquipmentCommand(裝備)／ChooseRewardCommand(遺物)


func test_buy_offer_command_marks_purchased_unit_discovered_atomically_in_profile_and_run() -> void:
	var root := _prepared_root()
	var catalog := EconomyTestFixture.save_fixture_catalog(root.run.content_snapshot.manifest_digest_value())
	var battle_catalog := EconomyTestFixture.battle_catalog(root.run.content_snapshot.manifest_digest_value())
	var storage := FakeSaveStorage.new()
	var repository := SaveRootFixture.create_repository(storage)
	add_child_autofree(repository)
	var controller := _controller_for(root, repository)
	assert_true(controller.dispatch(GenerateExpeditionMapCommand.new(catalog)).ok)
	var mapped := repository.load()
	assert_true(mapped.ok)
	if not mapped.ok: return
	assert_true(controller.transition(EnterNodeEvent.new(
		mapped.run.map_state.nodes[0].node_id, catalog,
		EconomyTestFixture.expedition_battle_catalog(root.run.content_snapshot.manifest_digest_value())
	)).ok)
	var after_enter := repository.load()
	assert_true(after_enter.ok)
	if not after_enter.ok: return
	var offer_id := after_enter.run.economy_state.shop_offers[0].offer_id

	var bought := controller.dispatch(BuyOfferCommand.new(offer_id, catalog, battle_catalog))
	assert_true(bought.ok, "%s:%s" % [
		String(bought.error.code) if bought.error != null else "none",
		String(bought.error.field_path) if bought.error != null else "none",
	])
	if not bought.ok: return
	var after_buy := repository.load()
	assert_true(after_buy.ok)
	if not after_buy.ok: return
	assert_true(
		after_buy.run.discovered_content_ids.has(&"unit.fixture"),
		"purchased unit.fixture must be recorded in run.discovered_content_ids"
	)
	assert_true(
		after_buy.profile.discovered_content_ids.has(&"unit.fixture"),
		"RunController._commit_draft must union discovery into profile' in the same commit"
	)


func test_refresh_shop_command_marks_shop_offer_units_discovered() -> void:
	var root := _prepared_root()
	var catalog := EconomyTestFixture.save_fixture_catalog(root.run.content_snapshot.manifest_digest_value())
	var storage := FakeSaveStorage.new()
	var repository := SaveRootFixture.create_repository(storage)
	add_child_autofree(repository)
	var controller := _controller_for(root, repository)
	assert_true(controller.dispatch(GenerateExpeditionMapCommand.new(catalog)).ok)
	var mapped := repository.load()
	assert_true(mapped.ok)
	if not mapped.ok: return
	assert_true(controller.transition(EnterNodeEvent.new(
		mapped.run.map_state.nodes[0].node_id, catalog,
		EconomyTestFixture.expedition_battle_catalog(root.run.content_snapshot.manifest_digest_value())
	)).ok)

	var refreshed := controller.dispatch(RefreshShopCommand.new(catalog))
	assert_true(refreshed.ok, "%s:%s" % [
		String(refreshed.error.code) if refreshed.error != null else "none",
		String(refreshed.error.field_path) if refreshed.error != null else "none",
	])
	if not refreshed.ok: return
	var after := repository.load()
	assert_true(after.ok)
	if not after.ok: return
	assert_false(after.run.economy_state.shop_offers.is_empty())
	for offer: ShopOffer in after.run.economy_state.shop_offers:
		assert_true(
			after.run.discovered_content_ids.has(offer.unit_def_id),
			"expected %s discovered after shop refresh" % offer.unit_def_id
		)
	assert_true(after.profile.discovered_content_ids.has(&"unit.fixture"))


func test_enter_node_event_marks_encounter_enemy_unit_discovered() -> void:
	var root := _prepared_root()
	var catalog := EconomyTestFixture.save_fixture_catalog(root.run.content_snapshot.manifest_digest_value())
	var storage := FakeSaveStorage.new()
	var repository := SaveRootFixture.create_repository(storage)
	add_child_autofree(repository)
	var controller := _controller_for(root, repository)
	var generated := controller.dispatch(GenerateExpeditionMapCommand.new(catalog))
	assert_true(generated.ok)
	if not generated.ok: return
	var generated_root := repository.load()
	assert_true(generated_root.ok)
	if not generated_root.ok: return
	var target := generated_root.run.map_state.nodes[0]
	var battle_catalog := EconomyTestFixture.expedition_battle_catalog(
		root.run.content_snapshot.manifest_digest_value()
	)

	var entered := controller.transition(EnterNodeEvent.new(target.node_id, catalog, battle_catalog))
	assert_true(entered.ok, "%s" % [String(entered.error.code) if entered.error != null else "none"])
	if not entered.ok: return
	var after_enter := repository.load()
	assert_true(after_enter.ok)
	if not after_enter.ok: return
	assert_not_null(after_enter.run.map_state.nodes[0].encounter_preview)
	assert_true(
		after_enter.run.discovered_content_ids.has(&"unit.enemy"),
		"encountered enemy unit.enemy must be recorded in run.discovered_content_ids"
	)
	assert_true(after_enter.profile.discovered_content_ids.has(&"unit.enemy"))


func test_commit_board_layout_command_marks_newly_boarded_unit_discovered() -> void:
	var root := SaveRootFixture.create_valid_root()
	root.run.run_phase = RunState.RunPhase.PREPARE
	var no_equipment: Array[String] = []
	var unit := UnitInstance.new(
		"u_0000000000000001", &"unit.fixture", 1, no_equipment, U64Bits.one()
	)
	var no_placements: Array[BoardPlacementState] = []
	root.run.roster_state.unit_instances = [unit]
	root.run.roster_state.board = BoardState.new(no_placements)
	root.run.roster_state.bench_unit_instance_ids = ["u_0000000000000001"]
	var pool_entries: Array[UnitPoolEntryState] = [
		UnitPoolEntryState.new(&"unit.fixture", 1, 0, 0, 1),
	]
	root.run.unit_pool_state = UnitPoolState.new(pool_entries)
	assert_false(root.run.discovered_content_ids.has(&"unit.fixture"))
	var storage := FakeSaveStorage.new()
	var repository := SaveRootFixture.create_repository(storage)
	add_child_autofree(repository)
	var controller := _controller_for(root, repository)

	var placements: Array[BoardPlacementState] = [
		BoardPlacementState.new(0, 0, "u_0000000000000001"),
	]
	var no_bench: Array[String] = []
	var result := controller.dispatch(CommitBoardLayoutCommand.new(
		BoardState.new(placements), no_bench, _empty_battle_catalog()
	))
	assert_true(result.ok, _command_error_text(result.error))
	if not result.ok: return
	var loaded := repository.load()
	assert_true(loaded.ok)
	if not loaded.ok: return
	assert_true(
		loaded.run.discovered_content_ids.has(&"unit.fixture"),
		"unit placed onto the board (上場) must be recorded in run.discovered_content_ids"
	)
	assert_true(loaded.profile.discovered_content_ids.has(&"unit.fixture"))


func test_forge_equipment_command_marks_forged_equipment_discovered() -> void:
	var run := ForgeEquipmentTestFixture.base_run()
	assert_false(run.discovered_content_ids.has(ForgeEquipmentTestFixture.EQUIPMENT_ALPHA_BETA))
	var component_a := ForgeEquipmentTestFixture.item_id(1)
	var component_b := ForgeEquipmentTestFixture.item_id(2)
	run.roster_state.item_instances = [
		ForgeEquipmentTestFixture.item(component_a, ForgeEquipmentTestFixture.COMPONENT_ALPHA),
		ForgeEquipmentTestFixture.item(component_b, ForgeEquipmentTestFixture.COMPONENT_BETA),
	]
	run.roster_state.inventory_item_instance_ids = [component_a, component_b]
	var storage := FakeSaveStorage.new()
	var repository := ForgeEquipmentTestFixture.repository_for(storage)
	add_child_autofree(repository)
	var profile := SaveRootFixture.create_valid_root().profile
	var lease := TestCatalogLease.new(run.content_snapshot.manifest_digest_value())
	var session := RunSession.new(profile, run, lease)
	var factory := RunSaveRootFactory.new("0.1.0", FixedRunCommitClock.new())
	var controller := RunController.new(session, repository, RunStateValidator.new(), factory)
	var table := ForgeEquipmentTestFixture.forge_table()

	var result := controller.dispatch(ForgeEquipmentCommand.new(component_a, component_b, table))
	assert_true(result.ok, _command_error_text(result.error))
	if not result.ok: return
	var loaded := repository.load()
	assert_true(loaded.ok)
	if not loaded.ok: return
	assert_true(
		loaded.run.discovered_content_ids.has(ForgeEquipmentTestFixture.EQUIPMENT_ALPHA_BETA),
		"forged equipment.alpha_beta must be recorded in run.discovered_content_ids"
	)
	assert_true(
		loaded.profile.discovered_content_ids.has(ForgeEquipmentTestFixture.EQUIPMENT_ALPHA_BETA)
	)


func test_choose_reward_command_marks_granted_relic_discovered() -> void:
	var root := ResolutionFixtureFactory.create_root(ResolutionState.Kind.REWARD_PENDING)
	assert_false(root.run.discovered_content_ids.has(&"relic.fixture"))
	var pending := (root.run.resolution_state as RewardPendingResolutionState).pending_reward
	var relic_offer := RewardOfferState.new(
		"choice_2", RewardOfferState.RewardKind.RELIC,
		OptionalStringNameValue.of(&"relic.fixture"), 0, null,
		ResolutionFixtureFactory.PAYLOAD_REWARD
	)
	pending.offers[2] = relic_offer
	var storage := FakeSaveStorage.new()
	var repository := SaveRootFixture.create_repository(storage)
	add_child_autofree(repository)
	var lease := TestCatalogLease.new(root.run.content_snapshot.manifest_digest_value())
	var session := RunSession.new(root.profile, root.run, lease)
	var factory := RunSaveRootFactory.new("0.1.0", FixedRunCommitClock.new())
	var controller := RunController.new(session, repository, RunStateValidator.new(), factory)
	var catalog := EconomyTestFixture.save_fixture_catalog(root.run.content_snapshot.manifest_digest_value())

	var result := controller.dispatch(ChooseRewardCommand.new("choice_2", catalog))
	assert_true(result.ok, _command_error_text(result.error))
	if not result.ok: return
	var loaded := repository.load()
	assert_true(loaded.ok)
	if not loaded.ok: return
	assert_eq(loaded.run.roster_state.active_relic_slots[0].relic_id.value, &"relic.fixture")
	assert_true(
		loaded.run.discovered_content_ids.has(&"relic.fixture"),
		"granted relic.fixture must be recorded in run.discovered_content_ids"
	)
	assert_true(loaded.profile.discovered_content_ids.has(&"relic.fixture"))


func test_repeated_purchase_of_same_unit_def_id_does_not_duplicate_discovery() -> void:
	var root := _prepared_root()
	var catalog := EconomyTestFixture.save_fixture_catalog(root.run.content_snapshot.manifest_digest_value())
	var battle_catalog := EconomyTestFixture.battle_catalog(root.run.content_snapshot.manifest_digest_value())
	var storage := FakeSaveStorage.new()
	var repository := SaveRootFixture.create_repository(storage)
	add_child_autofree(repository)
	var controller := _controller_for(root, repository)
	assert_true(controller.dispatch(GenerateExpeditionMapCommand.new(catalog)).ok)
	var mapped := repository.load()
	assert_true(mapped.ok)
	if not mapped.ok: return
	assert_true(controller.transition(EnterNodeEvent.new(
		mapped.run.map_state.nodes[0].node_id, catalog,
		EconomyTestFixture.expedition_battle_catalog(root.run.content_snapshot.manifest_digest_value())
	)).ok)
	var after_enter := repository.load()
	assert_true(after_enter.ok)
	if not after_enter.ok: return
	assert_true(
		after_enter.run.economy_state.shop_offers.size() >= 2,
		"fixture must offer at least 2 shop slots to prove de-duplication"
	)
	var first_offer_id := after_enter.run.economy_state.shop_offers[0].offer_id
	var second_offer_id := after_enter.run.economy_state.shop_offers[1].offer_id

	assert_true(controller.dispatch(BuyOfferCommand.new(first_offer_id, catalog, battle_catalog)).ok)
	var second_bought := controller.dispatch(BuyOfferCommand.new(second_offer_id, catalog, battle_catalog))
	assert_true(second_bought.ok, _command_error_text(second_bought.error))
	if not second_bought.ok: return

	var after_two_buys := repository.load()
	assert_true(after_two_buys.ok)
	if not after_two_buys.ok: return
	assert_eq(
		after_two_buys.run.discovered_content_ids.count(&"unit.fixture"),
		1,
		"unit.fixture must be recorded exactly once despite two purchases of the same def_id"
	)


func test_reload_then_repeat_refresh_does_not_duplicate_discovery() -> void:
	var root := _prepared_root()
	var catalog := EconomyTestFixture.save_fixture_catalog(root.run.content_snapshot.manifest_digest_value())
	var storage := FakeSaveStorage.new()
	var repository := SaveRootFixture.create_repository(storage)
	add_child_autofree(repository)
	var controller := _controller_for(root, repository)
	assert_true(controller.dispatch(GenerateExpeditionMapCommand.new(catalog)).ok)
	var mapped := repository.load()
	assert_true(mapped.ok)
	if not mapped.ok: return
	assert_true(controller.transition(EnterNodeEvent.new(
		mapped.run.map_state.nodes[0].node_id, catalog,
		EconomyTestFixture.expedition_battle_catalog(root.run.content_snapshot.manifest_digest_value())
	)).ok)
	assert_true(controller.dispatch(RefreshShopCommand.new(catalog)).ok)
	var after_first_refresh := repository.load()
	assert_true(after_first_refresh.ok)
	if not after_first_refresh.ok: return
	var count_after_first := after_first_refresh.run.discovered_content_ids.count(&"unit.fixture")
	assert_eq(count_after_first, 1)

	# Simulate a process reload: rebuild session/controller purely from the
	# persisted SaveRoot (no in-memory state carried over), then repeat the
	# same kind of discovery-causing action again.
	var reloaded_session := RunSession.new(
		after_first_refresh.profile, after_first_refresh.run,
		TestCatalogLease.new(after_first_refresh.run.content_snapshot.manifest_digest_value())
	)
	var reloaded_controller := RunController.new(
		reloaded_session, repository, RunStateValidator.new(),
		RunSaveRootFactory.new("0.1.0", FixedRunCommitClock.new())
	)
	var repeated := reloaded_controller.dispatch(RefreshShopCommand.new(catalog))
	assert_true(repeated.ok, _command_error_text(repeated.error))
	if not repeated.ok: return
	var after_reload_refresh := repository.load()
	assert_true(after_reload_refresh.ok)
	if not after_reload_refresh.ok: return
	assert_eq(
		after_reload_refresh.run.discovered_content_ids.count(&"unit.fixture"),
		count_after_first,
		"reload + repeat refresh must not duplicate an already-discovered id"
	)


func test_buy_offer_save_failure_leaves_discovery_and_purchase_both_uncommitted_then_succeeds_on_retry() -> void:
	var root := _prepared_root()
	var catalog := EconomyTestFixture.save_fixture_catalog(root.run.content_snapshot.manifest_digest_value())
	var battle_catalog := EconomyTestFixture.battle_catalog(root.run.content_snapshot.manifest_digest_value())
	var storage := FakeSaveStorage.new()
	var repository := SaveRootFixture.create_repository(storage)
	add_child_autofree(repository)
	var controller := _controller_for(root, repository)
	assert_true(controller.dispatch(GenerateExpeditionMapCommand.new(catalog)).ok)
	var mapped := repository.load()
	assert_true(mapped.ok)
	if not mapped.ok: return
	assert_true(controller.transition(EnterNodeEvent.new(
		mapped.run.map_state.nodes[0].node_id, catalog,
		EconomyTestFixture.expedition_battle_catalog(root.run.content_snapshot.manifest_digest_value())
	)).ok)
	var before_buy := repository.load()
	assert_true(before_buy.ok)
	if not before_buy.ok: return
	var offer_id := before_buy.run.economy_state.shop_offers[0].offer_id

	storage.reset_journal()
	storage.inject_fault(StorageFaultKey.new(StorageFaultKey.DIRECTORY, StorageFaultKey.MAIN, 0))
	var result := controller.dispatch(BuyOfferCommand.new(offer_id, catalog, battle_catalog))
	assert_false(result.ok)
	assert_eq(result.error.code, CommandError.SAVE_FAILED)
	storage.clear_faults()

	# copy-validate-save-swap atomicity: a failed save must leave *both* the
	# purchase and the discovery-log union entirely uncommitted -- not just
	# the purchase. Compares the full ledger (not just presence/absence of
	# one id) so this is agnostic to whether some other id was already
	# discovered earlier in the same run (e.g. via node-entry's encounter).
	var after_failed_buy := repository.load()
	assert_true(after_failed_buy.ok)
	if not after_failed_buy.ok: return
	assert_eq(after_failed_buy.run.discovered_content_ids, before_buy.run.discovered_content_ids)
	assert_eq(after_failed_buy.profile.discovered_content_ids, before_buy.profile.discovered_content_ids)
	assert_eq(
		after_failed_buy.run.economy_state.shop_offers.size(),
		before_buy.run.economy_state.shop_offers.size()
	)

	# Retry the *same* purchase now that storage is healthy again. This must
	# succeed and mark discovery this time -- proving the earlier failure
	# truly discarded the whole draft (offer_id still purchasable) rather
	# than partially applying it. Without this second half, an
	# unimplemented discovery log would make the two ledger-equality
	# assertions above pass vacuously (both sides empty), so this retry is
	# what actually keeps this test red before T09 lands.
	var retried := controller.dispatch(BuyOfferCommand.new(offer_id, catalog, battle_catalog))
	assert_true(retried.ok, _command_error_text(retried.error))
	if not retried.ok: return
	var after_retry := repository.load()
	assert_true(after_retry.ok)
	if not after_retry.ok: return
	assert_true(after_retry.run.discovered_content_ids.has(&"unit.fixture"))
	assert_true(after_retry.profile.discovered_content_ids.has(&"unit.fixture"))


## w2 review addition (gap: node entry itself regenerates shop offers via
## NodeEntryService.enter, not only RefreshShopCommand -- see
## enter_node_event.gd _mark_shop_discovery). Mirrors
## test_refresh_shop_command_marks_shop_offer_units_discovered but proves the
## same coverage holds right after EnterNodeEvent alone, no refresh needed.
func test_enter_node_event_marks_freshly_generated_shop_offer_units_discovered() -> void:
	var root := _prepared_root()
	var catalog := EconomyTestFixture.save_fixture_catalog(root.run.content_snapshot.manifest_digest_value())
	var storage := FakeSaveStorage.new()
	var repository := SaveRootFixture.create_repository(storage)
	add_child_autofree(repository)
	var controller := _controller_for(root, repository)
	assert_true(controller.dispatch(GenerateExpeditionMapCommand.new(catalog)).ok)
	var mapped := repository.load()
	assert_true(mapped.ok)
	if not mapped.ok: return

	assert_true(controller.transition(EnterNodeEvent.new(
		mapped.run.map_state.nodes[0].node_id, catalog,
		EconomyTestFixture.expedition_battle_catalog(root.run.content_snapshot.manifest_digest_value())
	)).ok)
	var after_enter := repository.load()
	assert_true(after_enter.ok)
	if not after_enter.ok: return
	assert_false(after_enter.run.economy_state.shop_offers.is_empty())
	for offer: ShopOffer in after_enter.run.economy_state.shop_offers:
		assert_true(
			after_enter.run.discovered_content_ids.has(offer.unit_def_id),
			"expected %s discovered after node entry regenerated shop offers" % offer.unit_def_id
		)
	assert_true(after_enter.profile.discovered_content_ids.has(&"unit.fixture"))


## w2 review addition (gap: ChooseRewardCommand only marked RELIC offers, not
## ITEM/裝備直發 offers granted via RewardService._grant_item -- see
## choose_reward_command.gd _mark_relic_discovery). Mirrors
## test_choose_reward_command_marks_granted_relic_discovered with an ITEM offer
## in place of the RELIC offer. Reuses &"relic.fixture" as the granted item's
## content_id (not because an ITEM would realistically grant a relic, but
## because it's the only non-unit id in SaveRootFixture.create_receipt()'s
## enabled list -- any other made-up id gets marked content-incompatible by
## SaveJsonCodec's migration-port receipt check and fails save for an unrelated
## reason). What's under test here is the RewardKind.ITEM discovery-marking
## path, not the specific content_id value.
func test_choose_reward_command_marks_granted_item_discovered() -> void:
	var root := ResolutionFixtureFactory.create_root(ResolutionState.Kind.REWARD_PENDING)
	assert_false(root.run.discovered_content_ids.has(&"relic.fixture"))
	var pending := (root.run.resolution_state as RewardPendingResolutionState).pending_reward
	var item_offer := RewardOfferState.new(
		"choice_2", RewardOfferState.RewardKind.ITEM,
		OptionalStringNameValue.of(&"relic.fixture"), 0, null,
		ResolutionFixtureFactory.PAYLOAD_REWARD
	)
	pending.offers[2] = item_offer
	var storage := FakeSaveStorage.new()
	var repository := SaveRootFixture.create_repository(storage)
	add_child_autofree(repository)
	var lease := TestCatalogLease.new(root.run.content_snapshot.manifest_digest_value())
	var session := RunSession.new(root.profile, root.run, lease)
	var factory := RunSaveRootFactory.new("0.1.0", FixedRunCommitClock.new())
	var controller := RunController.new(session, repository, RunStateValidator.new(), factory)
	var catalog := EconomyTestFixture.save_fixture_catalog(root.run.content_snapshot.manifest_digest_value())

	var result := controller.dispatch(ChooseRewardCommand.new("choice_2", catalog))
	assert_true(result.ok, _command_error_text(result.error))
	if not result.ok: return
	var loaded := repository.load()
	assert_true(loaded.ok)
	if not loaded.ok: return
	assert_true(
		loaded.run.discovered_content_ids.has(&"relic.fixture"),
		"granted item (RewardKind.ITEM direct-grant, content_id=relic.fixture) must be recorded in run.discovered_content_ids"
	)
	assert_true(loaded.profile.discovered_content_ids.has(&"relic.fixture"))


func _prepared_root() -> SaveRoot:
	var root := SaveRootFixture.create_valid_root()
	var catalog := EconomyTestFixture.save_fixture_catalog(root.run.content_snapshot.manifest_digest_value())
	root.run.run_phase = RunState.RunPhase.MAP
	root.run.current_node_id = null
	root.run.map_state.current_node_id = null
	root.run.map_state.completed_node_ids.clear()
	root.run.resolution_state = IdleResolutionState.new()
	root.run.economy_state = EconomyState.new(47, 3, 0, 5, 0, 0, [])
	root.run.unit_pool_state = catalog.create_initial_pool()
	root.run.unit_pool_state.entries[0].remaining_copies -= 1
	root.run.unit_pool_state.entries[0].held_copies = 1
	var no_equipment: Array[String] = []
	var unit := UnitInstance.new(
		"u_0000000000000001", &"unit.fixture", 1,
		no_equipment, U64Bits.one()
	)
	var placements: Array[BoardPlacementState] = [
		BoardPlacementState.new(3, 3, unit.instance_id)
	]
	var bench: Array[String] = []
	var units: Array[UnitInstance] = [unit]
	var items: Array[ItemInstanceState] = []
	var item_ids: Array[String] = []
	var relics: Array[RelicSlotState] = []
	for index: int in range(5):
		relics.append(RelicSlotState.new(index, null))
	root.run.roster_state = RosterState.new(
		BoardState.new(placements), bench, units, items,
		item_ids, item_ids, relics
	)
	root.run.reservation_owners.clear()
	root.run.transaction_receipts.clear()
	root.run.income_claimed_node_ids.clear()
	root.run.next_transaction_serial = U64Bits.zero()
	root.run.next_unit_serial = U64Bits.from_u32(0, 2).value
	return root


func _controller_for(root: SaveRoot, repository: SaveRepository) -> RunController:
	var session := RunSession.new(
		root.profile, root.run,
		TestCatalogLease.new(root.run.content_snapshot.manifest_digest_value())
	)
	return RunController.new(
		session, repository, RunStateValidator.new(),
		RunSaveRootFactory.new("0.1.0", FixedRunCommitClock.new())
	)


func _empty_battle_catalog() -> BattleRuleCatalog:
	var units: Array[BattleUnitRule] = []
	var traits: Array[BattleTraitRule] = []
	var abilities: Array[BattleAbilityRule] = []
	var effects: Array[BattleEffectRule] = []
	var encounters: Array[BattleEncounterRule] = []
	var equipment: Array[BattleEquipmentRule] = []
	var configs: Array[BattleCombatConfigRule] = []
	return BattleRuleCatalog.new(
		SaveRootFixture.MANIFEST_DIGEST, units, traits, abilities, effects,
		encounters, equipment, configs
	)


func _command_error_text(error: CommandError) -> String:
	if error == null:
		return "none"
	return "%s:%s" % [String(error.code), String(error.field_path)]
