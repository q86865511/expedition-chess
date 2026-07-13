class_name RosterState
extends RefCounted

var board: BoardState
var bench_unit_instance_ids: Array[String] = []
var unit_instances: Array[UnitInstance] = []
var item_instances: Array[ItemInstanceState] = []
var inventory_item_instance_ids: Array[String] = []
var pending_item_overflow: Array[String] = []
var active_relic_slots: Array[RelicSlotState] = []

func _init(
	p_board: BoardState,
	p_bench_unit_instance_ids: Array[String],
	p_unit_instances: Array[UnitInstance],
	p_item_instances: Array[ItemInstanceState],
	p_inventory_item_instance_ids: Array[String],
	p_pending_item_overflow: Array[String],
	p_active_relic_slots: Array[RelicSlotState]
) -> void:
	board = p_board.deep_clone()
	bench_unit_instance_ids.assign(p_bench_unit_instance_ids)
	for unit: UnitInstance in p_unit_instances:
		unit_instances.append(unit.deep_clone())
	for item: ItemInstanceState in p_item_instances:
		item_instances.append(item.deep_clone())
	inventory_item_instance_ids.assign(p_inventory_item_instance_ids)
	pending_item_overflow.assign(p_pending_item_overflow)
	for slot: RelicSlotState in p_active_relic_slots:
		active_relic_slots.append(slot.deep_clone())

func deep_clone() -> RosterState:
	return RosterState.new(
		board,
		bench_unit_instance_ids,
		unit_instances,
		item_instances,
		inventory_item_instance_ids,
		pending_item_overflow,
		active_relic_slots
	)
