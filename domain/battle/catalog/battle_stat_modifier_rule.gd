class_name BattleStatModifierRule
extends RefCounted

var stat: StringName
var mode: StringName
var amount: int

func deep_clone() -> BattleStatModifierRule:
	var copied := BattleStatModifierRule.new()
	copied.stat = stat
	copied.mode = mode
	copied.amount = amount
	return copied
