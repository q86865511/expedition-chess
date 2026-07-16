class_name BattleConditionRule
extends RefCounted

var kind: StringName
var subject: StringName
var comparator: StringName
var int_value: OptionalIntValue
var stable_id_value: OptionalStringNameValue
var max_uses_per_battle: OptionalIntValue

func deep_clone() -> BattleConditionRule:
	var copied := BattleConditionRule.new()
	copied.kind = kind
	copied.subject = subject
	copied.comparator = comparator
	copied.int_value = int_value.deep_clone() if int_value != null else null
	copied.stable_id_value = stable_id_value.deep_clone() if stable_id_value != null else null
	copied.max_uses_per_battle = max_uses_per_battle.deep_clone() if max_uses_per_battle != null else null
	return copied
