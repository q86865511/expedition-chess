class_name NodeServiceOverlaySnapshot
extends RefCounted

## design.md §5（:208-214）：node service 期間 UI 需要的三個 identity 欄位——
## 服務內拆解與離場命令都必須原樣帶回它們才拿得到 service authority。
## 與 NodeChoiceOverlaySnapshot 同樣是 deep clone 的 immutable 投影。

var service_kind: StringName
var node_id: StringName
var choice_receipt_digest: String


static func from_state(
	pending: NodeServicePendingResolutionState
) -> NodeServiceOverlaySnapshot:
	if pending == null:
		return null
	var result := NodeServiceOverlaySnapshot.new()
	result.service_kind = pending.service_kind
	result.node_id = pending.node_id
	result.choice_receipt_digest = pending.choice_receipt_digest
	return result


func deep_clone() -> NodeServiceOverlaySnapshot:
	var clone := NodeServiceOverlaySnapshot.new()
	clone.service_kind = service_kind
	clone.node_id = node_id
	clone.choice_receipt_digest = choice_receipt_digest
	return clone
