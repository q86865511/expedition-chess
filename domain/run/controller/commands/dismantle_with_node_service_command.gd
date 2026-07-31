class_name DismantleWithNodeServiceCommand
extends RunCommand

## design.md §5（:208-213）：`DismantleWithNodeServiceCommand(expected_run_id,
## node_id, choice_receipt_digest, item_instance_id)` 需要 NodeServicePending
## (service_kind=dismantle) 的 service authority，沿用既有拆解／overflow 規則，
## 但**不要求、不消耗 consumable**；服務期間不限次數，每次仍有唯一 transaction
## receipt。節點完成只由 ExitNodeServiceCommand 負責——本命令永遠不動
## resolution_state／run_phase／map node completion（review H2）。
##
## 一般 DismantleEquipmentCommand 維持耗材規則，兩者共用同一份 inventory 容量常數。

var _expected_run_id: String
var _node_id: StringName
var _choice_receipt_digest: String
var _equipment_item_instance_id: String

func _init(
	p_expected_run_id: String,
	p_node_id: StringName,
	p_choice_receipt_digest: String,
	p_equipment_item_instance_id: String
) -> void:
	_expected_run_id = p_expected_run_id
	_node_id = p_node_id
	_choice_receipt_digest = p_choice_receipt_digest
	_equipment_item_instance_id = p_equipment_item_instance_id

func is_concrete() -> bool:
	return not _expected_run_id.is_empty() \
		and not String(_node_id).is_empty() \
		and not _choice_receipt_digest.is_empty() \
		and not _equipment_item_instance_id.is_empty()

func apply_to(draft: RunState) -> CommandApplyResult:
	if not is_concrete() or draft == null or draft.roster_state == null:
		return _rejected(&"run.roster_state", &"DISMANTLE_NODE_SERVICE_DRAFT_INVALID")
	var authority_error := NodeServiceAuthority.try_reject(
		draft,
		&"dismantle",
		_expected_run_id,
		_node_id,
		_choice_receipt_digest,
		&"DISMANTLE_NODE_SERVICE"
	)
	if authority_error != null:
		return CommandApplyResult.failure(authority_error)
	var equipment_item := _find_item(draft, _equipment_item_instance_id)
	if equipment_item == null or equipment_item.bound_unit_instance_id == null:
		return _rejected(
			&"run.roster_state.item_instances",
			&"DISMANTLE_NODE_SERVICE_TARGET_NOT_BOUND"
		)
	var unit := _find_unit(draft, equipment_item.bound_unit_instance_id.value)
	if unit == null or not unit.equipment_instance_ids.has(_equipment_item_instance_id):
		return _rejected(
			&"run.roster_state.unit_instances",
			&"DISMANTLE_NODE_SERVICE_TARGET_NOT_BOUND"
		)
	if draft.next_transaction_serial.equals(U64Bits.max_value()):
		return _rejected(
			&"run.next_transaction_serial",
			&"DISMANTLE_NODE_SERVICE_SERIAL_EXHAUSTED"
		)
	var built := RuntimeKeySchemaRegistry.new().build_transaction(
		StringName(draft.run_id),
		_node_id,
		&"dismantle_node_service",
		draft.next_transaction_serial
	)
	if not built.ok:
		return _rejected(
			&"run.transaction_receipts", &"DISMANTLE_NODE_SERVICE_KEY_FAILED"
		)
	var digest_parts: Array[String] = [
		"NSD1",
		String(built.key_state.digest),
		_choice_receipt_digest,
		_equipment_item_instance_id,
	]
	var payload := EconomyPayloadDigest.sha256(digest_parts)
	if payload.is_empty():
		return _rejected(
			&"run.transaction_receipts", &"DISMANTLE_NODE_SERVICE_DIGEST_FAILED"
		)
	unit.equipment_instance_ids.erase(_equipment_item_instance_id)
	equipment_item.bound_unit_instance_id = null
	if draft.roster_state.inventory_item_instance_ids.size() \
		< DismantleEquipmentCommand.INVENTORY_CAPACITY:
		draft.roster_state.inventory_item_instance_ids.append(_equipment_item_instance_id)
		draft.roster_state.inventory_item_instance_ids.sort()
	else:
		draft.roster_state.pending_item_overflow.append(_equipment_item_instance_id)
		draft.roster_state.pending_item_overflow.sort()
	EconomyCommandSupport.append_transaction_receipt(
		draft,
		TransactionReceiptState.new(
			built.key_state as TransactionKeyState, payload
		)
	)
	draft.next_transaction_serial = draft.next_transaction_serial.add(U64Bits.one())
	return CommandApplyResult.success(draft)

func _find_unit(draft: RunState, unit_instance_id: String) -> UnitInstance:
	for unit: UnitInstance in draft.roster_state.unit_instances:
		if unit.instance_id == unit_instance_id:
			return unit
	return null

func _find_item(draft: RunState, item_instance_id: String) -> ItemInstanceState:
	for item: ItemInstanceState in draft.roster_state.item_instances:
		if item.instance_id == item_instance_id:
			return item
	return null

func _rejected(field_path: StringName, source_code: StringName) -> CommandApplyResult:
	var diagnostics: Array[DiagnosticValue] = [
		DiagnosticValue.from_string(&"source_code", String(source_code)),
	]
	return CommandApplyResult.failure(
		CommandApplyError.new(CommandApplyError.APPLY_REJECTED, field_path, null, diagnostics)
	)
