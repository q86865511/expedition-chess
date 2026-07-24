class_name RunRelicRule
extends RefCounted

var relic_id: StringName
var category: StringName
## 規則來源。既有 RunRelicTableBuilder 產物與 S4 呼叫端從不設定本欄，故預設 &"relic"
## （slot-gated 語意，維持既有行為）。指揮官被動＝&"commander"、挑戰詞綴＝&"challenge"，
## 兩者為 always-active（不看 slot），由 RunRelicTable.sum_always_active/always_active_count
## 無條件加總（design §6.1、S5-AC-003）。
var source: StringName = &"relic"
var effect_ids: Array[StringName] = []
var run_operations: Array[RunRelicOperationRule] = []

func deep_clone() -> RunRelicRule:
	var copied := RunRelicRule.new()
	copied.relic_id = relic_id
	copied.category = category
	copied.source = source
	copied.effect_ids = effect_ids.duplicate()
	for operation: RunRelicOperationRule in run_operations:
		copied.run_operations.append(operation.deep_clone())
	return copied
