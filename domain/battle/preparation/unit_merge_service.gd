class_name UnitMergeService
extends RefCounted

const DEFAULT_INVENTORY_CAPACITY: int = 16

var _inventory_capacity: int

func _init(p_inventory_capacity: int = DEFAULT_INVENTORY_CAPACITY) -> void:
	_inventory_capacity = p_inventory_capacity

func merge_all(roster: RosterState, catalog: BattleRuleCatalog) -> UnitMergeResult:
	if roster == null or catalog == null or _inventory_capacity < 0 \
		or not _roster_is_cloneable(roster):
		return _failure(UnitMergeError.INVALID_INPUT, &"roster")
	var draft := roster.deep_clone()
	var initial_error := _validate_item_ownership(draft, catalog)
	if initial_error != null:
		return UnitMergeResult.failure(initial_error)
	var before_ledger := _build_copy_ledger(draft.unit_instances)
	var merge_count := 0
	while true:
		var group := _next_merge_group(draft)
		if group.is_empty():
			break
		var merge_error := _merge_group(draft, group, catalog)
		if merge_error != null:
			return UnitMergeResult.failure(merge_error)
		merge_count += 1
	var after_ledger := _build_copy_ledger(draft.unit_instances)
	if not _ledgers_equal(before_ledger, after_ledger):
		return _failure(UnitMergeError.COPY_CONSERVATION, &"unit_instances")
	var final_error := _validate_item_ownership(draft, catalog)
	if final_error != null:
		return UnitMergeResult.failure(final_error)
	return UnitMergeResult.success(draft, merge_count, after_ledger)

func _next_merge_group(roster: RosterState) -> Array[UnitInstance]:
	var definition_ids: Array[StringName] = []
	for unit: UnitInstance in roster.unit_instances:
		if unit.star >= 1 and unit.star <= 2 and not definition_ids.has(unit.def_id):
			definition_ids.append(unit.def_id)
	definition_ids.sort_custom(StableNameSort.id_less)
	for star: int in [1, 2]:
		for definition_id: StringName in definition_ids:
			var candidates: Array[UnitInstance] = []
			for unit: UnitInstance in roster.unit_instances:
				if unit.def_id == definition_id and unit.star == star:
					candidates.append(unit)
			_sort_candidates(candidates, roster)
			if candidates.size() >= 3:
				var group: Array[UnitInstance] = [candidates[0], candidates[1], candidates[2]]
				return group
	var no_group: Array[UnitInstance] = []
	return no_group

func _sort_candidates(candidates: Array[UnitInstance], roster: RosterState) -> void:
	for index: int in range(1, candidates.size()):
		var cursor := index
		while cursor > 0 and _candidate_precedes(candidates[cursor], candidates[cursor - 1], roster):
			var temporary := candidates[cursor - 1]
			candidates[cursor - 1] = candidates[cursor]
			candidates[cursor] = temporary
			cursor -= 1

func _candidate_precedes(left: UnitInstance, right: UnitInstance, roster: RosterState) -> bool:
	var left_placement := _find_placement(roster.board.placements, left.instance_id)
	var right_placement := _find_placement(roster.board.placements, right.instance_id)
	if (left_placement != null) != (right_placement != null):
		return left_placement != null
	if left_placement != null:
		var left_cell := left_placement.logical_y * 8 + left_placement.logical_x
		var right_cell := right_placement.logical_y * 8 + right_placement.logical_x
		if left_cell != right_cell:
			return left_cell < right_cell
	else:
		var left_bench := roster.bench_unit_instance_ids.find(left.instance_id)
		var right_bench := roster.bench_unit_instance_ids.find(right.instance_id)
		if left_bench < 0:
			left_bench = 0x7fffffff
		if right_bench < 0:
			right_bench = 0x7fffffff
		if left_bench != right_bench:
			return left_bench < right_bench
	return left.instance_id < right.instance_id

func _merge_group(
	roster: RosterState,
	group: Array[UnitInstance],
	catalog: BattleRuleCatalog
) -> UnitMergeError:
	var primary := group[0]
	var minimum_serial := primary.acquired_serial.deep_clone()
	for unit: UnitInstance in group:
		if unit.acquired_serial.compare(minimum_serial) < 0:
			minimum_serial = unit.acquired_serial.deep_clone()
	primary.star += 1
	primary.acquired_serial = minimum_serial
	for consumed_index: int in range(1, group.size()):
		var consumed := group[consumed_index]
		for item_id: String in consumed.equipment_instance_ids:
			var item := _find_item(roster.item_instances, item_id)
			if item == null or item.bound_unit_instance_id == null \
				or item.bound_unit_instance_id.value != consumed.instance_id:
				return UnitMergeError.new(
					UnitMergeError.EQUIPMENT_BINDING,
					&"item_instances.bound_unit_instance_id"
				)
			if primary.equipment_instance_ids.size() < 3 \
				and not _has_unique_group_conflict(primary, item, roster, catalog):
				primary.equipment_instance_ids.append(item_id)
				item.bound_unit_instance_id = OptionalStringValue.new(primary.instance_id)
			else:
				item.bound_unit_instance_id = null
				if roster.inventory_item_instance_ids.size() < _inventory_capacity:
					roster.inventory_item_instance_ids.append(item_id)
				else:
					roster.pending_item_overflow.append(item_id)
		_remove_unit_from_layout(roster, consumed.instance_id)
		_remove_unit_instance(roster.unit_instances, consumed.instance_id)
	roster.inventory_item_instance_ids.sort()
	roster.pending_item_overflow.sort()
	return null

func _has_unique_group_conflict(
	primary: UnitInstance,
	candidate_item: ItemInstanceState,
	roster: RosterState,
	catalog: BattleRuleCatalog
) -> bool:
	var candidate_rule := catalog.try_equipment_rule(candidate_item.def_id)
	if candidate_rule == null or candidate_rule.unique_group == null:
		return false
	for equipped_id: String in primary.equipment_instance_ids:
		var equipped := _find_item(roster.item_instances, equipped_id)
		var equipped_rule := catalog.try_equipment_rule(equipped.def_id)
		if equipped_rule != null and equipped_rule.unique_group != null \
			and equipped_rule.unique_group.value == candidate_rule.unique_group.value:
			return true
	return false

func _remove_unit_from_layout(roster: RosterState, instance_id: String) -> void:
	for index: int in range(roster.board.placements.size() - 1, -1, -1):
		if roster.board.placements[index].unit_instance_id == instance_id:
			roster.board.placements.remove_at(index)
	for index: int in range(roster.bench_unit_instance_ids.size() - 1, -1, -1):
		if roster.bench_unit_instance_ids[index] == instance_id:
			roster.bench_unit_instance_ids.remove_at(index)

func _remove_unit_instance(units: Array[UnitInstance], instance_id: String) -> void:
	for index: int in range(units.size() - 1, -1, -1):
		if units[index].instance_id == instance_id:
			units.remove_at(index)
			return

func _validate_item_ownership(roster: RosterState, catalog: BattleRuleCatalog) -> UnitMergeError:
	if roster.inventory_item_instance_ids.size() > _inventory_capacity:
		return UnitMergeError.new(
			UnitMergeError.ITEM_CONSERVATION,
			&"inventory_item_instance_ids"
		)
	var item_ids: Array[String] = []
	for item: ItemInstanceState in roster.item_instances:
		if item.instance_id.is_empty() or item_ids.has(item.instance_id):
			return UnitMergeError.new(
				UnitMergeError.ITEM_CONSERVATION,
				&"item_instances.instance_id"
			)
		item_ids.append(item.instance_id)
	var inventory_ids: Array[String] = []
	for item_id: String in roster.inventory_item_instance_ids:
		var item := _find_item(roster.item_instances, item_id)
		if item_id.is_empty() or inventory_ids.has(item_id) or item == null \
			or item.bound_unit_instance_id != null:
			return UnitMergeError.new(
				UnitMergeError.ITEM_CONSERVATION,
				&"inventory_item_instance_ids"
			)
		inventory_ids.append(item_id)
	var overflow_ids: Array[String] = []
	for item_id: String in roster.pending_item_overflow:
		var item := _find_item(roster.item_instances, item_id)
		if item_id.is_empty() or overflow_ids.has(item_id) \
			or inventory_ids.has(item_id) or item == null \
			or item.bound_unit_instance_id != null:
			return UnitMergeError.new(
				UnitMergeError.ITEM_CONSERVATION,
				&"pending_item_overflow"
			)
		overflow_ids.append(item_id)
	var unit_ids: Array[String] = []
	var referenced_items: Array[String] = []
	for unit: UnitInstance in roster.unit_instances:
		if unit.instance_id.is_empty() or unit_ids.has(unit.instance_id) \
			or unit.star < 1 or unit.star > 3:
			return UnitMergeError.new(UnitMergeError.INVALID_INPUT, &"unit_instances")
		unit_ids.append(unit.instance_id)
		if unit.equipment_instance_ids.size() > 3:
			return UnitMergeError.new(UnitMergeError.EQUIPMENT_BINDING, &"unit_instances.equipment")
		var unique_groups: Array[StringName] = []
		for item_id: String in unit.equipment_instance_ids:
			if referenced_items.has(item_id):
				return UnitMergeError.new(UnitMergeError.ITEM_CONSERVATION, &"item_instances")
			var item := _find_item(roster.item_instances, item_id)
			if item == null or item.bound_unit_instance_id == null \
				or item.bound_unit_instance_id.value != unit.instance_id:
				return UnitMergeError.new(UnitMergeError.EQUIPMENT_BINDING, &"item_instances")
			var rule := catalog.try_equipment_rule(item.def_id)
			if rule == null:
				return UnitMergeError.new(UnitMergeError.EQUIPMENT_RULE_MISSING, &"item_instances.def_id")
			if rule.unique_group != null:
				if unique_groups.has(rule.unique_group.value):
					return UnitMergeError.new(UnitMergeError.EQUIPMENT_BINDING, &"equipment.unique_group")
				unique_groups.append(rule.unique_group.value)
			referenced_items.append(item_id)
	for item: ItemInstanceState in roster.item_instances:
		if item.bound_unit_instance_id != null:
			if not unit_ids.has(item.bound_unit_instance_id.value) \
				or not referenced_items.has(item.instance_id) \
				or inventory_ids.has(item.instance_id) \
				or overflow_ids.has(item.instance_id):
				return UnitMergeError.new(UnitMergeError.ITEM_CONSERVATION, &"item_instances")
		elif inventory_ids.has(item.instance_id) == overflow_ids.has(item.instance_id):
			return UnitMergeError.new(UnitMergeError.ITEM_CONSERVATION, &"item_instances")
	return null

func _roster_is_cloneable(roster: RosterState) -> bool:
	if roster.board == null:
		return false
	for placement: BoardPlacementState in roster.board.placements:
		if placement == null:
			return false
	for unit: UnitInstance in roster.unit_instances:
		if unit == null or unit.acquired_serial == null:
			return false
	for item: ItemInstanceState in roster.item_instances:
		if item == null or item.acquired_serial == null:
			return false
	for slot: RelicSlotState in roster.active_relic_slots:
		if slot == null:
			return false
	return true

func _build_copy_ledger(units: Array[UnitInstance]) -> Array[UnitCopyLedgerEntry]:
	var definition_ids: Array[StringName] = []
	for unit: UnitInstance in units:
		if not definition_ids.has(unit.def_id):
			definition_ids.append(unit.def_id)
	definition_ids.sort_custom(StableNameSort.id_less)
	var ledger: Array[UnitCopyLedgerEntry] = []
	for definition_id: StringName in definition_ids:
		var copies := 0
		for unit: UnitInstance in units:
			if unit.def_id == definition_id:
				copies += _star_weight(unit.star)
		ledger.append(UnitCopyLedgerEntry.new(definition_id, copies))
	return ledger

func _star_weight(star: int) -> int:
	match star:
		1: return 1
		2: return 3
		3: return 9
	return 0

func _ledgers_equal(
	left: Array[UnitCopyLedgerEntry],
	right: Array[UnitCopyLedgerEntry]
) -> bool:
	if left.size() != right.size():
		return false
	for index: int in range(left.size()):
		if left[index].unit_def_id != right[index].unit_def_id \
			or left[index].weighted_copies != right[index].weighted_copies:
			return false
	return true

func _find_placement(
	placements: Array[BoardPlacementState],
	instance_id: String
) -> BoardPlacementState:
	for placement: BoardPlacementState in placements:
		if placement.unit_instance_id == instance_id:
			return placement
	return null

func _find_item(items: Array[ItemInstanceState], instance_id: String) -> ItemInstanceState:
	for item: ItemInstanceState in items:
		if item.instance_id == instance_id:
			return item
	return null

func _failure(code: StringName, field_path: StringName) -> UnitMergeResult:
	return UnitMergeResult.failure(UnitMergeError.new(code, field_path))
