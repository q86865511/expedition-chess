class_name NodeEntryService
extends RefCounted

var _income_service: IncomeService
var _shop_service: ShopService

func _init(p_income_service: IncomeService = null, p_shop_service: ShopService = null) -> void:
	_income_service = p_income_service if p_income_service != null else IncomeService.new()
	_shop_service = p_shop_service if p_shop_service != null else ShopService.new()

func enter(
	run: RunState,
	target_node_id: String,
	catalog: EconomyExpeditionCatalog,
	battle_catalog: BattleRuleCatalog = null,
	relic_table: RunRelicTable = null
) -> NodeEntryResult:
	if run == null or target_node_id.is_empty() or catalog == null or run.map_state == null:
		return NodeEntryResult.failure(NodeEntryError.INPUT_INVALID, &"request")
	if run.content_snapshot == null or catalog.manifest_digest_value() != run.content_snapshot.manifest_digest_value():
		return NodeEntryResult.failure(NodeEntryError.GENERATION_MISMATCH, &"content_snapshot.manifest_digest")
	if run.run_phase != RunState.RunPhase.MAP:
		return NodeEntryResult.failure(NodeEntryError.PHASE_INVALID, &"run_phase")
	if run.resolution_state == null or run.resolution_state.kind != ResolutionState.Kind.IDLE:
		return NodeEntryResult.failure(NodeEntryError.RESOLUTION_INVALID, &"resolution_state")
	var draft := run.deep_clone()
	var node := _find_node(draft.map_state.nodes, target_node_id)
	if node == null:
		return NodeEntryResult.failure(NodeEntryError.NODE_MISSING, &"target_node_id")
	if node.completed or draft.map_state.completed_node_ids.has(target_node_id):
		return NodeEntryResult.failure(NodeEntryError.NODE_COMPLETED, &"target_node_id")
	if not _reachable(draft, node):
		return NodeEntryResult.failure(NodeEntryError.NODE_UNREACHABLE, &"target_node_id")
	if not draft.economy_state.shop_offers.is_empty():
		return NodeEntryResult.failure(NodeEntryError.SHOP_LEAK, &"economy_state.shop_offers")
	draft.current_node_id = OptionalStringValue.new(target_node_id)
	draft.map_state.current_node_id = OptionalStringValue.new(target_node_id)
	draft.act_index = node.act_index
	if node.node_kind in [
		MapNodeState.NodeKind.NORMAL,
		MapNodeState.NodeKind.ELITE,
		MapNodeState.NodeKind.BOSS,
	]:
		if battle_catalog == null \
			or battle_catalog.manifest_digest_value() != catalog.manifest_digest_value():
			return NodeEntryResult.failure(
				NodeEntryError.ENCOUNTER_CATALOG_MISSING, &"battle_catalog"
			)
		var node_rule := catalog.try_map_node(node.def_id)
		if node_rule == null or node_rule.generator_id.is_empty():
			return NodeEntryResult.failure(
				NodeEntryError.ENCOUNTER_COMPILE_FAILED,
				&"map_node.generator_id"
			)
		var compile_request := EncounterCompileRequest.new()
		compile_request.manifest_digest = catalog.manifest_digest_value()
		compile_request.encounter_id = node_rule.generator_id
		compile_request.node_id = StringName(node.node_id)
		compile_request.act_index = node.act_index
		compile_request.depth = node.layer_index
		compile_request.challenge_level = draft.challenge_level
		var compiled := EncounterCompiler.new().compile(
			compile_request, battle_catalog
		)
		if not compiled.ok:
			return NodeEntryResult.failure(
				NodeEntryError.ENCOUNTER_COMPILE_FAILED,
				compiled.error.field_path
			)
		node.encounter_preview = compiled.preview.deep_clone()
	# 路線／經濟遺物的作用中槽位（依 slot_index 升序）由 draft roster 推導，餵給 income／shop。
	var active_relic_ids := RunRelicActivation.active_ids_in_slot_order(
		draft.roster_state.active_relic_slots
	)
	if not draft.income_claimed_node_ids.has(target_node_id):
		var income := _income_service.quote(IncomeQuoteRequest.new(
			StringName(draft.run_id), StringName(target_node_id), node.layer_index,
			draft.economy_state, draft.next_transaction_serial, catalog,
			relic_table, active_relic_ids
		))
		if not income.ok:
			return NodeEntryResult.failure(income.error.code, income.error.field_path)
		draft.economy_state = income.transaction.economy_state.deep_clone()
		draft.next_transaction_serial = income.transaction.next_transaction_serial.deep_clone()
		draft.transaction_receipts.append(income.transaction.receipt.deep_clone())
		draft.income_claimed_node_ids.append(target_node_id)
		draft.income_claimed_node_ids.sort()
	var shop_rng := EconomyCommandSupport.try_shop_rng(draft)
	if shop_rng == null:
		var derived := RngService.new().derive_stream(
			draft.run_seed, &"shop", StringName("%s:shop_v1" % draft.run_id)
		)
		if not derived.ok:
			return NodeEntryResult.failure(derived.error.code, derived.error.field_path)
		shop_rng = derived.snapshot
	var shop := _shop_service.generate_offers(GenerateOffersRequest.new(
		StringName(draft.run_id), StringName(target_node_id), draft.economy_state,
		draft.unit_pool_state, draft.roster_state, draft.reservation_owners,
		shop_rng, draft.next_transaction_serial, draft.next_unit_serial, catalog,
		relic_table, active_relic_ids
	))
	if not shop.ok:
		return NodeEntryResult.failure(shop.error.code, shop.error.field_path)
	EconomyCommandSupport.apply_shop_transaction(draft, shop.transaction)
	draft.transaction_receipts.sort_custom(func(left: TransactionReceiptState, right: TransactionReceiptState) -> bool:
		return String(left.key.digest) < String(right.key.digest)
	)
	return NodeEntryResult.success(draft)

func _find_node(nodes: Array[MapNodeState], node_id: String) -> MapNodeState:
	for node: MapNodeState in nodes:
		if node.node_id == node_id:
			return node
	return null

func _reachable(run: RunState, target: MapNodeState) -> bool:
	if run.map_state.completed_node_ids.is_empty():
		return target.act_index == 1 and target.layer_index == 0
	for completed_id: String in run.map_state.completed_node_ids:
		for edge: MapEdgeState in run.map_state.edges:
			if edge.from_node_id == completed_id and edge.to_node_id == target.node_id:
				return true
	return false
