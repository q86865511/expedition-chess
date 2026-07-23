class_name RunRelicActivation
extends RefCounted

## 由 RosterState.active_relic_slots 推導「依 slot_index 數值升序」的作用中遺物 id 序列，
## 讓各 run-layer service 的觸發序（design.md §6：slot_index 升序）可直接從真實槽位型別得出，
## 呼叫端不需自行排序。空槽（relic_id == null）略過。
static func active_ids_in_slot_order(slots: Array[RelicSlotState]) -> Array[StringName]:
	var ordered_slots: Array[RelicSlotState] = slots.duplicate()
	ordered_slots.sort_custom(func(left: RelicSlotState, right: RelicSlotState) -> bool:
		return left.slot_index < right.slot_index
	)
	var result: Array[StringName] = []
	for slot: RelicSlotState in ordered_slots:
		if slot.relic_id != null:
			result.append(slot.relic_id.value)
	return result
