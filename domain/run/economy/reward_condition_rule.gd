class_name RewardConditionRule
extends RefCounted

var kind: StringName
var int_value: int
var stable_id_value: OptionalStringNameValue

func _init(
	p_kind: StringName,
	p_int_value: int,
	p_stable_id_value: OptionalStringNameValue = null
) -> void:
	kind = p_kind
	int_value = p_int_value
	stable_id_value = (
		p_stable_id_value.deep_clone() if p_stable_id_value != null else null
	)

func deep_clone() -> RewardConditionRule:
	return RewardConditionRule.new(kind, int_value, stable_id_value)
