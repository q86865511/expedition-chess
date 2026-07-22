class_name RewardCandidateRule
extends RefCounted

var kind: StringName
var content_id: OptionalStringNameValue
var weight: int
var amount: int
var conditions: Array[RewardConditionRule] = []

func _init(
	p_kind: StringName,
	p_content_id: OptionalStringNameValue,
	p_weight: int,
	p_amount: int = 1,
	p_conditions: Array[RewardConditionRule] = []
) -> void:
	kind = p_kind
	content_id = p_content_id.deep_clone() if p_content_id != null else null
	weight = p_weight
	amount = p_amount
	for condition: RewardConditionRule in p_conditions:
		conditions.append(condition.deep_clone())

func deep_clone() -> RewardCandidateRule:
	return RewardCandidateRule.new(kind, content_id, weight, amount, conditions)
