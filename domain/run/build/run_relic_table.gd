class_name RunRelicTable
extends RefCounted

var _manifest_digest: String
var _rules: Array[RunRelicRule] = []

func _init(manifest_digest: String, rules: Array[RunRelicRule]) -> void:
	_manifest_digest = manifest_digest
	for value: RunRelicRule in rules:
		_rules.append(value.deep_clone())

func manifest_digest_value() -> String:
	return _manifest_digest

func rules_for_category(category: StringName) -> Array[RunRelicRule]:
	var result: Array[RunRelicRule] = []
	for value: RunRelicRule in _rules:
		if value.category == category:
			result.append(value.deep_clone())
	return result

func try_relic_rule(relic_id: StringName) -> RunRelicRule:
	for value: RunRelicRule in _rules:
		if value.relic_id == relic_id:
			return value.deep_clone()
	return null

## 依呼叫端傳入的 id 順序回傳對應規則（呼叫端負責依 slot_index 升序排列，見
## RunRelicActivation）。找不到的 id 靜默略過，不報錯、不中斷。回傳的是深拷貝，
## 呼叫端修改不會污染表內狀態。
func ordered_rules(active_relic_ids: Array[StringName]) -> Array[RunRelicRule]:
	var result: Array[RunRelicRule] = []
	for relic_id: StringName in active_relic_ids:
		var rule := try_relic_rule(relic_id)
		if rule != null:
			result.append(rule)
	return result

## 指定 category、kind 的 run_operation.amount 加總，依作用中遺物的槽序（呼叫端傳入序）。
func sum_operation_amount(
	active_relic_ids: Array[StringName], category: StringName, kind: StringName
) -> int:
	var total := 0
	for rule: RunRelicRule in ordered_rules(active_relic_ids):
		if rule.category != category:
			continue
		for operation: RunRelicOperationRule in rule.run_operations:
			if operation.kind == kind:
				total += operation.amount
	return total

## 指定 category 的作用中遺物數量（依槽序），供路線遺物佔用 anchor 使用。
func active_count(active_relic_ids: Array[StringName], category: StringName) -> int:
	var count := 0
	for rule: RunRelicRule in ordered_rules(active_relic_ids):
		if rule.category == category:
			count += 1
	return count

func deep_clone() -> RunRelicTable:
	return RunRelicTable.new(_manifest_digest, _rules)
