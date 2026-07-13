class_name RosterViewState
extends RefCounted

var board: BoardState
var bench_unit_instance_ids: Array[String] = []
var unit_instances: Array[UnitInstance] = []
var inventory_item_instance_ids: Array[String] = []
var pending_item_overflow: Array[String] = []
var active_relic_slots: Array[RelicSlotState] = []

func _init(
	p_board: BoardState,
	p_bench_unit_instance_ids: Array[String],
	p_unit_instances: Array[UnitInstance],
	p_inventory_item_instance_ids: Array[String],
	p_pending_item_overflow: Array[String],
	p_active_relic_slots: Array[RelicSlotState]
) -> void:
	board = p_board.deep_clone()
	bench_unit_instance_ids.assign(p_bench_unit_instance_ids)
	for unit: UnitInstance in p_unit_instances:
		unit_instances.append(unit.deep_clone())
	inventory_item_instance_ids.assign(p_inventory_item_instance_ids)
	pending_item_overflow.assign(p_pending_item_overflow)
	for slot: RelicSlotState in p_active_relic_slots:
		active_relic_slots.append(slot.deep_clone())

static func from_state(state: RosterState) -> RosterViewState:
	return RosterViewState.new(
		state.board,
		state.bench_unit_instance_ids,
		state.unit_instances,
		state.inventory_item_instance_ids,
		state.pending_item_overflow,
		state.active_relic_slots
	)

func deep_clone() -> RosterViewState:
	return RosterViewState.new(
		board,
		bench_unit_instance_ids,
		unit_instances,
		inventory_item_instance_ids,
		pending_item_overflow,
		active_relic_slots
	)
