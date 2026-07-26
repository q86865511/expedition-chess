extends GutTest

## T06(specs/meta-progression) — RunRelicRule.source 欄位（指揮官/挑戰 always-active 標記地基）。
## Covers：S5-AC-003；tasks.md T06 驗收：「RunRelicRule.source（預設 relic）」。
## 依據 design.md §6.1:117「RunRelicRule 加 source: StringName（預設 &"relic"）」與
## §2 版本策略表「RunRelicTable 1（擴充）| RunRelicRule 新增 source（relic/commander/challenge）」。
##
## 範圍聲明：本檔只鎖 RunRelicRule 這個資料型別本身（欄位預設值、可設定性、deep_clone 保真）。
## RunRelicTable.sum_always_active/always_active_count 的彙整語意見同目錄
## test_run_relic_table_always_active.gd；四個 run 層消費端見對應
## test_income_service_commander_challenge_modifiers.gd 等四檔。
##
## 假設聲明：現有 domain/run/build/run_relic_table_builder.gd 的 build() 建立
## RunRelicRule.new() 後從未設定 .source，S4 既有測試(test_run_relic_table_operations.gd 等)
## 建構 RunRelicRule 時也從未提供 source——這些既有呼叫端必須在不修改任何一行的前提下
## 繼續正確運作(遺物規則必須被 sum_always_active/always_active_count 排除)，因此
## 「預設值 == &"relic"」是可從既有程式碼零修改的前提反推的硬性事實，非本檔臆測。

func test_source_defaults_to_relic_when_not_set() -> void:
	var rule := RunRelicRule.new()
	assert_eq(
		rule.source, &"relic",
		"未設定 source 的既有呼叫端(RunRelicTableBuilder 等)必須維持 relic 語意"
	)

func test_source_can_be_set_to_commander() -> void:
	var rule := RunRelicRule.new()
	rule.source = &"commander"
	assert_eq(rule.source, &"commander")

func test_source_can_be_set_to_challenge() -> void:
	var rule := RunRelicRule.new()
	rule.source = &"challenge"
	assert_eq(rule.source, &"challenge")

func test_deep_clone_preserves_explicit_source() -> void:
	var rule := RunRelicRule.new()
	rule.relic_id = &"commander.fixture"
	rule.category = &"economy"
	rule.source = &"commander"
	var operation := RunRelicOperationRule.new()
	operation.operation_index = 0
	operation.kind = &"add_gold"
	operation.amount = 5
	operation.claim_scope = &"always"
	rule.run_operations = [operation]
	var cloned := rule.deep_clone()
	assert_eq(
		cloned.source, &"commander",
		"deep_clone 必須保真複製 source,否則經 RunRelicTable._init/try_relic_rule/" +
		"ordered_rules 的既有 deep_clone 管線會讓 always-active 標記在建表當下就遺失"
	)
	assert_eq(cloned.category, &"economy")
	assert_eq(cloned.run_operations.size(), 1)

func test_deep_clone_preserves_default_relic_source() -> void:
	var rule := RunRelicRule.new()
	rule.relic_id = &"relic.fixture"
	var cloned := rule.deep_clone()
	assert_eq(cloned.source, &"relic")

func test_run_relic_table_constructor_preserves_source_through_its_internal_deep_clone() -> void:
	# RunRelicTable._init 對傳入的每個 rule 立即呼叫 deep_clone()——這是本檔與
	# test_run_relic_table_always_active.gd 所有「直接建表」測試共同依賴的地基事實：
	# 若 deep_clone 不保真 source,經 RunRelicTable.new(...) 建表後 always-active 規則
	# 會被靜默重置為 relic、from 建表當下就無法被 sum_always_active 找到。
	var commander_rule := RunRelicRule.new()
	commander_rule.relic_id = &"commander.fixture"
	commander_rule.category = &"economy"
	commander_rule.source = &"commander"
	var operation := RunRelicOperationRule.new()
	operation.operation_index = 0
	operation.kind = &"add_gold"
	operation.amount = 5
	operation.claim_scope = &"always"
	commander_rule.run_operations = [operation]
	var table := RunRelicTable.new(
		"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", [commander_rule]
	)
	var fetched := table.try_relic_rule(&"commander.fixture")
	assert_not_null(fetched)
	if fetched == null:
		return
	assert_eq(fetched.source, &"commander")
