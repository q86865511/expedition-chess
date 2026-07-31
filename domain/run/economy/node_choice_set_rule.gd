class_name NodeChoiceSetRule
extends RefCounted

var choice_set_id: StringName
var display_name_key: StringName
var node_kind: StringName
var choices: Array[NodeChoiceRule] = []


func _init(
	p_choice_set_id: StringName,
	p_display_name_key: StringName,
	p_node_kind: StringName,
	p_choices: Array[NodeChoiceRule]
) -> void:
	choice_set_id = p_choice_set_id
	display_name_key = p_display_name_key
	node_kind = p_node_kind
	for choice: NodeChoiceRule in p_choices:
		choices.append(choice.deep_clone())


func try_choice(choice_id: StringName) -> NodeChoiceRule:
	for choice: NodeChoiceRule in choices:
		if choice.choice_id == choice_id:
			return choice.deep_clone()
	return null


func deep_clone() -> NodeChoiceSetRule:
	return NodeChoiceSetRule.new(
		choice_set_id, display_name_key, node_kind, choices
	)
