extends GutTest

func test_loss_settlement_discards_proposals_pays_stipend_once_and_releases_shop() -> void:
	var root := _battle_root(MapNodeState.NodeKind.NORMAL)
	root.run.economy_state.loss_streak = 1
	var discarded := _proposal(&"effect.loss", &"add_gold", 50)
	_set_result(root.run, &"player_loss", 20, [discarded])
	var catalog := EconomyTestFixture.settlement_catalog(
		root.run.content_snapshot.manifest_digest_value()
	)
	var settled := BattleSettlementService.new().settle(root.run, catalog)
	assert_true(settled.ok, "%s:%s" % [
		String(settled.error.code) if settled.error != null else "none",
		String(settled.error.field_path) if settled.error != null else "none",
	])
	if not settled.ok: return
	assert_eq(settled.run_state.expedition_hp, 80)
	assert_eq(settled.run_state.economy_state.gold, root.run.economy_state.gold + 3)
	assert_eq(settled.run_state.economy_state.loss_streak, 2)
	assert_eq(settled.run_state.economy_state.win_streak, 0)
	assert_eq(settled.run_state.loss_stipend_claimed_act_ids, [0])
	assert_eq(settled.run_state.claim_receipts.size(), root.run.claim_receipts.size())
	assert_eq(settled.run_state.run_phase, RunState.RunPhase.MAP)
	assert_true(settled.run_state.map_state.nodes[0].completed)
	assert_eq(settled.run_state.economy_state.shop_offers.size(), 0)
	_assert_pool_conserved(settled.run_state.unit_pool_state)
	var retry := BattleSettlementService.new().settle(settled.run_state, catalog)
	assert_false(retry.ok)

func test_boss_loss_retries_without_income_reward_or_shop_release() -> void:
	var root := _battle_root(MapNodeState.NodeKind.BOSS)
	root.run.economy_state.loss_streak = 1
	_set_result(root.run, &"player_loss", 22, [])
	var catalog := EconomyTestFixture.settlement_catalog(
		root.run.content_snapshot.manifest_digest_value()
	)
	var before_offers := root.run.economy_state.shop_offers.size()
	var before_income := root.run.income_claimed_node_ids.duplicate()
	var settled := BattleSettlementService.new().settle(root.run, catalog)
	assert_true(settled.ok)
	if not settled.ok: return
	assert_eq(settled.run_state.run_phase, RunState.RunPhase.PREPARE)
	assert_true(settled.run_state.resolution_state is IdleResolutionState)
	assert_eq(settled.run_state.economy_state.shop_offers.size(), before_offers)
	assert_eq(settled.run_state.income_claimed_node_ids, before_income)
	assert_false(settled.run_state.map_state.nodes[0].completed)
	assert_eq(settled.run_state.loss_stipend_claimed_act_ids, [0])
	var abandoned := BattleSettlementService.new().abandon_boss_retry(
		settled.run_state, catalog
	)
	assert_true(abandoned.ok)
	if not abandoned.ok: return
	assert_eq(abandoned.run_state.expedition_hp, 0)
	assert_eq(abandoned.run_state.run_phase, RunState.RunPhase.RESULTS)
	assert_true(abandoned.run_state.map_state.nodes[0].completed)
	assert_eq(abandoned.run_state.economy_state.shop_offers.size(), 0)

func test_lethal_normal_and_boss_losses_enter_terminal_results() -> void:
	for kind: MapNodeState.NodeKind in [
		MapNodeState.NodeKind.NORMAL, MapNodeState.NodeKind.BOSS,
	]:
		var root := _battle_root(kind)
		root.run.expedition_hp = 20
		_set_result(root.run, &"player_loss", 20, [])
		var catalog := EconomyTestFixture.settlement_catalog(
			root.run.content_snapshot.manifest_digest_value()
		)
		var settled := BattleSettlementService.new().settle(root.run, catalog)
		assert_true(settled.ok, "kind %d" % kind)
		if not settled.ok: continue
		assert_eq(settled.run_state.expedition_hp, 0)
		assert_eq(settled.run_state.run_phase, RunState.RunPhase.RESULTS)
		assert_true(settled.run_state.resolution_state is IdleResolutionState)
		assert_true(settled.run_state.map_state.nodes[0].completed)

func test_act_three_boss_final_reward_enters_terminal_results() -> void:
	var root := _battle_root(MapNodeState.NodeKind.BOSS)
	_replace_node_kind(root.run, MapNodeState.NodeKind.BOSS, 3)
	var catalog := EconomyTestFixture.settlement_catalog(
		root.run.content_snapshot.manifest_digest_value()
	)
	var settled := BattleSettlementService.new().settle(root.run, catalog)
	assert_true(settled.ok)
	if not settled.ok: return
	var pending := (settled.run_state.resolution_state as RewardPendingResolutionState).pending_reward
	var chosen := RewardService.new().choose(
		settled.run_state, pending.offers[0].choice_id, catalog
	)
	assert_true(chosen.ok)
	if not chosen.ok: return
	var advanced := RewardService.new().advance(chosen.run_state, catalog)
	assert_true(advanced.ok)
	if not advanced.ok: return
	assert_eq(advanced.run_state.run_phase, RunState.RunPhase.RESULTS)
	assert_true(advanced.run_state.resolution_state is IdleResolutionState)

func test_win_applies_scalar_claims_once_and_persists_reward_before_choice() -> void:
	var root := _battle_root(MapNodeState.NodeKind.NORMAL)
	root.run.economy_state.gold = 98
	root.run.economy_state.level = 3
	root.run.economy_state.xp = 3
	root.run.expedition_hp = 98
	var proposals: Array[RunMutationProposal] = [
		_proposal(&"effect.gold", &"add_gold", 10),
		_proposal(&"effect.hp", &"heal_expedition_hp", 10),
		_proposal(&"effect.xp", &"add_xp", 4),
	]
	_set_result(root.run, &"player_win", 0, proposals)
	var catalog := EconomyTestFixture.settlement_catalog(
		root.run.content_snapshot.manifest_digest_value()
	)
	var settled := BattleSettlementService.new().settle(root.run, catalog)
	assert_true(settled.ok, "%s:%s" % [
		String(settled.error.code) if settled.error != null else "none",
		String(settled.error.field_path) if settled.error != null else "none",
	])
	if not settled.ok: return
	assert_eq(settled.run_state.economy_state.gold, 99)
	assert_eq(settled.run_state.economy_state.level, 4)
	assert_eq(settled.run_state.economy_state.xp, 3)
	assert_eq(settled.run_state.expedition_hp, 100)
	assert_eq(settled.run_state.claim_receipts.size(), root.run.claim_receipts.size() + 3)
	assert_eq(settled.run_state.run_phase, RunState.RunPhase.REWARD)
	var pending := (settled.run_state.resolution_state as RewardPendingResolutionState).pending_reward
	assert_eq(pending.phase, PendingRewardState.Phase.CHOOSING)
	assert_eq(pending.offers.size(), 3)
	var persisted_choice_ids: Array[String] = []
	for offer: RewardOfferState in pending.offers:
		persisted_choice_ids.append(offer.choice_id)
	var cloned := settled.run_state.deep_clone()
	var cloned_pending := (cloned.resolution_state as RewardPendingResolutionState).pending_reward
	var cloned_choice_ids: Array[String] = []
	for offer: RewardOfferState in cloned_pending.offers:
		cloned_choice_ids.append(offer.choice_id)
	assert_eq(cloned_choice_ids, persisted_choice_ids)
	var duplicate := BattleSettlementService.new().settle(settled.run_state, catalog)
	assert_false(duplicate.ok)

func test_standard_reward_always_contains_a_non_unit_and_reserves_unit_copies() -> void:
	var root := _battle_root(MapNodeState.NodeKind.NORMAL)
	root.run.unit_pool_state.entries[0].total_copies = 8
	root.run.unit_pool_state.entries[0].remaining_copies = 3
	var catalog := EconomyTestFixture.mixed_reward_catalog(
		root.run.content_snapshot.manifest_digest_value()
	)
	var settled := BattleSettlementService.new().settle(root.run, catalog)
	assert_true(settled.ok)
	if not settled.ok: return
	var pending := (settled.run_state.resolution_state as RewardPendingResolutionState).pending_reward
	var non_unit_count := 0
	var unit_count := 0
	for offer: RewardOfferState in pending.offers:
		if offer.reward_kind == RewardOfferState.RewardKind.UNIT:
			unit_count += 1
		else:
			non_unit_count += 1
	assert_eq(pending.offers.size(), 3)
	assert_gt(non_unit_count, 0)
	assert_gt(unit_count, 0)
	assert_eq(pending.reserved_copies.size(), unit_count)
	_assert_pool_conserved(settled.run_state.unit_pool_state)

func test_reward_conditions_filter_roster_inventory_hp_and_pool_deterministically() -> void:
	var root := _battle_root(MapNodeState.NodeKind.NORMAL)
	root.run.expedition_hp = 40
	for index: int in range(9):
		root.run.roster_state.bench_unit_instance_ids.append("bench_%d" % index)
	for index: int in range(16):
		root.run.roster_state.inventory_item_instance_ids.append("item_%d" % index)
	var base := EconomyTestFixture.settlement_catalog(
		root.run.content_snapshot.manifest_digest_value()
	)
	var roster_condition: Array[RewardConditionRule] = [
		RewardConditionRule.new(&"roster_space_at_least", 1),
		RewardConditionRule.new(
			&"pool_copies_at_least", 1,
			OptionalStringNameValue.of(&"unit.fixture")
		),
	]
	var inventory_condition: Array[RewardConditionRule] = [
		RewardConditionRule.new(&"inventory_space_at_least", 1),
	]
	var hp_condition: Array[RewardConditionRule] = [
		RewardConditionRule.new(&"expedition_hp_below", 50),
	]
	var candidates: Array[RewardCandidateRule] = [
		RewardCandidateRule.new(
			&"unit", OptionalStringNameValue.of(&"unit.fixture"),
			100, 1, roster_condition
		),
		RewardCandidateRule.new(
			&"item", OptionalStringNameValue.of(&"item.fixture"),
			100, 1, inventory_condition
		),
		RewardCandidateRule.new(&"gold", null, 1, 3, hp_condition),
		RewardCandidateRule.new(&"heal", null, 1, 10),
	]
	var tables: Array[RewardTableRule] = [
		RewardTableRule.new(&"reward.conditioned", candidates, 3),
	]
	var nodes: Array[MapNodeRule] = []
	for kind: int in range(7):
		nodes.append_array(base.map_nodes_for(kind))
	var catalog := EconomyExpeditionCatalog.new(
		base.manifest_digest_value(), base.config(), base.shop_units(), nodes, tables
	)
	var generated := RewardService.new().generate_stage(
		root.run, PendingRewardState.StageId.STANDARD, catalog
	)
	assert_true(generated.ok)
	if not generated.ok: return
	var pending := (generated.run_state.resolution_state as RewardPendingResolutionState).pending_reward
	for offer: RewardOfferState in pending.offers:
		assert_ne(offer.reward_kind, RewardOfferState.RewardKind.UNIT)
		assert_ne(offer.reward_kind, RewardOfferState.RewardKind.ITEM)
	var blocked_root := _battle_root(MapNodeState.NodeKind.NORMAL)
	blocked_root.run.expedition_hp = 100
	for index: int in range(9):
		blocked_root.run.roster_state.bench_unit_instance_ids.append("bench_%d" % index)
	for index: int in range(16):
		blocked_root.run.roster_state.inventory_item_instance_ids.append("item_%d" % index)
	var fallback := RewardService.new().generate_stage(
		blocked_root.run, PendingRewardState.StageId.STANDARD, catalog
	)
	assert_true(fallback.ok)
	if not fallback.ok: return
	var fallback_pending := (fallback.run_state.resolution_state as RewardPendingResolutionState).pending_reward
	for offer: RewardOfferState in fallback_pending.offers:
		assert_eq(offer.reward_kind, RewardOfferState.RewardKind.EVENT)

func test_elite_standard_then_relic_keeps_shop_until_final_exit() -> void:
	var root := _battle_root(MapNodeState.NodeKind.ELITE)
	var catalog := EconomyTestFixture.settlement_catalog(
		root.run.content_snapshot.manifest_digest_value()
	)
	var initial_shop_count := root.run.economy_state.shop_offers.size()
	var settled := BattleSettlementService.new().settle(root.run, catalog)
	assert_true(settled.ok)
	if not settled.ok: return
	var standard := (settled.run_state.resolution_state as RewardPendingResolutionState).pending_reward
	var standard_chosen := RewardService.new().choose(
		settled.run_state, standard.offers[0].choice_id, catalog
	)
	assert_true(standard_chosen.ok)
	if not standard_chosen.ok: return
	var relic_stage := RewardService.new().advance(standard_chosen.run_state, catalog)
	assert_true(relic_stage.ok)
	if not relic_stage.ok: return
	var relic_pending := (relic_stage.run_state.resolution_state as RewardPendingResolutionState).pending_reward
	assert_eq(relic_pending.stage_id, PendingRewardState.StageId.RELIC)
	assert_eq(relic_pending.phase, PendingRewardState.Phase.CHOOSING)
	assert_eq(relic_stage.run_state.economy_state.shop_offers.size(), initial_shop_count)
	var relic_chosen := RewardService.new().choose(
		relic_stage.run_state, relic_pending.offers[0].choice_id, catalog
	)
	assert_true(relic_chosen.ok)
	if not relic_chosen.ok: return
	var advanced := RewardService.new().advance(relic_chosen.run_state, catalog)
	assert_true(advanced.ok)
	if not advanced.ok: return
	assert_eq(advanced.run_state.run_phase, RunState.RunPhase.MAP)
	assert_eq(advanced.run_state.economy_state.shop_offers.size(), 0)
	_assert_pool_conserved(advanced.run_state.unit_pool_state)

func test_full_bench_unit_reward_can_be_abandoned_without_softlock() -> void:
	var root := _reward_root()
	var entry := root.run.unit_pool_state.entries[0]
	entry.total_copies = 15
	entry.held_copies = 9
	entry.reserved_copies = 6
	entry.remaining_copies = 0
	for index: int in range(9):
		var id := "u_%016x" % (index + 1)
		var no_equipment: Array[String] = []
		root.run.roster_state.unit_instances.append(UnitInstance.new(
			id, &"unit.fixture", 1, no_equipment,
			U64Bits.from_u32(0, index + 1).value
		))
		root.run.roster_state.bench_unit_instance_ids.append(id)
	var catalog := EconomyTestFixture.settlement_catalog(
		root.run.content_snapshot.manifest_digest_value()
	)
	var chosen := RewardService.new().choose(root.run, "choice_0", catalog)
	assert_true(chosen.ok)
	if not chosen.ok: return
	var battle_catalog := EconomyTestFixture.battle_catalog(
		root.run.content_snapshot.manifest_digest_value()
	)
	var blocked := RewardService.new().resolve_unit(
		chosen.run_state, true, catalog, battle_catalog
	)
	assert_false(blocked.ok)
	assert_eq(blocked.error.code, ExpeditionActionError.ROSTER_FULL)
	var abandoned := RewardService.new().resolve_unit(
		chosen.run_state, false, catalog, battle_catalog
	)
	assert_true(abandoned.ok)
	if not abandoned.ok: return
	var pending := (abandoned.run_state.resolution_state as RewardPendingResolutionState).pending_reward
	assert_eq(pending.phase, PendingRewardState.Phase.READY_TO_ADVANCE)
	var advanced := RewardService.new().advance(abandoned.run_state, catalog)
	assert_true(advanced.ok)
	if not advanced.ok: return
	assert_eq(advanced.run_state.run_phase, RunState.RunPhase.MAP)
	assert_eq(advanced.run_state.unit_pool_state.entries[0].reserved_copies, 0)
	_assert_pool_conserved(advanced.run_state.unit_pool_state)

func test_item_overflow_and_full_relic_slots_remain_recoverable_subphases() -> void:
	var catalog: EconomyExpeditionCatalog
	var item_root := _reward_root()
	_prepare_non_unit_offer(
		item_root.run, RewardOfferState.RewardKind.ITEM, &"item.fixture",
		"choice_item"
	)
	for index: int in range(16):
		var item_id := "i_%016x" % (index + 1)
		item_root.run.roster_state.item_instances.append(ItemInstanceState.new(
			item_id, &"item.existing", null,
			U64Bits.from_u32(0, index + 1).value
		))
		item_root.run.roster_state.inventory_item_instance_ids.append(item_id)
	item_root.run.next_item_serial = U64Bits.from_u32(0, 17).value
	catalog = EconomyTestFixture.settlement_catalog(
		item_root.run.content_snapshot.manifest_digest_value()
	)
	var item_chosen := RewardService.new().choose(
		item_root.run, "choice_item", catalog
	)
	assert_true(item_chosen.ok)
	if not item_chosen.ok: return
	var item_pending := (item_chosen.run_state.resolution_state as RewardPendingResolutionState).pending_reward
	assert_eq(item_pending.phase, PendingRewardState.Phase.ITEM_RESOLUTION)
	assert_eq(item_chosen.run_state.roster_state.pending_item_overflow.size(), 1)
	var overflow_id := item_chosen.run_state.roster_state.pending_item_overflow[0]
	var item_resolved := RewardService.new().resolve_item(
		item_chosen.run_state, overflow_id, true, catalog
	)
	assert_true(item_resolved.ok)
	assert_eq((item_resolved.run_state.resolution_state as RewardPendingResolutionState).pending_reward.phase, PendingRewardState.Phase.READY_TO_ADVANCE)

	var relic_root := _reward_root()
	_prepare_non_unit_offer(
		relic_root.run, RewardOfferState.RewardKind.RELIC, &"relic.new",
		"choice_relic"
	)
	var relic_pending := (relic_root.run.resolution_state as RewardPendingResolutionState).pending_reward
	relic_pending.stage_id = PendingRewardState.StageId.RELIC
	for slot: RelicSlotState in relic_root.run.roster_state.active_relic_slots:
		slot.relic_id = OptionalStringNameValue.of(StringName("relic.old_%d" % slot.slot_index))
	catalog = EconomyTestFixture.settlement_catalog(
		relic_root.run.content_snapshot.manifest_digest_value()
	)
	var relic_chosen := RewardService.new().choose(
		relic_root.run, "choice_relic", catalog
	)
	assert_true(relic_chosen.ok)
	if not relic_chosen.ok: return
	assert_eq((relic_chosen.run_state.resolution_state as RewardPendingResolutionState).pending_reward.phase, PendingRewardState.Phase.RELIC_RESOLUTION)
	var relic_resolved := RewardService.new().resolve_relic(
		relic_chosen.run_state, 2, catalog
	)
	assert_true(relic_resolved.ok)
	assert_eq(relic_resolved.run_state.roster_state.active_relic_slots[2].relic_id.value, &"relic.new")

func test_unit_reward_sell_equipment_overflow_keeps_exact_reservation() -> void:
	var root := _reward_root()
	var catalog := EconomyTestFixture.settlement_catalog(
		root.run.content_snapshot.manifest_digest_value()
	)
	var chosen := RewardService.new().choose(root.run, "choice_0", catalog)
	assert_true(chosen.ok)
	if not chosen.ok: return
	var draft := chosen.run_state
	var inventory_ids: Array[String] = []
	for index: int in range(16):
		var inventory_id := "it_%016x" % (index + 1)
		draft.roster_state.item_instances.append(ItemInstanceState.new(
			inventory_id, &"item.inventory", null,
			U64Bits.from_u32(0, index + 1).value
		))
		inventory_ids.append(inventory_id)
	draft.roster_state.inventory_item_instance_ids = inventory_ids
	var sold_unit_id := "u_0000000000000010"
	var equipped_id := "it_0000000000000011"
	draft.roster_state.item_instances.append(ItemInstanceState.new(
		equipped_id, &"item.equipped",
		OptionalStringValue.new(sold_unit_id),
		U64Bits.from_u32(0, 17).value
	))
	draft.next_item_serial = U64Bits.from_u32(0, 18).value
	var equipped: Array[String] = [equipped_id]
	draft.roster_state.unit_instances.append(UnitInstance.new(
		sold_unit_id, &"unit.fixture", 1, equipped,
		U64Bits.from_u32(0, 16).value
	))
	draft.roster_state.bench_unit_instance_ids.append(sold_unit_id)
	draft.unit_pool_state.entries[0].total_copies += 1
	draft.unit_pool_state.entries[0].held_copies += 1
	var sold := SellUnitCommand.new(sold_unit_id, catalog).apply_to(draft)
	assert_true(sold.ok)
	if not sold.ok: return
	var pending := (sold.draft.resolution_state as RewardPendingResolutionState).pending_reward
	assert_eq(pending.phase, PendingRewardState.Phase.ITEM_RESOLUTION)
	assert_not_null(pending.selected_unit_reservation)
	assert_eq(pending.reserved_copies.size(), 1)
	var validation := RunStateValidator.new().validate_run(sold.draft)
	assert_true(
		validation.ok,
		String(validation.error.field_path) if validation.error != null else "none"
	)
	var cleared := RewardService.new().resolve_item(
		sold.draft, equipped_id, true, catalog
	)
	assert_true(cleared.ok)
	if not cleared.ok: return
	assert_eq(
		(cleared.run_state.resolution_state as RewardPendingResolutionState).pending_reward.phase,
		PendingRewardState.Phase.UNIT_RESOLUTION
	)

func _battle_root(kind: MapNodeState.NodeKind) -> SaveRoot:
	var root := ResolutionFixtureFactory.create_root(
		ResolutionState.Kind.BATTLE_RESULT_PENDING
	)
	root.run.run_phase = RunState.RunPhase.COMBAT
	_replace_node_kind(root.run, kind)
	var node_id := root.run.map_state.nodes[0].node_id
	root.run.current_node_id = OptionalStringValue.new(node_id)
	root.run.map_state.current_node_id = OptionalStringValue.new(node_id)
	root.run.income_claimed_node_ids = [node_id]
	root.run.expedition_hp = 100
	return root

func _reward_root() -> SaveRoot:
	var root := ResolutionFixtureFactory.create_root(
		ResolutionState.Kind.REWARD_PENDING
	)
	root.run.run_phase = RunState.RunPhase.REWARD
	var node_id := root.run.map_state.nodes[0].node_id
	root.run.current_node_id = OptionalStringValue.new(node_id)
	root.run.map_state.current_node_id = OptionalStringValue.new(node_id)
	root.run.income_claimed_node_ids = [node_id]
	return root

func _replace_node_kind(
	run: RunState,
	kind: MapNodeState.NodeKind,
	requested_act_index: int = -1
) -> void:
	var old := run.map_state.nodes[0]
	var act_index := old.act_index if requested_act_index < 0 else requested_act_index
	var key_result := RuntimeKeySchemaRegistry.new().build_node(
		StringName(run.run_id), act_index,
		MapNodeState.node_kind_to_token(kind), old.layer_index, old.slot_index
	)
	var key := key_result.key_state as NodeKeyState
	run.map_state.nodes[0] = MapNodeState.new(
		String(key.digest), key, old.def_id, act_index, old.layer_index,
		old.slot_index, kind, old.generated_payload_digest,
		old.encounter_preview, old.completed
	)
	if run.current_node_id != null and run.current_node_id.value == old.node_id:
		run.current_node_id = OptionalStringValue.new(String(key.digest))
	if run.map_state.current_node_id != null \
		and run.map_state.current_node_id.value == old.node_id:
		run.map_state.current_node_id = OptionalStringValue.new(String(key.digest))
	for owner: ReservationOwnerState in run.reservation_owners:
		owner.key.node_id = key.digest
	for offer: ShopOffer in run.economy_state.shop_offers:
		offer.reservation_owner_key.node_id = key.digest
		offer.offer_id = String(offer.reservation_owner_key.digest)
	run.act_index = act_index

func _set_result(
	run: RunState,
	outcome: StringName,
	damage: int,
	proposals: Array[RunMutationProposal]
) -> void:
	var previous := run.resolution_state as BattleResultPendingResolutionState
	var result := BattleResult.new()
	result.battle_setup_hash = StringName(previous.battle_setup_hash)
	result.outcome = outcome
	result.final_tick = 20
	var survivors: Array[StringName] = []
	survivors.append(
		&"e_0000000000000001" \
		if outcome == &"player_loss" else &"u_0000000000000001"
	)
	result.survivor_instance_ids = survivors
	result.expedition_damage = damage
	for proposal: RunMutationProposal in proposals:
		result.run_mutation_proposals.append(proposal.deep_clone())
	result.summary_hash = &"0000000000000000000000000000000000000000000000000000000000000000"
	var sealed := BattleResultCodecV1.new().seal(result.to_record())
	assert_true(sealed.ok)
	run.resolution_state = BattleResultPendingResolutionState.new(
		previous.battle_setup_hash, BattleResult.from_record(sealed.record)
	)

func _proposal(
	effect_id: StringName,
	kind: StringName,
	amount: int
) -> RunMutationProposal:
	var built := RunMutationProposal.create(
		&"once_per_node", "u/u_0000000000000001", effect_id, 0,
		kind, amount
	)
	assert_true(built.ok)
	return built.proposal

func _prepare_non_unit_offer(
	run: RunState,
	kind: RewardOfferState.RewardKind,
	content_id: StringName,
	choice_id: String
) -> void:
	var pending := (run.resolution_state as RewardPendingResolutionState).pending_reward
	for reserved: ReservedCopyState in pending.reserved_copies:
		for owner: ReservationOwnerState in run.reservation_owners:
			if owner.key.digest == reserved.reservation_owner_key.digest:
				owner.status = ReservationOwnerState.Status.RELEASED
				run.unit_pool_state.entries[0].reserved_copies -= reserved.copies
				run.unit_pool_state.entries[0].remaining_copies += reserved.copies
	pending.reserved_copies.clear()
	pending.offers = [RewardOfferState.new(
		choice_id, kind, OptionalStringNameValue.of(content_id), 1, null,
		"7777777777777777777777777777777777777777777777777777777777777777"
	)]

func _assert_pool_conserved(pool: UnitPoolState) -> void:
	for entry: UnitPoolEntryState in pool.entries:
		assert_eq(
			entry.remaining_copies + entry.reserved_copies + entry.held_copies,
			entry.total_copies
		)
