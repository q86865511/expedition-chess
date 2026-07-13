class_name MapState
extends RefCounted

var nodes: Array[MapNodeState] = []
var edges: Array[MapEdgeState] = []
var current_node_id: OptionalStringValue
var completed_node_ids: Array[String] = []

func _init(
	p_nodes: Array[MapNodeState],
	p_edges: Array[MapEdgeState],
	p_current_node_id: OptionalStringValue,
	p_completed_node_ids: Array[String]
) -> void:
	for node: MapNodeState in p_nodes:
		nodes.append(node.deep_clone())
	for edge: MapEdgeState in p_edges:
		edges.append(edge.deep_clone())
	current_node_id = p_current_node_id.deep_clone() if p_current_node_id != null else null
	completed_node_ids.assign(p_completed_node_ids)

func deep_clone() -> MapState:
	return MapState.new(nodes, edges, current_node_id, completed_node_ids)
