class_name CommitNodeChoiceService
extends RefCounted

const OUTCOME_APPLY_AND_COMPLETE := 1
const OUTCOME_OPEN_DISMANTLE_SERVICE := 2
const OUTCOME_OPEN_REWARD_STAGE := 3

## design.md §5（:161-165）要求 lifecycle_nonce 是 pending 生命週期的唯一性來源，
## 因此不能是 (run, node, 世代) 的純函數——cancel→re-begin 必須換一組 nonce／
## pending_digest。專案規約要求決定性亂數一律走 RngService 的具名 stream，這裡取
## `map`：它是 run 層唯一與「節點走訪」同語意的 stream，而且 MapService 每次生成都
## 自行 derive_stream（map_service.gd:15-17），從不讀持久化的 MAP snapshot，
## 故在此消耗 entropy 不會改動任何既有地圖／商店／獎勵抽樣的決定性。
const LIFECYCLE_NONCE_STREAM := NamedRngState.StreamName.MAP
const LIFECYCLE_NONCE_CONTEXT_SUFFIX: String = ":node_choice_v1"
## nonce 必須非零（node_choice_pending_state.gd:47-49）；PCG 抽到全零的機率是 2^-64，
## 但錯誤路徑要有出口而不是讓整個 EnterNodeEvent 被拒（review M4 末段）。
const NONCE_DRAW_ATTEMPTS: int = 4


func begin(
	source: RunState,
	node_id: StringName,
	choice_set: NodeChoiceSetRule,
	catalog: EconomyExpeditionCatalog
) -> ExpeditionActionResult:
	if (
		source == null
		or source.content_snapshot == null
		or choice_set == null
		or choice_set.choices.size() < 2
	):
		return _failure(ExpeditionActionError.INPUT_INVALID, &"choice_set")
	var generation_error := _validate_generation(source, catalog)
	if generation_error != null:
		return ExpeditionActionResult.failure(
			generation_error.code, generation_error.field_path
		)
	if (
		source.run_phase != RunState.RunPhase.PREPARE
		or not source.resolution_state is IdleResolutionState
	):
		return _failure(ExpeditionActionError.PHASE_INVALID, &"resolution_state")
	var choice_ids: Array[StringName] = []
	for choice: NodeChoiceRule in choice_set.choices:
		if choice == null or choice.choice_id.is_empty() or choice_ids.has(choice.choice_id):
			return _failure(ExpeditionActionError.INPUT_INVALID, &"choice_set.choices")
		choice_ids.append(choice.choice_id)
	var draft := source.deep_clone()
	var lifecycle_nonce := _draw_lifecycle_nonce(draft)
	if lifecycle_nonce.is_empty():
		return _failure(ExpeditionActionError.RNG_FAILED, &"lifecycle_nonce")
	draft.resolution_state = NodeChoicePendingState.new(
		node_id,
		choice_set.choice_set_id,
		choice_ids,
		draft.content_snapshot.content_version_value(),
		draft.content_snapshot.catalog_schema_version_value(),
		draft.content_snapshot.content_codec_version_value(),
		draft.content_snapshot.manifest_digest_value(),
		lifecycle_nonce
	)
	var pending := draft.resolution_state as NodeChoicePendingState
	if not pending.is_valid():
		return _failure(
			ExpeditionActionError.INPUT_INVALID,
			_pending_invalid_field_path(pending)
		)
	return ExpeditionActionResult.success(draft)


func cancel(source: RunState) -> ExpeditionActionResult:
	if source == null or not source.resolution_state is NodeChoicePendingState:
		return _failure(ExpeditionActionError.RESOLUTION_INVALID, &"resolution_state")
	var pending := source.resolution_state as NodeChoicePendingState
	if not pending.is_valid():
		return _failure(ExpeditionActionError.RESOLUTION_INVALID, &"pending_digest")
	var draft := source.deep_clone()
	draft.resolution_state = IdleResolutionState.new()
	return ExpeditionActionResult.success(draft)


## design.md §5（:173-186）：payload 是玩家在 overlay 上看到的那一份 pending 的
## 完整複本，每一欄都對 canonical pending 逐一比對並回具名 rejection code。
## ALREADY_COMMITTED 必須排在 resolution 檢查之前——commit 成功後 pending 已被換掉，
## 若先驗 resolution，repeat confirm 拿到的會是 RESOLUTION_INVALID 而不是
## design :204-205 要求的 ALREADY_COMMITTED。
func commit(
	source: RunState,
	payload: NodeChoiceCommitPayload,
	choice_set: NodeChoiceSetRule,
	catalog: EconomyExpeditionCatalog
) -> ExpeditionActionResult:
	if (
		source == null
		or choice_set == null
		or payload == null
		or not payload.is_concrete()
	):
		return _failure(ExpeditionActionError.INPUT_INVALID, &"payload")
	if payload.expected_run_id != source.run_id:
		return _failure(NodeChoiceRejection.RUN_MISMATCH, &"expected_run_id")
	if _has_committed_receipt(source, payload.node_id, payload.pending_digest):
		return _failure(NodeChoiceRejection.ALREADY_COMMITTED, &"pending_digest")
	if not source.resolution_state is NodeChoicePendingState:
		return _failure(ExpeditionActionError.RESOLUTION_INVALID, &"resolution_state")
	var pending := source.resolution_state as NodeChoicePendingState
	if not pending.is_valid():
		return _failure(ExpeditionActionError.RESOLUTION_INVALID, &"pending_digest")
	var generation_error := _validate_generation(source, catalog)
	if generation_error != null:
		return ExpeditionActionResult.failure(
			generation_error.code, generation_error.field_path
		)
	var rejection := _reject_payload(payload, pending, choice_set)
	if rejection != null:
		return ExpeditionActionResult.failure(
			rejection.code, rejection.field_path
		)
	var selected := _find_choice(choice_set, payload.choice_id)
	if selected == null:
		return _failure(NodeChoiceRejection.CHOICE_UNKNOWN, &"choice_id")
	var draft := source.deep_clone()
	var operation_error := _apply_operations(draft, selected.operations)
	if operation_error != null:
		return ExpeditionActionResult.failure(
			operation_error.code, operation_error.field_path
		)
	if draft.next_transaction_serial.equals(U64Bits.max_value()):
		return _failure(
			ExpeditionActionError.SERIAL_EXHAUSTED, &"next_transaction_serial"
		)
	var serial_bits := draft.next_transaction_serial.deep_clone()
	var serial := serial_bits.to_hex()
	var built_key := RuntimeKeySchemaRegistry.new().build_transaction(
		StringName(draft.run_id),
		pending.node_id,
		&"commit_node_choice",
		serial_bits
	)
	if not built_key.ok:
		return _failure(
			ExpeditionActionError.KEY_FAILED, &"transaction_digest"
		)
	var transaction_digest := String(built_key.key_state.digest)
	var receipt := NodeChoiceCommitReceiptState.new()
	receipt.run_id = StringName(draft.run_id)
	receipt.node_id = pending.node_id
	receipt.choice_set_id = pending.choice_set_id
	receipt.choice_id = payload.choice_id
	receipt.pending_digest = pending.pending_digest
	receipt.lifecycle_nonce = pending.lifecycle_nonce
	receipt.transaction_serial = serial
	receipt.transaction_digest = transaction_digest
	receipt.result_key = selected.result_key
	receipt.outcome_kind = selected.outcome_kind
	receipt.refresh_digest()
	if not receipt.is_valid():
		return _failure(
			ExpeditionActionError.DIGEST_FAILED, &"receipt_digest"
		)
	EconomyCommandSupport.append_transaction_receipt(
		draft,
		TransactionReceiptState.new(
			built_key.key_state as TransactionKeyState,
			receipt.receipt_digest
		)
	)
	# design :186「result_acknowledged=false」：ack 只由
	# AcknowledgeNodeChoiceResultCommand 在另一筆交易翻 true，任何 outcome 都不得
	# 在本交易內自動 ack，否則 reload 無法重播結果（review M3）。
	draft.node_choice_receipts.append(
		NodeChoiceReceiptLedgerEntry.new(receipt, false)
	)
	draft.next_transaction_serial = draft.next_transaction_serial.add(U64Bits.one())
	match selected.outcome_kind:
		OUTCOME_OPEN_DISMANTLE_SERVICE:
			draft.resolution_state = NodeServicePendingResolutionState.new(
				&"dismantle", pending.node_id, receipt.receipt_digest
			)
		OUTCOME_OPEN_REWARD_STAGE:
			var reward_stage := _reward_stage(selected, catalog)
			if reward_stage < 0:
				return _failure(
					ExpeditionActionError.REWARD_CONFIG_INVALID,
					&"choice.reward_table_ref"
				)
			draft.resolution_state = IdleResolutionState.new()
			var generated := RewardService.new().generate_stage(
				draft,
				reward_stage,
				catalog
			)
			if not generated.ok:
				return generated
			draft = generated.run_state
		_:
			# 與 non_combat_node_service/reward advance 同義務:離場前釋放本節點的
			# shop offers,否則下一次 EnterNodeEvent 被 SHOP_LEAK 擋死
			var release_error := RewardService.new().try_release_shop_offers(draft)
			if release_error != null:
				return ExpeditionActionResult.failure(
					release_error.code, release_error.field_path
				)
			_complete_current_node(draft)
			draft.resolution_state = IdleResolutionState.new()
			draft.run_phase = RunState.RunPhase.MAP
	return ExpeditionActionResult.success(draft)


## design.md §5（:201-203）：另一筆 copy-save-swap 交易，只把 wrapper flag 改 true，
## 不刪 receipt、不改 digest。已是 true 時是冪等 no-op（reload 後 UI 可能重送一次
## ack；拒絕它只會讓畫面卡在已經播完的結果上）。
func acknowledge(
	source: RunState,
	expected_run_id: String,
	receipt_digest: String
) -> ExpeditionActionResult:
	if source == null or receipt_digest.is_empty():
		return _failure(ExpeditionActionError.INPUT_INVALID, &"receipt_digest")
	if expected_run_id != source.run_id:
		return _failure(NodeChoiceRejection.RUN_MISMATCH, &"expected_run_id")
	var draft := source.deep_clone()
	for entry: NodeChoiceReceiptLedgerEntry in draft.node_choice_receipts:
		if (
			entry != null
			and entry.receipt != null
			and entry.receipt.receipt_digest == receipt_digest
		):
			entry.result_acknowledged = true
			return ExpeditionActionResult.success(draft)
	return _failure(ExpeditionActionError.RESULT_INVALID, &"receipt_digest")


func _reject_payload(
	payload: NodeChoiceCommitPayload,
	pending: NodeChoicePendingState,
	choice_set: NodeChoiceSetRule
) -> ExpeditionActionError:
	if payload.node_id != pending.node_id:
		return ExpeditionActionError.new(
			NodeChoiceRejection.NODE_MISMATCH, &"node_id"
		)
	if (
		payload.choice_set_id != pending.choice_set_id
		or choice_set.choice_set_id != pending.choice_set_id
	):
		return ExpeditionActionError.new(
			NodeChoiceRejection.CHOICE_SET_MISMATCH, &"choice_set_id"
		)
	if payload.content_version != pending.content_version:
		return ExpeditionActionError.new(
			NodeChoiceRejection.CONTENT_VERSION_MISMATCH, &"content_version"
		)
	if payload.catalog_schema_version != pending.catalog_schema_version:
		return ExpeditionActionError.new(
			NodeChoiceRejection.CATALOG_SCHEMA_MISMATCH,
			&"catalog_schema_version"
		)
	if payload.content_codec_version != pending.content_codec_version:
		return ExpeditionActionError.new(
			NodeChoiceRejection.CODEC_MISMATCH, &"content_codec_version"
		)
	if payload.manifest_digest != pending.manifest_digest:
		return ExpeditionActionError.new(
			NodeChoiceRejection.MANIFEST_MISMATCH, &"manifest_digest"
		)
	if payload.pending_digest != pending.pending_digest:
		return ExpeditionActionError.new(
			NodeChoiceRejection.PENDING_DIGEST_MISMATCH, &"pending_digest"
		)
	if payload.lifecycle_nonce != pending.lifecycle_nonce:
		return ExpeditionActionError.new(
			NodeChoiceRejection.NONCE_MISMATCH, &"lifecycle_nonce"
		)
	if not pending.choice_ids.has(payload.choice_id):
		return ExpeditionActionError.new(
			NodeChoiceRejection.CHOICE_UNKNOWN, &"choice_id"
		)
	return null


## reward_service.gd:456-460／node_entry_service.gd:21-22 的同一道世代守衛：
## catalog 與 run 釘住的 content snapshot 不同世代時，choice set 與 reward table
## 都不得授權（review M2）。
func _validate_generation(
	source: RunState,
	catalog: EconomyExpeditionCatalog
) -> ExpeditionActionError:
	if catalog == null or source.content_snapshot == null:
		return ExpeditionActionError.new(
			ExpeditionActionError.INPUT_INVALID, &"catalog"
		)
	if catalog.manifest_digest_value() != source.content_snapshot.manifest_digest_value():
		return ExpeditionActionError.new(
			ExpeditionActionError.GENERATION_MISMATCH,
			&"content_snapshot.manifest_digest"
		)
	return null


## review N4：`NodeChoicePendingState.is_valid()` 有六個失敗來源，一律回
## `lifecycle_nonce` 會把「run 還釘在 catalog schema 1／codec 2 世代」的診斷指向 RNG，
## 排查者會往 nonce/rng 方向找。design.md §5（:162-164）把世代欄位寫進 pending 的
## exact fields，因此先具名判世代，其餘才落回 nonce。
func _pending_invalid_field_path(
	pending: NodeChoicePendingState
) -> StringName:
	if pending.catalog_schema_version != 2:
		return &"catalog_schema_version"
	if pending.content_codec_version != 3:
		return &"content_codec_version"
	if pending.manifest_digest.length() != 64:
		return &"manifest_digest"
	if pending.choice_ids.size() < 2:
		return &"choice_set.choices"
	if not StableIdValidator.new().is_valid(pending.choice_set_id):
		return &"choice_set_id"
	if not String(pending.node_id).begins_with("node_"):
		return &"node_id"
	return &"lifecycle_nonce"


func _has_committed_receipt(
	source: RunState,
	node_id: StringName,
	pending_digest: String
) -> bool:
	for entry: NodeChoiceReceiptLedgerEntry in source.node_choice_receipts:
		if (
			entry != null
			and entry.receipt != null
			and entry.receipt.node_id == node_id
			and entry.receipt.pending_digest == pending_digest
		):
			return true
	return false


func _draw_lifecycle_nonce(draft: RunState) -> String:
	var snapshot := EconomyCommandSupport.try_named_rng(
		draft, LIFECYCLE_NONCE_STREAM
	)
	if snapshot == null:
		var derived := RngService.new().derive_stream(
			draft.run_seed,
			&"map",
			StringName("%s%s" % [draft.run_id, LIFECYCLE_NONCE_CONTEXT_SUFFIX])
		)
		if not derived.ok:
			return ""
		snapshot = derived.snapshot
	var restored := Pcg32Stream.from_snapshot(snapshot)
	if not restored.ok:
		return ""
	var stream := restored.stream
	for _attempt: int in range(NONCE_DRAW_ATTEMPTS):
		var high := stream.next_u32()
		if not high.ok:
			return ""
		var low := stream.next_u32()
		if not low.ok:
			return ""
		var bits := U64Bits.from_u32(
			high.value_u32.low_u32(), low.value_u32.low_u32()
		)
		if not bits.ok:
			return ""
		# 抽過的 entropy 一定要落回 draft，否則 cancel→re-begin 會重抽同一個值。
		EconomyCommandSupport.set_named_rng(
			draft, LIFECYCLE_NONCE_STREAM, low.next_snapshot
		)
		if not bits.value.is_zero():
			return bits.value.to_hex()
	return ""


func _reward_stage(
	choice: NodeChoiceRule,
	catalog: EconomyExpeditionCatalog
) -> int:
	if (
		choice == null
		or not choice.has_reward_table_ref
		or catalog == null
	):
		return -1
	var table := catalog.try_reward_table_by_id(choice.reward_table_ref)
	if table == null:
		return -1
	if table.supports_stage(PendingRewardState.StageId.RELIC):
		return PendingRewardState.StageId.RELIC
	if table.supports_stage(PendingRewardState.StageId.STANDARD):
		return PendingRewardState.StageId.STANDARD
	if table.supports_stage(PendingRewardState.StageId.EVENT_GRANT):
		return PendingRewardState.StageId.EVENT_GRANT
	return -1


func _find_choice(
	choice_set: NodeChoiceSetRule,
	choice_id: StringName
) -> NodeChoiceRule:
	for choice: NodeChoiceRule in choice_set.choices:
		if choice != null and choice.choice_id == choice_id:
			return choice
	return null


func _apply_operations(
	draft: RunState,
	operations: Array[NodeChoiceOperationRule]
) -> ExpeditionActionError:
	for operation: NodeChoiceOperationRule in operations:
		if operation.kind == NodeChoiceOperationRule.Kind.ADD_GOLD:
			draft.economy_state.gold += operation.amount
		elif operation.kind == NodeChoiceOperationRule.Kind.HEAL_EXPEDITION_HP:
			draft.expedition_hp = mini(
				100,
				draft.expedition_hp + operation.amount
			)
		elif operation.kind == NodeChoiceOperationRule.Kind.DRAIN_EXPEDITION_HP:
			draft.expedition_hp = maxi(
				1,
				draft.expedition_hp - operation.amount
			)
		else:
			return ExpeditionActionError.new(
				ExpeditionActionError.INPUT_INVALID, &"choice.operations"
			)
	return null


func _complete_current_node(draft: RunState) -> void:
	if draft.current_node_id == null:
		return
	for node: MapNodeState in draft.map_state.nodes:
		if node.node_id != draft.current_node_id.value:
			continue
		node.completed = true
		if not draft.map_state.completed_node_ids.has(node.node_id):
			draft.map_state.completed_node_ids.append(node.node_id)
			draft.map_state.completed_node_ids.sort()
		return


func _failure(code: StringName, path: StringName) -> ExpeditionActionResult:
	return ExpeditionActionResult.failure(code, path)
