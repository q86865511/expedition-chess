class_name BattleRunOperationRule
extends RefCounted

var operation_index: int
var kind: StringName
var amount: int
var claim_scope: StringName

func deep_clone() -> BattleRunOperationRule:
	var copied := BattleRunOperationRule.new()
	copied.operation_index = operation_index
	copied.kind = kind
	copied.amount = amount
	copied.claim_scope = claim_scope
	return copied
