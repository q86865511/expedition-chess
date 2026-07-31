extends GutTest

## T25 review H1／H2 回歸：OPEN_DISMANTLE_SERVICE 出口必須是可離開的。
## design.md §5:208-214：
## - DismantleWithNodeServiceCommand 不要求／不消耗 consumable，服務期間不限次數，
##   每次都留下唯一 transaction receipt，且**不完成節點**。
## - ExitNodeServiceCommand 是唯一完成節點的命令，並且和其他離場路徑一樣要釋放
##   本節點的 shop offers（否則下一次 EnterNodeEvent 被 NODE_ENTRY_SHOP_LEAK 擋死）。

const UNIT_ID: String = "u_0000000000000001"
const EQUIPMENT_A: String = "it_0000000000000001"
const EQUIPMENT_B: String = "it_0000000000000002"


func test_service_dismantle_needs_no_consumable_and_repeats_without_completing_node() -> void:
	var run := _run_in_dismantle_service()
	var pending := run.resolution_state as NodeServicePendingResolutionState
	# 命令直接在傳入的 draft 上動手（RunController 傳的是複本），故基準值先抄下來。
	var base_receipt_count := run.transaction_receipts.size()
	var base_serial := run.next_transaction_serial.deep_clone()
	var first := _service_dismantle(run, pending, EQUIPMENT_A)
	assert_true(first.ok, NodeChoiceServiceFixture.command_error_code(first))
	if not first.ok:
		return
	var after_first := first.draft
	assert_null(_item(after_first, EQUIPMENT_A).bound_unit_instance_id)
	assert_true(
		after_first.roster_state.inventory_item_instance_ids.has(EQUIPMENT_A)
	)
	# 服務期間不限次數：resolution／phase／節點完成狀態都不得被第一次拆解改掉。
	assert_true(
		after_first.resolution_state is NodeServicePendingResolutionState
	)
	assert_eq(after_first.run_phase, RunState.RunPhase.PREPARE)
	assert_false(after_first.map_state.nodes[0].completed)
	var second := _service_dismantle(after_first, pending, EQUIPMENT_B)
	assert_true(second.ok, NodeChoiceServiceFixture.command_error_code(second))
	if not second.ok:
		return
	assert_null(_item(second.draft, EQUIPMENT_B).bound_unit_instance_id)
	assert_true(
		second.draft.resolution_state is NodeServicePendingResolutionState
	)
	# 每次拆解都有唯一 transaction receipt（serial 遞增 → key digest 不同）。
	assert_eq(
		second.draft.transaction_receipts.size(), base_receipt_count + 2
	)
	assert_eq(
		second.draft.next_transaction_serial.to_hex(),
		base_serial.add(U64Bits.one()).add(U64Bits.one()).to_hex()
	)


func test_exit_releases_shop_offers_completes_node_and_returns_to_map() -> void:
	var run := _run_in_dismantle_service()
	var pending := run.resolution_state as NodeServicePendingResolutionState
	assert_false(
		run.economy_state.shop_offers.is_empty(),
		"fixture must carry live offers, otherwise the leak guard is untested"
	)
	var exited := ExitNodeServiceCommand.new(
		run.run_id, pending.node_id, pending.choice_receipt_digest
	).apply_to(run)
	assert_true(exited.ok, NodeChoiceServiceFixture.command_error_code(exited))
	if not exited.ok:
		return
	# H1：下一個節點的 NodeEntryService.enter 要求 shop_offers 為空。
	assert_true(exited.draft.economy_state.shop_offers.is_empty())
	for owner: ReservationOwnerState in exited.draft.reservation_owners:
		assert_eq(owner.status, ReservationOwnerState.Status.RELEASED)
	assert_true(exited.draft.map_state.nodes[0].completed)
	assert_true(
		exited.draft.map_state.completed_node_ids.has(
			exited.draft.map_state.nodes[0].node_id
		)
	)
	assert_true(exited.draft.resolution_state is IdleResolutionState)
	assert_eq(exited.draft.run_phase, RunState.RunPhase.MAP)
	# ack 仍是另一筆交易的事（design :201-203）。
	assert_false(exited.draft.node_choice_receipts[0].result_acknowledged)


func test_exit_is_reachable_with_no_bound_equipment_and_no_consumable() -> void:
	var run := _run_in_dismantle_service()
	var pending := run.resolution_state as NodeServicePendingResolutionState
	var unit := _unit(run)
	unit.equipment_instance_ids.clear()
	for item: ItemInstanceState in run.roster_state.item_instances:
		item.bound_unit_instance_id = null
	# 沒有可拆的裝備、也沒有耗材時，拆解命令一律被拒——出口不能因此消失。
	var rejected := _service_dismantle(run, pending, EQUIPMENT_A)
	assert_false(rejected.ok)
	assert_eq(
		NodeChoiceServiceFixture.command_error_code(rejected),
		"DISMANTLE_NODE_SERVICE_TARGET_NOT_BOUND"
	)
	var exited := ExitNodeServiceCommand.new(
		run.run_id, pending.node_id, pending.choice_receipt_digest
	).apply_to(run)
	assert_true(exited.ok, NodeChoiceServiceFixture.command_error_code(exited))
	if not exited.ok:
		return
	assert_eq(exited.draft.run_phase, RunState.RunPhase.MAP)


func test_service_commands_require_matching_service_authority() -> void:
	var run := _run_in_dismantle_service()
	var pending := run.resolution_state as NodeServicePendingResolutionState
	var foreign_node := StringName("node_%s" % "b".repeat(64))
	var cases: Array[Array] = [
		[
			ExitNodeServiceCommand.new(
				"run_deadbeef", pending.node_id, pending.choice_receipt_digest
			),
			"EXIT_NODE_SERVICE_RUN_MISMATCH",
		],
		[
			ExitNodeServiceCommand.new(
				run.run_id, foreign_node, pending.choice_receipt_digest
			),
			"EXIT_NODE_SERVICE_NODE_MISMATCH",
		],
		[
			ExitNodeServiceCommand.new(
				run.run_id, pending.node_id, "c".repeat(64)
			),
			"EXIT_NODE_SERVICE_RECEIPT_MISMATCH",
		],
		[
			DismantleWithNodeServiceCommand.new(
				run.run_id, foreign_node, pending.choice_receipt_digest,
				EQUIPMENT_A
			),
			"DISMANTLE_NODE_SERVICE_NODE_MISMATCH",
		],
	]
	for entry: Array in cases:
		var command: RunCommand = entry[0]
		var result := command.apply_to(run)
		assert_false(result.ok)
		assert_eq(
			NodeChoiceServiceFixture.command_error_code(result), String(entry[1])
		)
	# IDLE 下服務命令沒有 authority。
	var idle := run.deep_clone()
	idle.resolution_state = IdleResolutionState.new()
	var without_service := ExitNodeServiceCommand.new(
		idle.run_id, pending.node_id, pending.choice_receipt_digest
	).apply_to(idle)
	assert_false(without_service.ok)
	assert_eq(
		NodeChoiceServiceFixture.command_error_code(without_service),
		"EXIT_NODE_SERVICE_RESOLUTION_INVALID"
	)


func test_general_dismantle_command_no_longer_completes_the_node() -> void:
	var run := _run_in_dismantle_service()
	var consumable_id := "it_0000000000000003"
	run.roster_state.item_instances.append(ItemInstanceState.new(
		consumable_id, &"consumable.dismantle_kit", null,
		U64Bits.from_u32(0, 3).value
	))
	run.roster_state.inventory_item_instance_ids.append(consumable_id)
	var result := DismantleEquipmentCommand.new(
		EQUIPMENT_A, consumable_id, EquipDismantleTestFixture.consumable_rules(
			run.content_snapshot.manifest_digest_value()
		)
	).apply_to(run)
	assert_true(result.ok, NodeChoiceServiceFixture.command_error_code(result))
	if not result.ok:
		return
	# design :213「只有 ExitNodeServiceCommand 完成節點」：耗材版拆解在服務期間
	# 仍可用，但不得自己完成節點、也不得偷偷 ack 或釋放 resolution。
	assert_true(result.draft.resolution_state is NodeServicePendingResolutionState)
	assert_eq(result.draft.run_phase, RunState.RunPhase.PREPARE)
	assert_false(result.draft.map_state.nodes[0].completed)
	assert_false(result.draft.node_choice_receipts[0].result_acknowledged)
	assert_false(result.draft.economy_state.shop_offers.is_empty())


## OPEN_DISMANTLE_SERVICE 的正式產生路徑：commit 一個 dismantle 選項，
## 再補上兩件已綁定裝備。
func _run_in_dismantle_service() -> RunState:
	var run := NodeChoiceServiceFixture.prepared_run()
	var catalog := NodeChoiceServiceFixture.catalog_for(run)
	var rule := NodeChoiceServiceFixture.choice_set(
		NodeChoiceRule.OUTCOME_OPEN_DISMANTLE_SERVICE
	)
	var begun := NodeChoiceServiceFixture.begun_run(run, rule, catalog)
	var committed := CommitNodeChoiceService.new().commit(
		begun,
		NodeChoiceServiceFixture.payload_for(begun, &"choice.fixture.dismantle"),
		rule,
		catalog
	)
	assert_true(
		committed.ok, NodeChoiceServiceFixture.error_code(committed)
	)
	var draft := committed.run_state
	assert_true(draft.resolution_state is NodeServicePendingResolutionState)
	var equipment: Array[String] = [EQUIPMENT_A, EQUIPMENT_B]
	var units: Array[UnitInstance] = [
		UnitInstance.new(UNIT_ID, &"unit.fixture", 1, equipment, U64Bits.one())
	]
	draft.roster_state.unit_instances = units
	draft.roster_state.bench_unit_instance_ids = [UNIT_ID]
	var items: Array[ItemInstanceState] = [
		ItemInstanceState.new(
			EQUIPMENT_A, &"equipment.plain_a",
			OptionalStringValue.new(UNIT_ID), U64Bits.one()
		),
		ItemInstanceState.new(
			EQUIPMENT_B, &"equipment.plain_b",
			OptionalStringValue.new(UNIT_ID), U64Bits.from_u32(0, 2).value
		),
	]
	draft.roster_state.item_instances = items
	return draft


func _service_dismantle(
	run: RunState,
	pending: NodeServicePendingResolutionState,
	item_instance_id: String
) -> CommandApplyResult:
	return DismantleWithNodeServiceCommand.new(
		run.run_id,
		pending.node_id,
		pending.choice_receipt_digest,
		item_instance_id
	).apply_to(run)


func _unit(run: RunState) -> UnitInstance:
	for unit: UnitInstance in run.roster_state.unit_instances:
		if unit.instance_id == UNIT_ID:
			return unit
	return null


func _item(run: RunState, item_instance_id: String) -> ItemInstanceState:
	for item: ItemInstanceState in run.roster_state.item_instances:
		if item.instance_id == item_instance_id:
			return item
	return null
