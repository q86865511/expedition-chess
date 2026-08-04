class_name BalanceProductionCaseDriver
extends RefCounted

const COMBAT_STEP_LIMIT: int = 100000
const PREPARE_ACTION_LIMIT: int = 3
const REWARD_STEP_LIMIT: int = 32
const BOSS_RETRY_LIMIT: int = 100
const EXPECTED_FULL_ROUTE_NODES: int = 21

var _content: ProjectContentBootstrapResult
var _storage_factory: Callable
var trace_enabled: bool = false
var diagnostic_node_limit: int = 0
var _active_battle_catalog: BattleRuleCatalog
var _active_battle_passives: Array[StringName] = []


func _init(content: ProjectContentBootstrapResult, storage_factory: Callable) -> void:
	_content = content
	_storage_factory = storage_factory


func run_case(strategy_id: StringName, seed_index: int) -> BalanceBotCaseResult:
	var result := BalanceBotCaseResult.new()
	result.strategy_id = strategy_id
	result.seed_index = seed_index
	result.build_id = &"build.unresolved"
	if _content == null or not _content.ok:
		return _fail(result, &"BALANCE_PRODUCTION_CONTENT_MISSING")
	if not BalanceBotStrategy.IDS.has(strategy_id) or seed_index < 0:
		return _fail(result, &"BALANCE_CASE_INPUT_INVALID")
	if not _storage_factory.is_valid():
		return _fail(result, &"BALANCE_STORAGE_FACTORY_MISSING")

	var commander_id := _commander_id()
	var commander := CommanderContentReader.new().try_read(
		_content.registry, _content.manifest_digest, commander_id
	)
	if commander == null:
		return _fail(result, &"BALANCE_COMMANDER_MISSING")
	var profile := _profile_for_seed(seed_index, commander_id)
	var started := StartExpeditionCommand.new(
		commander_id, commander, 0, _content.receipt,
		_content.economy_catalog
	).apply_to(profile)
	if not started.ok:
		return _fail(result, &"BALANCE_BOOTSTRAP_FAILED")
	result.run_id = StringName(started.run.run_id)
	result.world_digest = _world_digest(started.run)

	var storage: SaveStoragePort = _storage_factory.call()
	if storage == null:
		return _fail(result, &"BALANCE_STORAGE_FACTORY_INVALID")
	var repository := SaveRepository.new(
		storage,
		ContentRegistryReceiptAdapter.new(_content.registry),
		ContentRegistryMigrationAdapter.new(_content.registry),
		RunStateValidator.new()
	)
	var root_factory := RunSaveRootFactory.new(
		"0.2.0", BalanceFixedRunCommitClock.new()
	)
	var saved := repository.save(root_factory.build(started.profile, started.run))
	if not saved.ok:
		repository.free()
		return _fail(result, &"BALANCE_INITIAL_SAVE_FAILED")
	var composition := _compose(started.profile, started.run, repository, root_factory)
	if not bool(composition.get("ok", false)):
		repository.free()
		return _fail(result, StringName(composition.get("error", "BALANCE_COMPOSE_FAILED")))
	var session: RunPresentationSession = composition.session
	var controller: RunController = composition.controller
	var strategy := BalanceBotStrategy.new(strategy_id)
	var replay_parts: Array[String] = [
		"BALANCE-PRODUCTION-CASE-V2", String(result.run_id), result.world_digest,
		String(strategy_id), str(seed_index),
	]
	var previous_node_id := ""
	var generated := _dispatch(session, RunPresentationIntent.Kind.GENERATE_MAP)
	if not generated.is_empty():
		repository.free()
		return _fail(result, generated)
	result.world_digest = _map_world_digest(session.snapshot().map)
	_trace("generated run=%s nodes=%d" % [result.run_id, session.snapshot().map.nodes.size()])

	while session.view_state().run_phase != RunState.RunPhase.RESULTS:
		var view := session.view_state()
		if view.run_phase != RunState.RunPhase.MAP:
			repository.free()
			return _fail(result, &"BALANCE_UNEXPECTED_RUN_PHASE")
		var reachable := session.reachable_nodes()
		if reachable.is_empty():
			repository.free()
			return _fail(result, &"BALANCE_NO_REACHABLE_NODE")
		var node_id := _choose_route_node(
			strategy_id, reachable, session.snapshot().map, previous_node_id
		)
		var node := _try_node(session.snapshot().map, node_id)
		if node == null:
			repository.free()
			return _fail(result, &"BALANCE_ROUTE_NODE_MISSING")
		result.route_ids.append(_route_signature(node))
		_trace("enter completed=%d node=%s act=%d layer=%d kind=%d" % [
			result.completed_node_count, node.node_id, node.act_index,
			node.layer_index, node.node_kind,
		])
		replay_parts.append("route:%s" % node_id)
		var enter := RunPresentationIntent.new(RunPresentationIntent.Kind.ENTER_NODE)
		enter.target_node_id = node_id
		var entered_error := _dispatch_intent(session, enter)
		if not entered_error.is_empty():
			repository.free()
			return _fail(result, entered_error)
		previous_node_id = node_id
		_trace("entered phase=%d choice=%s service=%s" % [
			session.view_state().run_phase,
			str(session.snapshot().node_choice_overlay != null),
			str(session.snapshot().node_service_overlay != null),
		])
		result.act_reached = maxi(result.act_reached, node.act_index)

		if _is_combat(node):
			var combat_error := _resolve_combat_node(
				session, controller, strategy, node, result, replay_parts
			)
			if not combat_error.is_empty():
				repository.free()
				return _fail(result, combat_error)
		else:
			# Some production non-combat nodes resolve on entry; only send the
			# formal resolver while the committed phase still exposes PREPARE.
			if session.view_state().run_phase == RunState.RunPhase.PREPARE \
				and session.snapshot().node_choice_overlay == null:
				var noncombat_error := _dispatch(
					session, RunPresentationIntent.Kind.RESOLVE_NON_COMBAT
				)
				if not noncombat_error.is_empty():
					repository.free()
					return _fail(result, noncombat_error)

		var resolution_error := _resolve_post_node(session, strategy_id, result, replay_parts)
		if not resolution_error.is_empty():
			repository.free()
			return _fail(result, resolution_error)
		result.completed_node_count = session.snapshot().map.completed_node_ids.size()
		if node.node_kind == MapNodeState.NodeKind.BOSS:
			_capture_act_snapshot(session.snapshot(), node.act_index, result, replay_parts)
		_trace("node resolved completed=%d phase=%d" % [
			result.completed_node_count, session.view_state().run_phase,
		])
		if diagnostic_node_limit > 0 \
			and result.completed_node_count >= diagnostic_node_limit:
			repository.free()
			return _fail(result, &"BALANCE_DIAGNOSTIC_NODE_LIMIT")
		if result.reload_count == 0 and result.completed_node_count >= 7 \
			and session.view_state().run_phase == RunState.RunPhase.MAP:
			var loaded := repository.load()
			if not loaded.ok or loaded.run == null:
				repository.free()
				return _fail(result, &"BALANCE_RELOAD_FAILED")
			var reloaded := _compose(loaded.profile, loaded.run, repository, root_factory)
			if not bool(reloaded.get("ok", false)):
				repository.free()
				return _fail(result, &"BALANCE_RECOMPOSE_FAILED")
			session = reloaded.session
			controller = reloaded.controller
			result.reload_count = 1
			replay_parts.append("reload:%s" % String(result.run_id))

	var authoritative := repository.load()
	if not authoritative.ok or authoritative.run == null:
		repository.free()
		return _fail(result, &"BALANCE_FINAL_READBACK_FAILED")
	var final_run: RunState = authoritative.run
	result.terminal = true
	result.final_phase = StringName(RunState.RunPhase.keys()[final_run.run_phase])
	result.completed_node_count = final_run.map_state.completed_node_ids.size()
	result.ending_gold = final_run.economy_state.gold
	result.ending_hp = final_run.expedition_hp
	result.won = result.completed_node_count == EXPECTED_FULL_ROUTE_NODES \
		and result.ending_hp > 0
	result.build_id = _derive_build_id(final_run.roster_state, result.run_id)
	_capture_receipt_proof(final_run, result)
	_validate_case_proof(result)
	replay_parts.append("final:%s:%d:%d:%d" % [
		String(result.final_phase), result.completed_node_count,
		result.ending_gold, result.ending_hp,
	])
	replay_parts.append_array(result.settlement_receipt_digests)
	replay_parts.append_array(result.reward_receipt_digests)
	result.replay_digest = EconomyPayloadDigest.sha256(replay_parts)
	repository.free()
	return result


func _capture_receipt_proof(run: RunState, result: BalanceBotCaseResult) -> void:
	for receipt: TransactionReceiptState in run.transaction_receipts:
		if receipt == null or receipt.key == null:
			continue
		var proof := "%s:%s" % [String(receipt.key.digest), receipt.payload_digest]
		var kind := String(receipt.key.command_kind)
		if kind.begins_with("battle_settle_"):
			result.settlement_receipt_digests.append(proof)
		elif kind.begins_with("reward_"):
			result.reward_receipt_digests.append(proof)
	result.settlement_receipt_digests.sort()
	result.reward_receipt_digests.sort()


func _validate_case_proof(result: BalanceBotCaseResult) -> void:
	if result.final_phase != &"RESULTS":
		_append_failure(result, &"BALANCE_FINAL_PHASE_INVALID")
	if result.completed_node_count != result.route_ids.size():
		_append_failure(result, &"BALANCE_ROUTE_PROOF_MISMATCH")
	if result.settlement_receipt_digests.size() \
		!= result.battle_wins + result.battle_losses:
		_append_failure(result, &"BALANCE_SETTLEMENT_RECEIPT_MISMATCH")
	if _contains_duplicate(result.settlement_receipt_digests):
		_append_failure(result, &"BALANCE_SETTLEMENT_RECEIPT_DUPLICATE")
	if _contains_duplicate(result.reward_receipt_digests):
		_append_failure(result, &"BALANCE_DUPLICATE_REWARD")
	if result.ending_gold < 0 or result.ending_hp < 0:
		_append_failure(result, &"BALANCE_NEGATIVE_RESOURCE")


func _contains_duplicate(values: Array[String]) -> bool:
	for index: int in range(1, values.size()):
		if values[index] == values[index - 1]:
			return true
	return false


func _append_failure(result: BalanceBotCaseResult, code: StringName) -> void:
	if not result.failure_codes.has(code):
		result.failure_codes.append(code)


func _compose(
	profile: ProfileState, run: RunState, repository: SaveRepository,
	root_factory: RunSaveRootFactory
) -> Dictionary:
	var session_result := RunSessionFactory.new(_content.registry).create(profile, run)
	if not session_result.ok:
		return {"ok": false, "error": &"BALANCE_SESSION_FAILED"}
	var table_result := RunModifierTableBuilder.new().build(
		_content.registry, _content.manifest_digest, _content.run_relic_ids,
		run.commander_id, run.challenge_level
	)
	if not table_result.ok:
		return {"ok": false, "error": &"BALANCE_MODIFIER_TABLE_FAILED"}
	var passive_ids := CommanderContentReader.new().passive_effect_ids(
		_content.registry, _content.manifest_digest, run.commander_id
	)
	var roots: Array[StringName] = []
	roots.append_array(_content.unit_ids)
	roots.append_array(_content.equipment_ids)
	roots.append_array(_content.battle_relic_ids)
	roots.append_array(_content.encounter_ids)
	roots.append_array(passive_ids)
	var battle_result := BattleRuleCatalogBuilder.new().build(
		_content.registry, _content.manifest_digest,
		RunCompositionSupport.required_battle_ids(roots, run.challenge_level)
	)
	if not battle_result.ok:
		return {"ok": false, "error": &"BALANCE_BATTLE_CATALOG_FAILED"}
	var affix_result := ChallengeAffixResolver.new().resolve(
		_content.registry, _content.manifest_digest, run.challenge_level
	)
	if not affix_result.ok:
		return {"ok": false, "error": &"BALANCE_AFFIX_FAILED"}
	var affix_ids: Array[StringName] = []
	for entry: ChallengeAffixEntryState in affix_result.entries:
		if entry.track == ChallengeAffixEntryState.BATTLE_AFFIX_TRACK:
			affix_ids.append(entry.effect_id)
	var commander := CommanderContentReader.new().try_read(
		_content.registry, _content.manifest_digest, run.commander_id
	)
	var controller := RunController.new(
		session_result.session, repository, RunStateValidator.new(), root_factory,
		battle_result.catalog
	)
	var factory := RunCommandFactory.new(
		_content.economy_catalog, table_result.table, battle_result.catalog,
		affix_ids, run.commander_id,
		commander.population_bonus if commander != null else 0,
		_content.forge_table, _content.consumable_rules
	)
	var battle_passives: Array[StringName] = []
	for effect_id: StringName in passive_ids:
		var effect_rule := battle_result.catalog.try_effect_rule(effect_id)
		if effect_rule != null and not effect_rule.battle_operations.is_empty():
			battle_passives.append(effect_id)
	_active_battle_catalog = battle_result.catalog
	_active_battle_passives.assign(battle_passives)
	return {
		"ok": true,
		"controller": controller,
		"session": RunPresentationSession.new(
			controller, factory, battle_result.catalog, battle_passives
		),
	}


func _resolve_combat_node(
	session: RunPresentationSession,
	controller: RunController,
	strategy: BalanceBotStrategy,
	node: MapNodeState,
	result: BalanceBotCaseResult,
	replay_parts: Array[String]
) -> StringName:
	for attempt: int in range(BOSS_RETRY_LIMIT + 1):
		var prepare_error := _prepare(session, strategy, result, replay_parts)
		if not prepare_error.is_empty():
			return prepare_error
		_trace("combat start node=%s attempt=%d" % [node.node_id, attempt + 1])
		_trace_battle_validation(
			session, _try_node(session.snapshot().map, node.node_id)
		)
		var combat_started := Time.get_ticks_msec()
		var combat_error := _dispatch(
			session, RunPresentationIntent.Kind.START_OR_RESUME_COMBAT
		)
		_trace("combat end node=%s attempt=%d elapsed_ms=%d" % [
			node.node_id, attempt + 1, Time.get_ticks_msec() - combat_started,
		])
		if not combat_error.is_empty():
			_trace_committed_battle_failure(controller)
			return combat_error
		var committed := controller.committed_combat_snapshot()
		var pending := committed.resolution_state as BattleResultPendingResolutionState \
			if committed != null else null
		if pending == null or pending.battle_result == null:
			return &"BALANCE_BATTLE_RESULT_MISSING"
		var won: bool = pending.battle_result.outcome == &"player_win"
		result.battle_wins += 1 if won else 0
		result.battle_losses += 0 if won else 1
		replay_parts.append("battle:%s" % String(pending.battle_result.result_hash))
		var settle_error := _dispatch(session, RunPresentationIntent.Kind.SETTLE_BATTLE)
		if not settle_error.is_empty():
			return settle_error
		if session.view_state().run_phase != RunState.RunPhase.PREPARE:
			return &""
		if node.node_kind != MapNodeState.NodeKind.BOSS:
			return &"BALANCE_NON_BOSS_RETRY_PHASE"
		if session.view_state().expedition_hp <= 0:
			return &"BALANCE_BOSS_RETRY_HP_INVALID"
		result.boss_retry_count += 1
		replay_parts.append("boss_retry:%s:%d" % [node.node_id, result.boss_retry_count])
	return &"BALANCE_BOSS_RETRY_LIMIT"


func _prepare(
	session: RunPresentationSession, strategy: BalanceBotStrategy,
	result: BalanceBotCaseResult, replay_parts: Array[String]
) -> StringName:
	for _step: int in range(PREPARE_ACTION_LIMIT):
		var snapshot := session.snapshot()
		var actions := _shop_actions(snapshot, strategy.strategy_id)
		var chosen := strategy.try_choose_action(BalanceBotObservation.new(
			session.economy_state().gold, session.economy_state().level,
			session.view_state().expedition_hp, session.view_state().act_index, actions
		))
		if chosen == null or chosen.kind == BalanceBotAction.Kind.HOLD:
			break
		var intent: RunPresentationIntent
		var selected_id := chosen.stable_id
		match chosen.kind:
			BalanceBotAction.Kind.BUY_UNIT:
				intent = RunPresentationIntent.new(RunPresentationIntent.Kind.BUY_UNIT)
				intent.offer_id = String(chosen.stable_id)
				selected_id = _unit_def_id_for_offer(snapshot, String(chosen.stable_id))
			BalanceBotAction.Kind.BUY_XP:
				intent = RunPresentationIntent.new(RunPresentationIntent.Kind.BUY_XP)
			BalanceBotAction.Kind.REROLL:
				intent = RunPresentationIntent.new(RunPresentationIntent.Kind.REFRESH_SHOP)
			BalanceBotAction.Kind.SELL_UNIT:
				intent = RunPresentationIntent.new(RunPresentationIntent.Kind.SELL_UNIT)
				intent.unit_instance_id = String(chosen.stable_id)
			_:
				break
		var error := _dispatch_intent(session, intent)
		if not error.is_empty():
			return error
		match chosen.kind:
			BalanceBotAction.Kind.BUY_UNIT:
				result.buy_unit_count += 1
				result.selected_ids.append(selected_id)
			BalanceBotAction.Kind.BUY_XP:
				result.buy_xp_count += 1
			BalanceBotAction.Kind.REROLL:
				result.reroll_count += 1
			BalanceBotAction.Kind.SELL_UNIT:
				result.sell_unit_count += 1
		replay_parts.append("action:%d:%s" % [chosen.kind, String(chosen.stable_id)])
	return _commit_board(session)


func _shop_actions(
	snapshot: RunPresentationSnapshot, strategy_id: StringName
) -> Array[BalanceBotAction]:
	var actions: Array[BalanceBotAction] = []
	var unit_count := snapshot.roster.unit_instances.size()
	var level := snapshot.economy.level
	var has_affordable_buy := false
	var bench_is_full := snapshot.roster.bench_unit_instance_ids.size() >= 9
	if bench_is_full:
		for instance_id: String in snapshot.roster.bench_unit_instance_ids:
			actions.append(BalanceBotAction.new(
				BalanceBotAction.Kind.SELL_UNIT, StringName(instance_id), 0,
				200, 200, 200
			))
	else:
		for offer: ShopOffer in snapshot.economy.shop_offers:
			var rule := _content.battle_catalog.try_unit_rule(offer.unit_def_id)
			if rule == null:
				continue
			has_affordable_buy = has_affordable_buy \
				or offer.cost <= snapshot.economy.gold
			actions.append(BalanceBotAction.new(
				BalanceBotAction.Kind.BUY_UNIT, StringName(offer.offer_id), offer.cost,
				100 + rule.cost_tier * 20, 20 - offer.cost * 5,
				rule.trait_ids.size() * 30 + rule.effect_ids.size() * 5
			))
	var config := _content.economy_catalog.config()
	var xp_legal := level < 9
	var xp_economy_score := 90
	if strategy_id == BalanceBotStrategy.ECONOMY:
		xp_legal = economy_xp_allowed(
			snapshot.economy.gold, config.xp_buy_cost,
			config.interest_step_gold, config.interest_per_step,
			config.max_interest, unit_count, level
		)
		xp_economy_score = 150
	actions.append(BalanceBotAction.new(
		BalanceBotAction.Kind.BUY_XP, &"action.buy_xp", config.xp_buy_cost,
		40, xp_economy_score, 20, xp_legal
	))
	actions.append(BalanceBotAction.new(
		BalanceBotAction.Kind.REROLL, &"action.refresh_shop", config.reroll_cost,
		80, economy_reroll_score(unit_count, level, has_affordable_buy), 35
	))
	actions.append(BalanceBotAction.new(
		BalanceBotAction.Kind.HOLD, &"action.hold", 0, 0,
		economy_hold_score(unit_count, level), 30
	))
	return actions


static func economy_hold_score(unit_count: int, level: int) -> int:
	return 0 if unit_count < level else 120


static func economy_reroll_score(
	unit_count: int, level: int, has_affordable_buy: bool
) -> int:
	return 40 if unit_count < level and not has_affordable_buy else -40


static func economy_xp_allowed(
	gold: int,
	cost: int,
	interest_step_gold: int,
	interest_per_step: int,
	max_interest: int,
	unit_count: int,
	level: int
) -> bool:
	if level >= 9 or unit_count < level or cost < 0 or gold < cost \
		or interest_step_gold <= 0 or interest_per_step <= 0 or max_interest < 0:
		return false
	@warning_ignore("integer_division")
	var steps_for_max := (max_interest + interest_per_step - 1) / interest_per_step
	return gold - cost >= steps_for_max * interest_step_gold


func _unit_def_id_for_offer(snapshot: RunPresentationSnapshot, offer_id: String) -> StringName:
	for offer: ShopOffer in snapshot.economy.shop_offers:
		if offer.offer_id == offer_id:
			return offer.unit_def_id
	return StringName(offer_id)


func _commit_board(session: RunPresentationSession) -> StringName:
	var snapshot := session.snapshot()
	var ordered: Array[String] = []
	var seen: Dictionary = {}
	var placements_source := snapshot.roster.board.placements.duplicate()
	placements_source.sort_custom(func(a: BoardPlacementState, b: BoardPlacementState) -> bool:
		return a.logical_y < b.logical_y or (a.logical_y == b.logical_y and (
			a.logical_x < b.logical_x or (a.logical_x == b.logical_x \
			and a.unit_instance_id < b.unit_instance_id)))
	)
	for placement: BoardPlacementState in placements_source:
		if not seen.has(placement.unit_instance_id):
			seen[placement.unit_instance_id] = true
			ordered.append(placement.unit_instance_id)
	for instance_id: String in snapshot.roster.bench_unit_instance_ids:
		if not seen.has(instance_id):
			seen[instance_id] = true
			ordered.append(instance_id)
	var placements: Array[BoardPlacementState] = []
	var bench: Array[String] = []
	for index: int in range(ordered.size()):
		if index < snapshot.economy.level:
			@warning_ignore("integer_division")
			placements.append(BoardPlacementState.new(
				index / BoardPreparationValidator.BOARD_WIDTH,
				index % BoardPreparationValidator.BOARD_WIDTH, ordered[index]
			))
		else:
			bench.append(ordered[index])
	var intent := RunPresentationIntent.new(RunPresentationIntent.Kind.COMMIT_BOARD_LAYOUT)
	intent.board = BoardState.new(placements)
	intent.bench_unit_instance_ids.assign(bench)
	return _dispatch_intent(session, intent)


func _resolve_post_node(
	session: RunPresentationSession, strategy_id: StringName,
	result: BalanceBotCaseResult, replay_parts: Array[String]
) -> StringName:
	for _step: int in range(REWARD_STEP_LIMIT):
		var snapshot := session.snapshot()
		if snapshot.view.run_phase in [RunState.RunPhase.MAP, RunState.RunPhase.RESULTS]:
			return &""
		var intent: RunPresentationIntent
		if snapshot.node_choice_overlay != null:
			_trace("post-node commit choice")
			var options := snapshot.node_choice_overlay.options.duplicate()
			options.sort_custom(func(a: NodeChoiceOptionSnapshot, b: NodeChoiceOptionSnapshot) -> bool:
				return String(a.choice_id) < String(b.choice_id)
			)
			var option: NodeChoiceOptionSnapshot = options[-1] \
				if strategy_id == BalanceBotStrategy.SYNERGY else options[0]
			intent = RunPresentationIntent.new(RunPresentationIntent.Kind.COMMIT_NODE_CHOICE)
			intent.choice_set_id = snapshot.node_choice_overlay.choice_set_id
			intent.node_choice_payload = snapshot.node_choice_overlay.commit_payload(
				snapshot.run_id, option.choice_id
			)
			result.selected_ids.append(option.choice_id)
			replay_parts.append("choice:%s" % String(option.choice_id))
		elif snapshot.node_service_overlay != null:
			_trace("post-node exit service")
			intent = RunPresentationIntent.new(RunPresentationIntent.Kind.EXIT_NODE_SERVICE)
			intent.expected_run_id = String(snapshot.run_id)
			intent.node_id = snapshot.node_service_overlay.node_id
			intent.choice_receipt_digest = snapshot.node_service_overlay.choice_receipt_digest
		elif not snapshot.pending_node_choice_results.is_empty():
			_trace("post-node acknowledge choice")
			var receipt := snapshot.pending_node_choice_results[0]
			intent = RunPresentationIntent.new(
				RunPresentationIntent.Kind.ACKNOWLEDGE_NODE_CHOICE_RESULT
			)
			intent.expected_run_id = String(snapshot.run_id)
			intent.receipt_digest = receipt.receipt_digest
		elif snapshot.view.run_phase == RunState.RunPhase.REWARD:
			_trace("post-node reward phase=%d" % snapshot.pending_reward.phase)
			intent = _reward_intent(snapshot, strategy_id, result, replay_parts)
		else:
			return &"BALANCE_POST_NODE_STATE_UNSUPPORTED"
		var error := _dispatch_intent(session, intent)
		if not error.is_empty():
			_trace("post-node error=%s" % String(error))
			return error
	return &"BALANCE_POST_NODE_STEP_LIMIT"


func _reward_intent(
	snapshot: RunPresentationSnapshot, strategy_id: StringName,
	result: BalanceBotCaseResult, replay_parts: Array[String]
) -> RunPresentationIntent:
	var pending := snapshot.pending_reward
	match pending.phase:
		PendingRewardState.Phase.CHOOSING:
			var offers := pending.offers.duplicate()
			offers.sort_custom(func(a: RewardOfferState, b: RewardOfferState) -> bool:
				return a.choice_id < b.choice_id
			)
			var offer = offers[-1] if strategy_id == BalanceBotStrategy.SYNERGY else offers[0]
			var intent := RunPresentationIntent.new(
				RunPresentationIntent.Kind.CHOOSE_STANDARD_REWARD
			)
			intent.choice_id = offer.choice_id
			var selected_id := StringName("reward.kind.%d" % int(offer.reward_kind))
			if offer.content_id != null and not offer.content_id.value.is_empty():
				selected_id = offer.content_id.value
			result.selected_ids.append(selected_id)
			replay_parts.append("reward:%s" % offer.choice_id)
			return intent
		PendingRewardState.Phase.UNIT_RESOLUTION:
			var intent := RunPresentationIntent.new(RunPresentationIntent.Kind.RESOLVE_UNIT_REWARD)
			intent.accept = true
			return intent
		PendingRewardState.Phase.ITEM_RESOLUTION:
			var intent := RunPresentationIntent.new(RunPresentationIntent.Kind.RESOLVE_ITEM_REWARD)
			intent.item_instance_id = snapshot.roster.pending_item_overflow[0] \
				if not snapshot.roster.pending_item_overflow.is_empty() else ""
			intent.abandon = intent.item_instance_id.is_empty()
			return intent
		PendingRewardState.Phase.RELIC_RESOLUTION:
			var intent := RunPresentationIntent.new(RunPresentationIntent.Kind.RESOLVE_RELIC_REWARD)
			intent.relic_slot_index = 0
			return intent
	return RunPresentationIntent.new(RunPresentationIntent.Kind.ADVANCE_REWARD)


func _dispatch(session: RunPresentationSession, kind: RunPresentationIntent.Kind) -> StringName:
	return _dispatch_intent(session, RunPresentationIntent.new(kind))


func _dispatch_intent(session: RunPresentationSession, intent: RunPresentationIntent) -> StringName:
	var dispatched := session.dispatch(intent)
	return &"" if dispatched.ok else dispatched.error.source_code


func _choose_route_node(
	strategy_id: StringName, reachable: Array, map: MapState,
	previous_node_id: String
) -> String:
	var best_id := ""
	var best_score := -2147483648
	var frontier := -1
	for presentation: MapNodePresentation in reachable:
		var candidate: MapNodeState = _try_node(map, presentation.node_id)
		if candidate != null and _continues_route(
			map, previous_node_id, candidate.node_id
		):
			frontier = maxi(frontier, candidate.act_index * 100 + candidate.layer_index)
	for presentation: MapNodePresentation in reachable:
		var node: MapNodeState = _try_node(map, presentation.node_id)
		if node == null or not _continues_route(map, previous_node_id, node.node_id) \
			or node.act_index * 100 + node.layer_index != frontier:
			continue
		var score := _route_score(strategy_id, node.node_kind)
		if score > best_score or (score == best_score and node.node_id < best_id):
			best_score = score
			best_id = node.node_id
	return best_id


func _continues_route(map: MapState, previous_node_id: String, node_id: String) -> bool:
	if previous_node_id.is_empty():
		var node := _try_node(map, node_id)
		return node != null and node.act_index == 1 and node.layer_index == 0
	for edge: MapEdgeState in map.edges:
		if edge.from_node_id == previous_node_id and edge.to_node_id == node_id:
			return true
	return false


func _route_score(strategy_id: StringName, kind: MapNodeState.NodeKind) -> int:
	if kind == MapNodeState.NodeKind.BOSS:
		return 1000
	match strategy_id:
		BalanceBotStrategy.TEMPO:
			return 100 if kind == MapNodeState.NodeKind.ELITE else 50
		BalanceBotStrategy.ECONOMY:
			return 100 if kind in [MapNodeState.NodeKind.MERCHANT, MapNodeState.NodeKind.REST] else 30
		BalanceBotStrategy.SYNERGY:
			return 100 if kind in [MapNodeState.NodeKind.TREASURE, MapNodeState.NodeKind.EVENT] else 40
	return 0


func _try_node(map: MapState, node_id: String) -> MapNodeState:
	for node: MapNodeState in map.nodes:
		if node.node_id == node_id:
			return node
	return null


func _is_combat(node: MapNodeState) -> bool:
	return node.node_kind in [
		MapNodeState.NodeKind.NORMAL, MapNodeState.NodeKind.ELITE,
		MapNodeState.NodeKind.BOSS,
	]


func _route_signature(node: MapNodeState) -> StringName:
	return StringName("route.act%d.layer%d.%s" % [
		node.act_index, node.layer_index,
		String(MapNodeState.NodeKind.keys()[node.node_kind]).to_lower(),
	])


func _commander_id() -> StringName:
	var ids := _content.commander_ids.duplicate()
	ids.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	for commander_id: StringName in ids:
		if _content.base_profile_unlocked_content_ids.has(commander_id):
			return commander_id
	return ids[0] if not ids.is_empty() else &""


func _profile_for_seed(seed_index: int, commander_id: StringName) -> ProfileState:
	var profile_id := EconomyPayloadDigest.sha256([
		"balance-profile-v1", str(seed_index)
	]).substr(0, 32)
	var unlocked := _content.base_profile_unlocked_content_ids.duplicate()
	if not unlocked.has(commander_id):
		unlocked.append(commander_id)
	return ProfileState.new(
		profile_id, U64Bits.one(), 0, unlocked, [] as Array[StringName], 0,
		[] as Array[SettlementReceiptState], &"settings.default", null,
		[] as Array[CommanderChallengeRecordState]
	)


func _world_digest(run: RunState) -> String:
	return EconomyPayloadDigest.sha256([
		run.run_id, run.run_seed.to_hex(), run.content_snapshot.manifest_digest_value()
	])


func _map_world_digest(map: MapState) -> String:
	var parts: Array[String] = ["BALANCE-WORLD-V1"]
	for node: MapNodeState in map.nodes:
		parts.append("%s:%d:%d:%d" % [
			node.node_id, node.act_index, node.layer_index, node.node_kind
		])
	for edge: MapEdgeState in map.edges:
		parts.append("%s>%s" % [edge.from_node_id, edge.to_node_id])
	return EconomyPayloadDigest.sha256(parts)


func _capture_act_snapshot(
	snapshot: RunPresentationSnapshot,
	act_index: int,
	result: BalanceBotCaseResult,
	replay_parts: Array[String]
) -> void:
	for existing: BalanceBotActSnapshot in result.act_snapshots:
		if existing.act_index == act_index:
			return
	var unit_ids: Array[StringName] = []
	for unit: UnitInstance in snapshot.roster.unit_instances:
		unit_ids.append(unit.def_id)
	var act_snapshot := BalanceBotActSnapshot.new(
		act_index, snapshot.economy.gold, snapshot.view.expedition_hp,
		snapshot.roster.unit_instances.size(),
		snapshot.roster.board.placements.size(), unit_ids
	)
	result.act_snapshots.append(act_snapshot)
	replay_parts.append(act_snapshot.canonical_token())


func _derive_build_id(roster: RosterState, run_id: StringName) -> StringName:
	var trait_counts: Dictionary = {}
	for unit: UnitInstance in roster.unit_instances:
		var rule := _content.battle_catalog.try_unit_rule(unit.def_id)
		if rule == null:
			continue
		for trait_id: StringName in rule.trait_ids:
			trait_counts[trait_id] = int(trait_counts.get(trait_id, 0)) + 1
	return build_id_from_trait_counts(trait_counts, run_id)


static func build_id_from_trait_counts(
	trait_counts: Dictionary, run_id: StringName
) -> StringName:
	var best_count := 0
	var candidates: Array[StringName] = []
	for key: Variant in trait_counts.keys():
		var trait_id := StringName(key)
		if not String(trait_id).begins_with("trait.faction_"):
			continue
		var count := int(trait_counts[key])
		if count < 2:
			continue
		if count > best_count:
			best_count = count
			candidates.clear()
			candidates.append(trait_id)
		elif count == best_count:
			candidates.append(trait_id)
	if candidates.is_empty():
		return &"build.none"
	var selected := candidates[0]
	var selected_digest := EconomyPayloadDigest.sha256([
		"BALANCE-BUILD-TIE-V1", String(run_id), String(selected),
	])
	for index: int in range(1, candidates.size()):
		var candidate := candidates[index]
		var digest := EconomyPayloadDigest.sha256([
			"BALANCE-BUILD-TIE-V1", String(run_id), String(candidate),
		])
		if digest < selected_digest:
			selected = candidate
			selected_digest = digest
	return StringName("build.trait.%s" % String(selected))


func _fail(result: BalanceBotCaseResult, code: StringName) -> BalanceBotCaseResult:
	if not result.failure_codes.has(code):
		result.failure_codes.append(code)
	if result.run_id.is_empty():
		result.run_id = &"invalid"
	if result.world_digest.length() != 64:
		result.world_digest = EconomyPayloadDigest.sha256([
			String(result.strategy_id), str(result.seed_index), String(code)
		])
	result.replay_digest = EconomyPayloadDigest.sha256([
		String(result.run_id), String(result.strategy_id), str(result.seed_index), String(code)
	])
	return result


func _trace(message: String) -> void:
	if trace_enabled:
		print("BALANCE_TRACE " + message)


func _trace_battle_validation(
	session: RunPresentationSession, node: MapNodeState
) -> void:
	if not trace_enabled or _active_battle_catalog == null \
		or node == null or node.encounter_preview == null:
		return
	var sources := BattleSetupSourceCompiler.new().compile(
		session.roster_state(), _active_battle_catalog, _active_battle_passives
	)
	var inputs := BattleSetupInputs.new()
	inputs.setup_schema_version = 2
	inputs.content_version = _content.content_version
	inputs.manifest_digest = StringName(_content.manifest_digest)
	inputs.encounter_snapshot = node.encounter_preview.deep_clone()
	for unit: UnitBattleSnapshot in sources.player_units:
		inputs.player_units.append(unit.deep_clone())
	for trait_snapshot: TraitBattleSnapshot in sources.player_active_traits:
		inputs.player_active_traits.append(trait_snapshot.deep_clone())
	for effect: BattleEffectSnapshot in sources.player_equipment_effects:
		inputs.player_equipment_effects.append(effect.deep_clone())
	for effect: BattleEffectSnapshot in sources.player_relic_effects:
		inputs.player_relic_effects.append(effect.deep_clone())
	for effect: BattleEffectSnapshot in sources.commander_effects:
		inputs.commander_effects.append(effect.deep_clone())
	var kind := &"boss" if node.node_kind == MapNodeState.NodeKind.BOSS else (
		&"elite" if node.node_kind == MapNodeState.NodeKind.ELITE else &"normal"
	)
	var built := BattleRulesSnapshotBuilder.new().build(
		_active_battle_catalog, inputs, node.act_index, kind
	)
	if not built.ok:
		_trace("prevalidate rules error=%s field=%s" % [
			String(built.error.code), String(built.error.field_path),
		])
		return
	inputs.battle_rules = built.snapshot
	var validation := BattleSetupInputsValidator.new().validate_for_build(inputs)
	if not validation.ok:
		_trace("prevalidate inputs error=%s field=%s source=%s" % [
			String(validation.error.code), String(validation.error.field_path),
			String(validation.error.source_id),
		])
		var validator := BattleSetupInputsValidator.new()
		for effect_rule: BattleEffectRuleSnapshot in inputs.battle_rules.effect_rules:
			if not validator._conditions_valid(effect_rule.conditions) \
				or not validator._operations_valid(effect_rule.battle_operations) \
				or not validator._run_operations_valid(effect_rule.run_operations):
				_trace("prevalidate invalid effect=%s conditions=%s battle_ops=%s run_ops=%s" % [
					String(effect_rule.effect_id),
					str(validator._conditions_valid(effect_rule.conditions)),
					str(validator._operations_valid(effect_rule.battle_operations)),
					str(validator._run_operations_valid(effect_rule.run_operations)),
				])
	else:
		_trace("prevalidate ok units=%d traits=%d equipment=%d relics=%d" % [
			inputs.player_units.size(), inputs.player_active_traits.size(),
			inputs.player_equipment_effects.size(), inputs.player_relic_effects.size(),
		])


func _trace_committed_battle_failure(controller: RunController) -> void:
	if not trace_enabled or controller == null:
		return
	var committed := controller.committed_combat_snapshot()
	var pending := committed.resolution_state as CombatPendingResolutionState \
		if committed != null else null
	if pending == null or pending.battle_setup == null:
		_trace("simulation diagnostic unavailable")
		return
	var simulation := BattleSimulation.new()
	var initialized := simulation.initialize(pending.battle_setup)
	if not initialized.ok:
		_trace("simulation initialize error=%s field=%s source=%s" % [
			String(initialized.error.code), String(initialized.error.field_path),
			String(initialized.error.source_code),
		])
		return
	var state := simulation.state_snapshot()
	for source: EffectSourceState in state.effect_sources:
		var rule := _effect_rule_for_diagnostic(
			pending.battle_setup.inputs.battle_rules, source.effect_id
		)
		if rule == null or rule.trigger != &"battle_start":
			continue
		_trace("battle_start effect=%s owner=%s" % [
			String(source.effect_id),
			String(source.source_instance_id.value) \
				if source.source_instance_id != null else "global",
		])
		for operation: BattleOperationRule in rule.battle_operations:
			_trace("battle_start operation effect=%s index=%d kind=%s stat=%s mode=%s amount=%d duration=%d target=%s" % [
				String(source.effect_id), operation.operation_index, String(operation.kind),
				String(operation.stat), String(operation.mode), operation.amount,
				operation.duration_ticks, String(operation.target),
			])
	for tick: int in range(RunPresentationSession.COMBAT_COMMIT_STEP_LIMIT):
		var stepped := simulation.step()
		if not stepped.ok:
			_trace("simulation step=%d error=%s field=%s source=%s" % [
				tick, String(stepped.error.code), String(stepped.error.field_path),
				String(stepped.error.source_code),
			])
			return
		if stepped.finished:
			_trace("simulation diagnostic unexpectedly finished")
			return
	_trace("simulation diagnostic reached step limit")


func _effect_rule_for_diagnostic(
	rules: BattleRulesSnapshot, effect_id: StringName
) -> BattleEffectRuleSnapshot:
	for rule: BattleEffectRuleSnapshot in rules.effect_rules:
		if rule.effect_id == effect_id:
			return rule
	return null
