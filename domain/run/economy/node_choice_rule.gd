class_name NodeChoiceRule
extends RefCounted

const OUTCOME_APPLY_AND_COMPLETE := 1
const OUTCOME_OPEN_DISMANTLE_SERVICE := 2
const OUTCOME_OPEN_REWARD_STAGE := 3

var choice_id: StringName
var sort_order: int
var title_key: StringName
var description_key: StringName
var preview_key: StringName
var result_key: StringName
var operations: Array[NodeChoiceOperationRule] = []
var reward_table_ref: StringName
var has_reward_table_ref: bool
var outcome_kind: int
var confirmation_required: bool


func _init(
	p_choice_id: StringName,
	p_sort_order: int,
	p_title_key: StringName,
	p_description_key: StringName,
	p_preview_key: StringName,
	p_result_key: StringName,
	p_operations: Array[NodeChoiceOperationRule],
	p_reward_table_ref: StringName,
	p_has_reward_table_ref: bool,
	p_outcome_kind: int,
	p_confirmation_required: bool
) -> void:
	choice_id = p_choice_id
	sort_order = p_sort_order
	title_key = p_title_key
	description_key = p_description_key
	preview_key = p_preview_key
	result_key = p_result_key
	for operation: NodeChoiceOperationRule in p_operations:
		operations.append(operation.deep_clone())
	reward_table_ref = p_reward_table_ref
	has_reward_table_ref = p_has_reward_table_ref
	outcome_kind = p_outcome_kind
	confirmation_required = p_confirmation_required


func deep_clone() -> NodeChoiceRule:
	return NodeChoiceRule.new(
		choice_id,
		sort_order,
		title_key,
		description_key,
		preview_key,
		result_key,
		operations,
		reward_table_ref,
		has_reward_table_ref,
		outcome_kind,
		confirmation_required
	)
