class_name MapEdgeState
extends RefCounted

var from_node_id: String
var to_node_id: String

func _init(p_from_node_id: String, p_to_node_id: String) -> void:
	from_node_id = p_from_node_id
	to_node_id = p_to_node_id

func deep_clone() -> MapEdgeState:
	return MapEdgeState.new(from_node_id, to_node_id)
