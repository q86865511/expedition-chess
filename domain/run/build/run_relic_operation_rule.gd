class_name RunRelicOperationRule
extends RefCounted

var operation_index: int
var kind: StringName
var amount: int
var claim_scope: StringName
## 來源 effect 的 stable id（builder 解碼時填入，見 run_relic_table_builder.gd
## _append_effect_run_operations）。claim key 消費端（BattleSettlementService）用它消歧
## 同一遺物內、不同 effect_refs 但 operation_index 相同的 operation——operation_index 只在
## 單一 effect 內唯一（content_validator.gd:691-693），不足以單獨識別（W3-F4 修正）。
var effect_id: StringName

func deep_clone() -> RunRelicOperationRule:
	var copied := RunRelicOperationRule.new()
	copied.operation_index = operation_index
	copied.kind = kind
	copied.amount = amount
	copied.claim_scope = claim_scope
	copied.effect_id = effect_id
	return copied
