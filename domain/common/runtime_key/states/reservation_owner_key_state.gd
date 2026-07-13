class_name ReservationOwnerKeyState
extends RuntimeKeyState

var run_id: StringName = &""
var node_id: StringName = &""
var source_kind: StringName = &""
var stage_or_refresh_id: StringName = &""
var slot_index: int = 0

static func create(run: StringName, node: StringName, source: StringName, stage: StringName, slot: int, key_digest: StringName) -> ReservationOwnerKeyState:
	var value := ReservationOwnerKeyState.new()
	value.kind = &"reservation_owner"
	value.run_id = run
	value.node_id = node
	value.source_kind = source
	value.stage_or_refresh_id = stage
	value.slot_index = slot
	value.digest = key_digest
	return value

func deep_clone() -> RuntimeKeyState:
	return create(run_id, node_id, source_kind, stage_or_refresh_id, slot_index, digest)
