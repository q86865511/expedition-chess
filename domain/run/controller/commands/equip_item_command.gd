class_name EquipItemCommand
extends RunCommand

## T04 / S4-AC-006 (specs/build-systems/design.md §5.2): binds one complete
## EquipmentDef instance from inventory onto a roster unit. Pre-validates
## unit.equipment_instance_ids.size() < EQUIPMENT_CAPACITY, no unique_group
## conflict against the unit's already-equipped items, and that the item's
## def_id actually resolves to a BattleEquipmentRule (rejects ItemComponentDef
## and any other non-equipment content). The pinned catalog generation is also
## checked against the draft's content_snapshot first (see
## commit_board_layout_command.gd:35-40), so a stale catalog can never author a
## commit against a newer pinned run. Any rejection leaves `draft` untouched and
## returns a named "source_code" diagnostic (see commit_board_layout_command.gd's
## `_rejected` convention).

const EQUIPMENT_CAPACITY: int = 3

var _unit_instance_id: String
var _item_instance_id: String
var _catalog: BattleRuleCatalog

func _init(
	p_unit_instance_id: String,
	p_item_instance_id: String,
	p_catalog: BattleRuleCatalog
) -> void:
	_unit_instance_id = p_unit_instance_id
	_item_instance_id = p_item_instance_id
	_catalog = p_catalog.deep_clone() if p_catalog != null else null

func is_concrete() -> bool:
	return not _unit_instance_id.is_empty() and not _item_instance_id.is_empty() \
		and _catalog != null

func apply_to(draft: RunState) -> CommandApplyResult:
	if not is_concrete() or draft == null or draft.roster_state == null \
		or draft.content_snapshot == null:
		return _rejected(&"run.roster_state", &"EQUIP_ITEM_DRAFT_INVALID")
	if _catalog.manifest_digest_value() != draft.content_snapshot.manifest_digest_value():
		return _rejected(
			&"run.content_snapshot.manifest_digest",
			&"EQUIP_ITEM_CATALOG_GENERATION_MISMATCH"
		)
	var unit := _find_unit(draft, _unit_instance_id)
	if unit == null:
		return _rejected(&"run.roster_state.unit_instances", &"EQUIP_ITEM_UNIT_NOT_FOUND")
	var item := _find_item(draft, _item_instance_id)
	if item == null or item.bound_unit_instance_id != null \
		or not draft.roster_state.inventory_item_instance_ids.has(_item_instance_id):
		return _rejected(&"run.roster_state.item_instances", &"EQUIP_ITEM_NOT_IN_INVENTORY")
	var rule := _catalog.try_equipment_rule(item.def_id)
	if rule == null:
		return _rejected(&"run.roster_state.item_instances.def_id", &"EQUIP_ITEM_NOT_EQUIPMENT")
	if unit.equipment_instance_ids.size() >= EQUIPMENT_CAPACITY:
		return _rejected(
			&"run.roster_state.unit_instances.equipment_instance_ids", &"EQUIP_ITEM_SLOTS_FULL"
		)
	if rule.unique_group != null \
		and _has_unique_conflict(draft, unit, rule.unique_group.value):
		return _rejected(
			&"run.roster_state.unit_instances.equipment_instance_ids",
			&"EQUIP_ITEM_UNIQUE_GROUP_CONFLICT"
		)
	item.bound_unit_instance_id = OptionalStringValue.new(_unit_instance_id)
	unit.equipment_instance_ids.append(_item_instance_id)
	draft.roster_state.inventory_item_instance_ids.erase(_item_instance_id)
	return CommandApplyResult.success(draft)

func _has_unique_conflict(
	draft: RunState,
	unit: UnitInstance,
	unique_group: StringName
) -> bool:
	for equipped_id: String in unit.equipment_instance_ids:
		var equipped_item := _find_item(draft, equipped_id)
		if equipped_item == null:
			continue
		var equipped_rule := _catalog.try_equipment_rule(equipped_item.def_id)
		if equipped_rule != null and equipped_rule.unique_group != null \
			and equipped_rule.unique_group.value == unique_group:
			return true
	return false

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
