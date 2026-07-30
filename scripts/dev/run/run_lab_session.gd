class_name RunLabSession
extends RefCounted

## Development-only convenience API. Every mutation is translated into a
## RunPresentationIntent and consumed by the same production facade as a real
## screen. This wrapper owns no command construction or canonical rules.

const COMBAT_STEP_LIMIT: int = 100000
const REWARD_STEP_LIMIT: int = 32

const ERROR_NO_SESSION: StringName = &"RUN_LAB_SESSION_MISSING"
const ERROR_NO_REACHABLE_NODE: StringName = &"RUN_LAB_NO_REACHABLE_NODE"
const ERROR_NO_SHOP_OFFER: StringName = &"RUN_LAB_NO_SHOP_OFFER"
const ERROR_NO_PENDING_REWARD: StringName = &"RUN_LAB_NO_PENDING_REWARD"
const ERROR_REWARD_STEP_LIMIT: StringName = &"RUN_LAB_REWARD_STEP_LIMIT"
const ERROR_ITEM_REWARD_UNSUPPORTED: StringName = &"RUN_LAB_ITEM_REWARD_UNSUPPORTED"

var _session: RunPresentationSession


## The Variant form keeps the pre-G2 dev composition call compatible while
## moving construction semantics into RunPresentationSession.
func _init(
	p_source: Variant = null,
	p_factory_source: Variant = null,
	p_economy_source: Variant = null,
	p_battle_source: Variant = null,
	p_commander_passive_effect_ids: Array[StringName] = []
) -> void:
	if p_source is RunPresentationSession:
		_session = p_source
	else:
		_session = RunPresentationSession.new(
			p_source,
			p_factory_source,
			p_battle_source,
			p_commander_passive_effect_ids
		)


func is_concrete() -> bool:
	return _session != null and _session.is_concrete()


func view() -> RunViewState:
	return _session.view_state() if _session != null else null


func map() -> MapState:
	return _session.map_state() if _session != null else null


func economy() -> EconomyState:
	return _session.economy_state() if _session != null else null


func reachable_node_ids() -> Array[String]:
	var result: Array[String] = []
	var map_state := map()
	if map_state == null:
		return result
	for node: MapNodeState in map_state.nodes:
		if node.completed or map_state.completed_node_ids.has(node.node_id):
			continue
		if map_state.completed_node_ids.is_empty():
			if node.act_index == 1 and node.layer_index == 0:
				result.append(node.node_id)
			continue
		for completed_id: String in map_state.completed_node_ids:
			for edge: MapEdgeState in map_state.edges:
				if edge.from_node_id == completed_id and edge.to_node_id == node.node_id:
					result.append(node.node_id)
					break
			if result.has(node.node_id):
				break
	return result


func try_node(node_id: String) -> MapNodeState:
	var map_state := map()
	if map_state == null:
		return null
	for node: MapNodeState in map_state.nodes:
		if node.node_id == node_id:
			return node
	return null


func current_node() -> MapNodeState:
	var current_view := view()
	if current_view == null or current_view.current_node_id == null:
		return null
	return try_node(current_view.current_node_id.value)


func generate_map() -> StringName:
	return _dispatch(RunPresentationIntent.Kind.GENERATE_MAP)


func enter_node(node_id: String) -> StringName:
	var intent := RunPresentationIntent.new(RunPresentationIntent.Kind.ENTER_NODE)
	intent.target_node_id = node_id
	return _dispatch_intent(intent)


func enter_first_reachable_node() -> StringName:
	var reachable := reachable_node_ids()
	return ERROR_NO_REACHABLE_NODE if reachable.is_empty() else enter_node(reachable[0])


func resolve_non_combat_node() -> StringName:
	return _dispatch(RunPresentationIntent.Kind.RESOLVE_NON_COMBAT)


func refresh_shop() -> StringName:
	return _dispatch(RunPresentationIntent.Kind.REFRESH_SHOP)


func buy_first_offer() -> StringName:
	var economy_state := economy()
	if economy_state == null or economy_state.shop_offers.is_empty():
		return ERROR_NO_SHOP_OFFER
	var intent := RunPresentationIntent.new(RunPresentationIntent.Kind.BUY_UNIT)
	intent.offer_id = economy_state.shop_offers[0].offer_id
	return _dispatch_intent(intent)


func commit_board() -> StringName:
	if not is_concrete():
		return ERROR_NO_SESSION
	var current_view := view()
	var roster := _session.roster_state()
	var ordered_instance_ids: Array[String] = []
	var seen: Dictionary = {}
	var placements_source: Array[BoardPlacementState] = roster.board.placements.duplicate()
	placements_source.sort_custom(
		func(left: BoardPlacementState, right: BoardPlacementState) -> bool:
			if left.logical_y != right.logical_y:
				return left.logical_y < right.logical_y
			if left.logical_x != right.logical_x:
				return left.logical_x < right.logical_x
			return left.unit_instance_id < right.unit_instance_id
	)
	for placement: BoardPlacementState in placements_source:
		if not seen.has(placement.unit_instance_id):
			seen[placement.unit_instance_id] = true
			ordered_instance_ids.append(placement.unit_instance_id)
	for instance_id: String in roster.bench_unit_instance_ids:
		if not seen.has(instance_id):
			seen[instance_id] = true
			ordered_instance_ids.append(instance_id)
	var deployable := mini(ordered_instance_ids.size(), maxi(0, current_view.economy.level))
	var placements: Array[BoardPlacementState] = []
	var bench: Array[String] = []
	for index: int in range(ordered_instance_ids.size()):
		var instance_id := ordered_instance_ids[index]
		if index < deployable:
			@warning_ignore("integer_division")
			var row: int = index / BoardPreparationValidator.BOARD_WIDTH
			placements.append(BoardPlacementState.new(
				row, index % BoardPreparationValidator.BOARD_WIDTH, instance_id
			))
		else:
			bench.append(instance_id)
	var intent := RunPresentationIntent.new(
		RunPresentationIntent.Kind.COMMIT_BOARD_LAYOUT
	)
	intent.board = BoardState.new(placements)
	intent.bench_unit_instance_ids.assign(bench)
	return _dispatch_intent(intent)


func start_combat() -> StringName:
	var error := _dispatch(RunPresentationIntent.Kind.START_OR_RESUME_COMBAT)
	if not error.is_empty():
		return error
	return _session.drive_current_combat_to_commit(COMBAT_STEP_LIMIT)


func settle_battle() -> StringName:
	return _dispatch(RunPresentationIntent.Kind.SETTLE_BATTLE)


func abandon_boss_retry() -> StringName:
	return _dispatch(RunPresentationIntent.Kind.ABANDON_BOSS_RETRY)


func resolve_rewards() -> StringName:
	if not is_concrete() or view().run_phase != RunState.RunPhase.REWARD:
		return ERROR_NO_PENDING_REWARD
	for _step: int in range(REWARD_STEP_LIMIT):
		var pending := _session.pending_reward_state()
		if pending == null:
			return ERROR_NO_PENDING_REWARD
		var error := _resolve_reward_step(pending)
		if not error.is_empty():
			return error
		if view().run_phase != RunState.RunPhase.REWARD:
			return &""
	return ERROR_REWARD_STEP_LIMIT


func _resolve_reward_step(pending: PendingRewardState) -> StringName:
	var intent: RunPresentationIntent
	match pending.phase:
		PendingRewardState.Phase.CHOOSING:
			if pending.offers.is_empty():
				return ERROR_NO_PENDING_REWARD
			intent = RunPresentationIntent.new(
				RunPresentationIntent.Kind.CHOOSE_STANDARD_REWARD
			)
			intent.choice_id = pending.offers[0].choice_id
		PendingRewardState.Phase.UNIT_RESOLUTION:
			intent = RunPresentationIntent.new(
				RunPresentationIntent.Kind.RESOLVE_UNIT_REWARD
			)
			intent.accept = true
		PendingRewardState.Phase.ITEM_RESOLUTION:
			var roster := _session.roster_state()
			if roster.pending_item_overflow.is_empty():
				return ERROR_ITEM_REWARD_UNSUPPORTED
			intent = RunPresentationIntent.new(
				RunPresentationIntent.Kind.RESOLVE_ITEM_REWARD
			)
			intent.item_instance_id = roster.pending_item_overflow[0]
		PendingRewardState.Phase.RELIC_RESOLUTION:
			intent = RunPresentationIntent.new(
				RunPresentationIntent.Kind.RESOLVE_RELIC_REWARD
			)
			intent.relic_slot_index = 0
		_:
			intent = RunPresentationIntent.new(
				RunPresentationIntent.Kind.ADVANCE_REWARD
			)
	return _dispatch_intent(intent)


func _dispatch(kind: RunPresentationIntent.Kind) -> StringName:
	return _dispatch_intent(RunPresentationIntent.new(kind))


func _dispatch_intent(intent: RunPresentationIntent) -> StringName:
	if _session == null:
		return ERROR_NO_SESSION
	var result := _session.dispatch(intent)
	return &"" if result.ok else result.error.source_code
