class_name NodeChoiceOperationRule
extends RefCounted

enum Kind {
	ADD_GOLD = 1,
	HEAL_EXPEDITION_HP = 2,
	DRAIN_EXPEDITION_HP = 3,
}

var kind: Kind
var amount: int
var operation_index: int
var claim_scope: StringName


func _init(
	p_kind: Kind,
	p_amount: int,
	p_operation_index: int,
	p_claim_scope: StringName
) -> void:
	kind = p_kind
	amount = p_amount
	operation_index = p_operation_index
	claim_scope = p_claim_scope


func deep_clone() -> NodeChoiceOperationRule:
	return NodeChoiceOperationRule.new(kind, amount, operation_index, claim_scope)
