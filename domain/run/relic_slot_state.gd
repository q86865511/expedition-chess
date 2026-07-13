class_name RelicSlotState
extends RefCounted

var slot_index: int
var relic_id: OptionalStringNameValue

func _init(p_slot_index: int, p_relic_id: OptionalStringNameValue) -> void:
	slot_index = p_slot_index
	relic_id = p_relic_id.deep_clone() if p_relic_id != null else null

func deep_clone() -> RelicSlotState:
	return RelicSlotState.new(slot_index, relic_id)
