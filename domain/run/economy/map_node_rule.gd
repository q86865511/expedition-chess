class_name MapNodeRule
extends RefCounted

var definition_id: StringName
var node_kind: MapNodeState.NodeKind
var generator_id: StringName

func _init(
	p_definition_id: StringName,
	p_node_kind: MapNodeState.NodeKind,
	p_generator_id: StringName = &""
) -> void:
	definition_id = p_definition_id
	node_kind = p_node_kind
	generator_id = p_generator_id

func deep_clone() -> MapNodeRule:
	return MapNodeRule.new(definition_id, node_kind, generator_id)
