class_name NodeChoiceReceiptLedgerEntry
extends RefCounted

var receipt: NodeChoiceCommitReceiptState
var result_acknowledged: bool

func _init(
	p_receipt: NodeChoiceCommitReceiptState = null,
	p_result_acknowledged: bool = false
) -> void:
	receipt = p_receipt.deep_clone() if p_receipt != null else null
	result_acknowledged = p_result_acknowledged

func deep_clone() -> NodeChoiceReceiptLedgerEntry:
	return NodeChoiceReceiptLedgerEntry.new(receipt, result_acknowledged)
