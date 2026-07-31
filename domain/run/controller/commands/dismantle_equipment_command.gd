class_name DismantleEquipmentCommand
extends RunCommand

## T04 / S4-AC-007 (specs/build-systems/design.md §5.3): consumes one
## dismantle-consumable item instance from inventory to unbind a bound
## equipment instance in the same transaction, returning it to inventory (or
## overflow when inventory is full). Any validation failure leaves `draft`
## untouched and consumes no consumable (see commit_board_layout_command.gd's
## `_rejected` convention for the named "source_code" diagnostic).
##
## Contract note (see tests/fixtures/build_items/equip_dismantle_test_fixture.gd
## header): the consumable is modeled as an ordinary unbound ItemInstanceState
## sitting in inventory, but its def_id must resolve to a genuine dismantle
## ConsumableDef via the pinned ConsumableRuleTable -- an arbitrary inventory
## item (equipment, component, non-dismantle consumable) can never be spent to
## unbind equipment.

const INVENTORY_CAPACITY: int = 16

var _equipment_item_instance_id: String
var _consumable_item_instance_id: String
var _consumable_rules: ConsumableRuleTable

func _init(
	p_equipment_item_instance_id: String,
	p_consumable_item_instance_id: String,
	p_consumable_rules: ConsumableRuleTable
) -> void:
	_equipment_item_instance_id = p_equipment_item_instance_id
	_consumable_item_instance_id = p_consumable_item_instance_id
	_consumable_rules = p_consumable_rules.deep_clone() if p_consumable_rules != null else null

func is_concrete() -> bool:
	return not _equipment_item_instance_id.is_empty() \
		and not _consumable_item_instance_id.is_empty() \
		and _consumable_rules != null

func apply_to(draft: RunState) -> CommandApplyResult:
	if not is_concrete() or draft == null or draft.roster_state == null:
		return _rejected(&"run.roster_state", &"DISMANTLE_EQUIPMENT_DRAFT_INVALID")
	var service_pending := (
		draft.resolution_state as NodeServicePendingResolutionState
	)
	if (
		not draft.resolution_state is IdleResolutionState
		and (
			service_pending == null
			or service_pending.service_kind != &"dismantle"
		)
	):
		return _rejected(
			&"run.resolution_state",
			&"DISMANTLE_EQUIPMENT_RESOLUTION_INVALID"
		)
	var equipment_item := _find_item(draft, _equipment_item_instance_id)
	if equipment_item == null or equipment_item.bound_unit_instance_id == null:
		return _rejected(
			&"run.roster_state.item_instances", &"DISMANTLE_EQUIPMENT_TARGET_NOT_BOUND"
		)
	var unit := _find_unit(draft, equipment_item.bound_unit_instance_id.value)
	if unit == null or not unit.equipment_instance_ids.has(_equipment_item_instance_id):
		return _rejected(
			&"run.roster_state.unit_instances", &"DISMANTLE_EQUIPMENT_TARGET_NOT_BOUND"
		)
	var consumable_item := _find_item(draft, _consumable_item_instance_id)
	if consumable_item == null or consumable_item.bound_unit_instance_id != null \
		or not draft.roster_state.inventory_item_instance_ids.has(_consumable_item_instance_id):
		return _rejected(
			&"run.roster_state.item_instances", &"DISMANTLE_EQUIPMENT_CONSUMABLE_UNAVAILABLE"
		)
	if not _consumable_rules.is_dismantle_consumable(consumable_item.def_id):
		return _rejected(
			&"run.roster_state.item_instances.def_id",
			&"DISMANTLE_EQUIPMENT_CONSUMABLE_KIND"
		)
	draft.roster_state.inventory_item_instance_ids.erase(_consumable_item_instance_id)
	draft.roster_state.item_instances.erase(consumable_item)
	unit.equipment_instance_ids.erase(_equipment_item_instance_id)
	equipment_item.bound_unit_instance_id = null
	if draft.roster_state.inventory_item_instance_ids.size() < INVENTORY_CAPACITY:
		draft.roster_state.inventory_item_instance_ids.append(_equipment_item_instance_id)
		draft.roster_state.inventory_item_instance_ids.sort()
	else:
		draft.roster_state.pending_item_overflow.append(_equipment_item_instance_id)
		draft.roster_state.pending_item_overflow.sort()
	if service_pending != null:
		_complete_node_service(draft, service_pending)
	return CommandApplyResult.success(draft)

func _complete_node_service(
	draft: RunState,
	pending: NodeServicePendingResolutionState
) -> void:
	for entry: NodeChoiceReceiptLedgerEntry in draft.node_choice_receipts:
		if (
			entry != null
			and entry.receipt != null
			and entry.receipt.receipt_digest
				== pending.choice_receipt_digest
		):
			entry.result_acknowledged = true
			break
	for node: MapNodeState in draft.map_state.nodes:
		if StringName(node.node_id) != pending.node_id:
			continue
		node.completed = true
		if not draft.map_state.completed_node_ids.has(node.node_id):
			draft.map_state.completed_node_ids.append(node.node_id)
			draft.map_state.completed_node_ids.sort()
		break
	draft.resolution_state = IdleResolutionState.new()
	draft.run_phase = RunState.RunPhase.MAP

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
