class_name NodeChoiceResultSnapshot
extends RefCounted

## design.md §5（:201-205）：「UI 只由 unacknowledged committed receipt 顯示 result」。
## 本投影因此只由 result_acknowledged=false 的 ledger entry 產生；玩家看完結果後由
## AcknowledgeNodeChoiceResultCommand 帶著同一個 receipt_digest 翻旗標。
## reload 後 false receipt 會再次出現，這就是 R4「post-commit route failure／reload
## 重播」的機制。

var node_id: StringName
var choice_set_id: StringName
var choice_id: StringName
var result_key: StringName
var outcome_kind: int
var receipt_digest: String


static func from_receipt(
	receipt: NodeChoiceCommitReceiptState
) -> NodeChoiceResultSnapshot:
	if receipt == null:
		return null
	var result := NodeChoiceResultSnapshot.new()
	result.node_id = receipt.node_id
	result.choice_set_id = receipt.choice_set_id
	result.choice_id = receipt.choice_id
	result.result_key = receipt.result_key
	result.outcome_kind = receipt.outcome_kind
	result.receipt_digest = receipt.receipt_digest
	return result


func deep_clone() -> NodeChoiceResultSnapshot:
	var clone := NodeChoiceResultSnapshot.new()
	clone.node_id = node_id
	clone.choice_set_id = choice_set_id
	clone.choice_id = choice_id
	clone.result_key = result_key
	clone.outcome_kind = outcome_kind
	clone.receipt_digest = receipt_digest
	return clone
