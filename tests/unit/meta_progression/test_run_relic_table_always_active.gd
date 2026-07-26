extends GutTest

## T06(specs/meta-progression) — RunRelicTable.sum_always_active/always_active_count。
## Covers：S5-AC-003；tasks.md T06 驗收：「RunRelicTable.sum_always_active(category,kind)/
## always_active_count(category)」。
## 依據 design.md §6.1:117：「RunRelicTable 加 sum_always_active(category, kind)／
## always_active_count(category)：對 source∈{commander,challenge} 規則無條件加總
## （不看 slot）」。
##
## 範圍聲明：本檔直接建構 RunRelicTable(不經 RunRelicTableBuilder/RunModifierTableBuilder/
## 內容註冊),只鎖 RunRelicTable 這兩個新方法本身的彙整語意——是否正確從內容解析出
## source=commander/challenge 的規則屬 test_run_modifier_table_builder.gd；四個消費端
## 是否正確疊加 always-active 貢獻於既有 slot-gated 之上屬另外四個
## test_*_commander_challenge_modifiers.gd。
##
## 假設聲明：sum_always_active/always_active_count 的簽名只有 (category[, kind])——
## 不接受 active_relic_ids,因為「無條件」正是其與既有 sum_operation_amount/active_count
## (兩者都要求呼叫端傳入 active_relic_ids 做槽位過濾)的核心差異。本檔以「完全不傳入任何
## slot/active id 資訊」的呼叫方式驗證這點。

const _DIGEST := "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

func test_sum_always_active_includes_commander_sourced_rule() -> void:
	var table := RunRelicTable.new(_DIGEST, [
		_rule(&"commander.fixture", &"commander", &"economy", &"add_gold", 7),
	])
	assert_eq(table.sum_always_active(&"economy", &"add_gold"), 7)

func test_sum_always_active_includes_challenge_sourced_rule() -> void:
	var table := RunRelicTable.new(_DIGEST, [
		_rule(&"challenge.fixture", &"challenge", &"economy", &"add_gold", 3),
	])
	assert_eq(table.sum_always_active(&"economy", &"add_gold"), 3)

func test_sum_always_active_sums_commander_and_challenge_together() -> void:
	var table := RunRelicTable.new(_DIGEST, [
		_rule(&"commander.fixture", &"commander", &"economy", &"add_gold", 7),
		_rule(&"challenge.fixture", &"challenge", &"economy", &"add_gold", 3),
	])
	assert_eq(table.sum_always_active(&"economy", &"add_gold"), 10)

func test_sum_always_active_excludes_relic_sourced_rule_even_with_matching_category_and_kind() -> void:
	var table := RunRelicTable.new(_DIGEST, [
		_rule(&"relic.fixture", &"relic", &"economy", &"add_gold", 100),
		_rule(&"commander.fixture", &"commander", &"economy", &"add_gold", 7),
	])
	assert_eq(
		table.sum_always_active(&"economy", &"add_gold"), 7,
		"relic 來源(即使 category/kind 相符)不得混入 always-active 加總——" +
		"避免與既有 sum_operation_amount 重複計入"
	)

func test_sum_always_active_excludes_default_source_rule_built_without_explicit_source() -> void:
	# 未顯式設定 .source 的規則(既有 RunRelicTableBuilder 產物的真實形狀)必須維持
	# relic 語意、被 always-active 彙整排除。
	var default_rule := RunRelicRule.new()
	default_rule.relic_id = &"relic.default"
	default_rule.category = &"economy"
	var operation := RunRelicOperationRule.new()
	operation.operation_index = 0
	operation.kind = &"add_gold"
	operation.amount = 50
	operation.claim_scope = &"always"
	default_rule.run_operations = [operation]
	var table := RunRelicTable.new(_DIGEST, [default_rule])
	assert_eq(table.sum_always_active(&"economy", &"add_gold"), 0)

func test_sum_always_active_filters_by_category() -> void:
	var table := RunRelicTable.new(_DIGEST, [
		_rule(&"commander.fixture", &"commander", &"rule", &"heal_expedition_hp", 5),
	])
	assert_eq(table.sum_always_active(&"economy", &"add_gold"), 0, "category 不符不應計入")
	assert_eq(table.sum_always_active(&"rule", &"heal_expedition_hp"), 5)

func test_sum_always_active_filters_by_kind_within_same_category() -> void:
	var table := RunRelicTable.new(_DIGEST, [
		_rule(&"commander.fixture", &"commander", &"economy", &"shop_discount", 4),
	])
	assert_eq(table.sum_always_active(&"economy", &"add_gold"), 0, "kind 不符不應計入")
	assert_eq(table.sum_always_active(&"economy", &"shop_discount"), 4)

func test_sum_always_active_on_empty_table_is_zero() -> void:
	var table := RunRelicTable.new(_DIGEST, [])
	assert_eq(table.sum_always_active(&"economy", &"add_gold"), 0)

func test_sum_always_active_does_not_depend_on_any_slot_or_active_id_information() -> void:
	# 無條件彙整的核心證據:即使把「作用中遺物」相關的呼叫端資訊完全排除在測試情境外
	# (本檔從未建構 active_relic_ids/RelicSlotState),commander/challenge 規則仍然生效。
	var table := RunRelicTable.new(_DIGEST, [
		_rule(&"commander.fixture", &"commander", &"economy", &"add_gold", 9),
	])
	assert_eq(table.sum_always_active(&"economy", &"add_gold"), 9)
	assert_eq(
		table.sum_always_active(&"economy", &"add_gold"), 9,
		"重複呼叫應得到相同結果(純函式式查詢、無隱藏狀態)"
	)

func test_always_active_count_counts_commander_and_challenge_rules_for_category() -> void:
	var table := RunRelicTable.new(_DIGEST, [
		_rule(&"commander.fixture", &"commander", &"route", &"add_gold", 0),
		_rule(&"challenge.fixture", &"challenge", &"route", &"add_gold", 0),
	])
	assert_eq(table.always_active_count(&"route"), 2)

func test_always_active_count_excludes_relic_sourced_rules() -> void:
	var table := RunRelicTable.new(_DIGEST, [
		_rule(&"relic.route_a", &"relic", &"route", &"add_gold", 0),
		_rule(&"relic.route_b", &"relic", &"route", &"add_gold", 0),
		_rule(&"commander.fixture", &"commander", &"route", &"add_gold", 0),
	])
	assert_eq(
		table.always_active_count(&"route"), 1,
		"兩個 relic 來源不得計入 always_active_count,只有 commander 那 1 筆算數"
	)

func test_always_active_count_filters_by_category() -> void:
	var table := RunRelicTable.new(_DIGEST, [
		_rule(&"commander.fixture", &"commander", &"economy", &"add_gold", 1),
	])
	assert_eq(table.always_active_count(&"route"), 0)
	assert_eq(table.always_active_count(&"economy"), 1)

func test_always_active_count_on_empty_table_is_zero() -> void:
	var table := RunRelicTable.new(_DIGEST, [])
	assert_eq(table.always_active_count(&"route"), 0)

func _rule(
	source_id: StringName, source: StringName, category: StringName,
	kind: StringName, amount: int
) -> RunRelicRule:
	var operation := RunRelicOperationRule.new()
	operation.operation_index = 0
	operation.kind = kind
	operation.amount = amount
	operation.claim_scope = &"always"
	var rule := RunRelicRule.new()
	rule.relic_id = source_id
	rule.category = category
	rule.source = source
	rule.effect_ids = [&"effect.fixture"]
	rule.run_operations = [operation]
	return rule
