class_name NodeChoiceServiceFixture
extends RefCounted

## specs/content-production/design.md §5（node choice transaction chain）的共用
## fixture：PREPARE 相位、codec3 content snapshot、current node 是一個真的 node key
## digest 的 run，加上一個兩選項的 NodeChoiceSetRule。
##
## 只提供「合法的起點」；每個測試自己把某一欄改壞來觀察具名拒絕碼。

static func outcome_token(outcome_kind: int) -> String:
	if outcome_kind == NodeChoiceRule.OUTCOME_OPEN_DISMANTLE_SERVICE:
		return "dismantle"
	if outcome_kind == NodeChoiceRule.OUTCOME_OPEN_REWARD_STAGE:
		return "reward"
	return "apply"


## PREPARE + IDLE + 已進入某個 treasure 節點的 run；shop offers／reservation owners／
## unit pool 由 ResolutionFixtureFactory 給成一致狀態，故離場路徑的
## try_release_shop_offers 會成功。
static func prepared_run() -> RunState:
	var run := ResolutionFixtureFactory.create_root(ResolutionState.Kind.IDLE).run
	var source := SaveRootFixture.create_receipt()
	var receipt := PinnedCatalogBuildReceipt.new(
		2,
		3,
		source.content_version,
		source.selection_digest,
		source.active_entry_ids,
		source.economy_config_id,
		source.combat_config_id,
		source.reward_table_ids,
		source.map_node_def_ids,
		source.challenge_unlock_def_ids,
		source.meta_reward_table_id,
		source.manifest_digest
	)
	var built := ContentSnapshotState.from_pinned_receipt(receipt)
	assert(built.ok, "codec3 content snapshot must build")
	run.content_snapshot = built.snapshot
	run.run_phase = RunState.RunPhase.PREPARE
	var old := run.map_state.nodes[0]
	var node_key_result := RuntimeKeySchemaRegistry.new().build_node(
		StringName(run.run_id), old.act_index, &"treasure",
		old.layer_index, old.slot_index
	)
	assert(node_key_result.ok, "node key must build")
	var node_key := node_key_result.key_state as NodeKeyState
	var nodes: Array[MapNodeState] = [MapNodeState.new(
		String(node_key.digest),
		node_key,
		&"mapnode.fixture",
		old.act_index,
		old.layer_index,
		old.slot_index,
		MapNodeState.NodeKind.TREASURE,
		old.generated_payload_digest,
		null,
		false
	)]
	run.map_state.nodes = nodes
	run.current_node_id = OptionalStringValue.new(String(node_key.digest))
	run.map_state.current_node_id = OptionalStringValue.new(String(node_key.digest))
	return run


static func catalog_for(run: RunState) -> EconomyExpeditionCatalog:
	return EconomyTestFixture.settlement_catalog(
		run.content_snapshot.manifest_digest_value()
	)


static func current_node_id(run: RunState) -> StringName:
	return StringName(run.current_node_id.value)


## 兩個選項：index 0 是傳入的 outcome，index 1 永遠是 APPLY_AND_COMPLETE
## （pending 要求至少兩個 choice）。
static func choice_set(
	outcome_kind: int = NodeChoiceRule.OUTCOME_APPLY_AND_COMPLETE
) -> NodeChoiceSetRule:
	var choices: Array[NodeChoiceRule] = [
		choice(
			StringName("choice.fixture.%s" % outcome_token(outcome_kind)),
			outcome_kind
		),
		choice(&"choice.fixture.plain", NodeChoiceRule.OUTCOME_APPLY_AND_COMPLETE),
	]
	return NodeChoiceSetRule.new(
		&"choice_set.fixture",
		&"loc.choice_set_fixture",
		&"treasure",
		choices
	)


static func choice(choice_id: StringName, outcome_kind: int) -> NodeChoiceRule:
	var operations: Array[NodeChoiceOperationRule] = []
	if outcome_kind == NodeChoiceRule.OUTCOME_APPLY_AND_COMPLETE:
		operations.append(NodeChoiceOperationRule.new(
			NodeChoiceOperationRule.Kind.ADD_GOLD, 1, 0, &"once_per_node"
		))
	# EconomyTestFixture.settlement_catalog 的 standard reward table id。
	var reward_table_ref: StringName = (
		&"reward.standard"
		if outcome_kind == NodeChoiceRule.OUTCOME_OPEN_REWARD_STAGE
		else &""
	)
	return NodeChoiceRule.new(
		choice_id,
		0,
		&"loc.choice_title",
		&"loc.choice_description",
		&"loc.choice_preview",
		&"loc.choice_result",
		operations,
		reward_table_ref,
		not reward_table_ref.is_empty(),
		outcome_kind,
		true
	)


## begin() 成功後的 run（含 pending resolution 與已推進的 rng stream）。
static func begun_run(
	run: RunState,
	set_rule: NodeChoiceSetRule,
	catalog: EconomyExpeditionCatalog
) -> RunState:
	var result := CommitNodeChoiceService.new().begin(
		run, current_node_id(run), set_rule, catalog
	)
	assert(result.ok, "fixture begin() must succeed")
	return result.run_state


static func pending_of(run: RunState) -> NodeChoicePendingState:
	return run.resolution_state as NodeChoicePendingState


static func payload_for(
	run: RunState, choice_id: StringName
) -> NodeChoiceCommitPayload:
	return NodeChoiceCommitPayload.from_pending(
		run.run_id, pending_of(run), choice_id
	)


static func error_code(result: ExpeditionActionResult) -> String:
	return String(result.error.code) if result.error != null else ""


static func command_error_code(result: CommandApplyResult) -> String:
	if result.error == null:
		return ""
	for diagnostic: DiagnosticValue in result.error.diagnostic_values:
		if diagnostic.key == &"source_code" and diagnostic.string_value != null:
			return diagnostic.string_value.value
	return ""
