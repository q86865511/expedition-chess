class_name MapNodePresentation
extends RefCounted

var node_id: String
var def_id: StringName
var act_index: int
var layer_index: int
var slot_index: int
var kind: StringName
var completed: bool
var reachable: bool
var encounter_preview: EncounterPreviewSnapshot


func _init(
	p_node_id: String,
	p_def_id: StringName,
	p_act_index: int,
	p_layer_index: int,
	p_slot_index: int,
	p_kind: StringName,
	p_completed: bool,
	p_reachable: bool,
	p_encounter_preview: EncounterPreviewSnapshot
) -> void:
	node_id = p_node_id
	def_id = p_def_id
	act_index = p_act_index
	layer_index = p_layer_index
	slot_index = p_slot_index
	kind = p_kind
	completed = p_completed
	reachable = p_reachable
	encounter_preview = (
		p_encounter_preview.deep_clone() if p_encounter_preview != null else null
	)


## Pure map-graph rule shared between RunPresentationSession and presentation
## screens: a node is reachable iff it is not already completed and either it
## is the act-1/layer-0 entry node with nothing completed yet, or an edge
## connects it from an already-completed node. Lives here (presentation/run,
## exempt from the PUI_SCREEN_WRITER_DEPENDENCY scan) so RunMapScreen can call
## it without importing RunPresentationSession, which the static gate treats
## as a canonical writer dependency for presentation/screens/*.gd.
static func is_reachable(map_state: MapState, node: MapNodeState) -> bool:
	if node.completed or map_state.completed_node_ids.has(node.node_id):
		return false
	if map_state.completed_node_ids.is_empty():
		return node.act_index == 1 and node.layer_index == 0
	for completed_id: String in map_state.completed_node_ids:
		for edge: MapEdgeState in map_state.edges:
			if edge.from_node_id == completed_id and edge.to_node_id == node.node_id:
				return true
	return false


static func from_state(
	state: MapNodeState,
	p_reachable: bool
) -> MapNodePresentation:
	return MapNodePresentation.new(
		state.node_id,
		state.def_id,
		state.act_index,
		state.layer_index,
		state.slot_index,
		MapNodeState.node_kind_to_token(state.node_kind),
		state.completed,
		p_reachable,
		state.encounter_preview
	)


func deep_clone() -> MapNodePresentation:
	return MapNodePresentation.new(
		node_id,
		def_id,
		act_index,
		layer_index,
		slot_index,
		kind,
		completed,
		reachable,
		encounter_preview
	)
