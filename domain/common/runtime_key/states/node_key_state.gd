class_name NodeKeyState
extends RuntimeKeyState

var run_id: StringName = &""
var act_index: int = 0
var node_kind: StringName = &""
var layer_index: int = 0
var slot_index: int = 0

static func create(run: StringName, act: int, node_type: StringName, layer: int, slot: int, key_digest: StringName) -> NodeKeyState:
	var value := NodeKeyState.new()
	value.kind = &"node"
	value.run_id = run
	value.act_index = act
	value.node_kind = node_type
	value.layer_index = layer
	value.slot_index = slot
	value.digest = key_digest
	return value

func deep_clone() -> RuntimeKeyState:
	return create(run_id, act_index, node_kind, layer_index, slot_index, digest)
