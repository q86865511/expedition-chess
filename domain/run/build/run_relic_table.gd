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

## source∈{commander,challenge} 規則（指揮官被動／挑戰詞綴）對指定 category、kind 的
## run_operation.amount 無條件加總——不看 slot、不需 active_relic_ids，與 slot-gated 的
## sum_operation_amount 互補。各 run 層消費端在既有 slot-gated 加總後再加本方法貢獻
## （design §6.1、S5-AC-003）。relic 來源即使 category/kind 相符也不計入（避免與
## sum_operation_amount 重複）。
func sum_always_active(category: StringName, kind: StringName) -> int:
	var total := 0
	for rule: RunRelicRule in _always_active_rules():
		if rule.category != category:
			continue
		for operation: RunRelicOperationRule in rule.run_operations:
			if operation.kind == kind:
				total += operation.amount
	return total

## source∈{commander,challenge} 且指定 category 的規則數量（無條件、不看 slot），供路線被動
## 佔用 branch anchor（MapService 在 active_count 之上再加本方法貢獻）。
func always_active_count(category: StringName) -> int:
	var count := 0
	for rule: RunRelicRule in _always_active_rules():
		if rule.category == category:
			count += 1
	return count

## 表內所有規則的深拷貝，供 RunModifierTableBuilder 在既有 relic 規則之上疊加 commander/
## challenge 規則後重建擴充表。一般消費端請用具語意的查詢方法（sum_*/active_count/…），
## 勿依賴此原始清單。
func all_rules() -> Array[RunRelicRule]:
	var result: Array[RunRelicRule] = []
	for value: RunRelicRule in _rules:
		result.append(value.deep_clone())
	return result

## always-active（source∈{commander,challenge}）規則，依決定性順序：commander 先於
## challenge，同來源內依 effect_id 字典序（design §6.1：slot 升序→commander→challenge；
## 規則以首個 effect_id 為鍵，同鍵以 relic_id 決勝）。無條件加總滿足交換律，排序不影響
## sum_always_active/always_active_count 的數值結果，僅為決定性與可讀性。
## 回傳表內規則的直接引用（本方法僅供內部唯讀彙整，不對外回傳）。
func _always_active_rules() -> Array[RunRelicRule]:
	var commander_rules: Array[RunRelicRule] = []
	var challenge_rules: Array[RunRelicRule] = []
	for value: RunRelicRule in _rules:
		if value.source == &"commander":
			commander_rules.append(value)
		elif value.source == &"challenge":
			challenge_rules.append(value)
	commander_rules.sort_custom(_source_rule_before)
	challenge_rules.sort_custom(_source_rule_before)
	var result: Array[RunRelicRule] = []
	result.append_array(commander_rules)
	result.append_array(challenge_rules)
	return result

func _source_rule_before(left: RunRelicRule, right: RunRelicRule) -> bool:
	var left_key := String(left.effect_ids[0]) if not left.effect_ids.is_empty() else String(left.relic_id)
	var right_key := String(right.effect_ids[0]) if not right.effect_ids.is_empty() else String(right.relic_id)
	if left_key == right_key:
		return String(left.relic_id) < String(right.relic_id)
	return left_key < right_key

func deep_clone() -> RunRelicTable:
	return RunRelicTable.new(_manifest_digest, _rules)
