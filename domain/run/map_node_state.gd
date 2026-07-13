class_name MapNodeState
extends RefCounted

enum NodeKind { NORMAL, ELITE, MERCHANT, EVENT, REST, TREASURE, BOSS }

static func node_kind_to_token(value: NodeKind) -> StringName:
	return [&"normal", &"elite", &"merchant", &"event", &"rest", &"treasure", &"boss"][value]

var node_id: String
var node_key: NodeKeyState
var def_id: StringName
var act_index: int
var layer_index: int
var slot_index: int
var node_kind: NodeKind
var generated_payload_digest: String
var encounter_preview: EncounterPreviewSnapshot
var completed: bool

func _init(
	p_node_id: String,
	p_node_key: NodeKeyState,
	p_def_id: StringName,
	p_act_index: int,
	p_layer_index: int,
	p_slot_index: int,
	p_node_kind: NodeKind,
	p_generated_payload_digest: String,
	p_encounter_preview: EncounterPreviewSnapshot,
	p_completed: bool
) -> void:
	node_id = p_node_id
	node_key = p_node_key.deep_clone()
	def_id = p_def_id
	act_index = p_act_index
	layer_index = p_layer_index
	slot_index = p_slot_index
	node_kind = p_node_kind
	generated_payload_digest = p_generated_payload_digest
	encounter_preview = p_encounter_preview.deep_clone() if p_encounter_preview != null else null
	completed = p_completed

func deep_clone() -> MapNodeState:
	return MapNodeState.new(
		node_id,
		node_key,
		def_id,
		act_index,
		layer_index,
		slot_index,
		node_kind,
		generated_payload_digest,
		encounter_preview,
		completed
	)
