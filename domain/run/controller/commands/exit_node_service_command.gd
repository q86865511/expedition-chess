class_name ExitNodeServiceCommand
extends RunCommand

## design.md §5（:213-214）：「只有 ExitNodeServiceCommand 完成節點」。
## 這是 NodeServicePendingResolutionState 的唯一出口，不管服務期間拆了幾件裝備
## （含零件）都可以離場——沒有這條出路時，缺耗材／沒有已綁定裝備的玩家會永遠停在
## NODE_SERVICE_PENDING／PREPARE，run 永久卡死（review H2）。
##
## 離場義務與 non_combat_node_service.gd:46、reward_service.gd:420、
## commit_node_choice_service.gd 的 APPLY 出口相同：先釋放本節點的 shop offers，
## 否則下一次 EnterNodeEvent 會被 NODE_ENTRY_SHOP_LEAK 擋死（review H1）。

var _expected_run_id: String
var _node_id: StringName
var _choice_receipt_digest: String

func _init(
	p_expected_run_id: String,
	p_node_id: StringName,
	p_choice_receipt_digest: String
) -> void:
	_expected_run_id = p_expected_run_id
	_node_id = p_node_id
	_choice_receipt_digest = p_choice_receipt_digest

func is_concrete() -> bool:
	return not _expected_run_id.is_empty() \
		and not String(_node_id).is_empty() \
		and not _choice_receipt_digest.is_empty()

func apply_to(draft: RunState) -> CommandApplyResult:
	if not is_concrete() or draft == null or draft.map_state == null:
		return _rejected(&"run.map_state", &"EXIT_NODE_SERVICE_DRAFT_INVALID")
	var authority_error := NodeServiceAuthority.try_reject(
		draft,
		&"dismantle",
		_expected_run_id,
		_node_id,
		_choice_receipt_digest,
		&"EXIT_NODE_SERVICE"
	)
	if authority_error != null:
		return CommandApplyResult.failure(authority_error)
	var release_error := RewardService.new().try_release_shop_offers(draft)
	if release_error != null:
		return _rejected(
			release_error.field_path, &"EXIT_NODE_SERVICE_SHOP_RELEASE_FAILED"
		)
	for node: MapNodeState in draft.map_state.nodes:
		if StringName(node.node_id) != _node_id:
			continue
		node.completed = true
		if not draft.map_state.completed_node_ids.has(node.node_id):
			draft.map_state.completed_node_ids.append(node.node_id)
			draft.map_state.completed_node_ids.sort()
		break
	# receipt 留在 ledger 且維持 unacknowledged：結果的 ack 是
	# AcknowledgeNodeChoiceResultCommand 的另一筆交易（design :201-203）。
	draft.resolution_state = IdleResolutionState.new()
	draft.run_phase = RunState.RunPhase.MAP
	return CommandApplyResult.success(draft)

func _rejected(field_path: StringName, source_code: StringName) -> CommandApplyResult:
	var diagnostics: Array[DiagnosticValue] = [
		DiagnosticValue.from_string(&"source_code", String(source_code)),
	]
	return CommandApplyResult.failure(
		CommandApplyError.new(CommandApplyError.APPLY_REJECTED, field_path, null, diagnostics)
	)
