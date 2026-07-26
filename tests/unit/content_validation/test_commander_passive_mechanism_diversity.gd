extends GutTest

## T10 (specs/meta-progression) — 三名指揮官被動非同一效果的數值階級（架構規格
## docs/game-architecture/04-content-and-meta-progression.md:81「三名指揮官的優勢不得只是
## 相同被動的數值階級」；design.md §7.2「三指揮官被動非同一效果數值階級（§7.2 硬約束）」；
## tasks.md T10 驗收欄「三被動非同一效果數值階級」）：新增 ContentValidator 規則，偵測「三名
## 指揮官的 passive_effect_refs 解析出的機制完全相同（同一組 operation 型別），只是數值不同」
## 的違規內容。
##
## ============================== 假設聲明（design 未釘死具體判準，測試作者裁決） ==============================
## 1. 「機制簽章」定義：對每個 CommanderDef，蒐集其 passive_effect_refs 逐一解析到的
##    EffectDef，聯集其 battle_operations ∪ run_operations 每個 operation 的
##    operation_type()（int，各 *OperationDef 子類唯一，如 AddGoldOperationDef=0x3101／
##    HealExpeditionHpOperationDef=0x3103／ModifyStatOperationDef=0x3004——沿用專案既有
##    慣例，這些整數碼已是區分 operation「機制種類」的權威判準），得到一個 operation_type
##    值的集合（忽略 amount/duration 等數值欄位——「只有數值不同」正是本規則要放行的差異，
##    不能拿數值欄位當判準）。
## 2. 觸發條件：內容集合中若恰有 3 個 CommanderDef（對齊 CONTENT_MINIMUM_COUNTS 對
##    commanders 數量的既有硬性要求，恆為 3），且三者的機制簽章集合三者兩兩相等（完全一樣的
##    operation_type 集合）→ 新 issue code CONTENT_COMMANDER_PASSIVE_HOMOGENEOUS（本檔
##    發明，design/tasks 未指定字面 code；語意等價即可，非逐字比對）。少於 3 個 CommanderDef
##    或三者簽章不完全相同（即使只有 1 個不同）時不觸發——「不得只是相同被動的數值階級」的
##    最直接讀法是「三者若真的完全同機制」才違規；2 同 1 異等更細緻的部分重疊判準留給實作
##    代理裁量，本檔不強制規定（untestable 原因見回報）。
## 3. 【重大風險，務必在派工回報中轉達】tests/fixtures/content/synthetic_content_fixture.gd
##    的 SyntheticContentFixture._commander()（:382-395）目前讓 index 0/1/2 三個 commander
##    的 passive_effect_refs 全部指向同一個 &"effect.general"（該效果 battle_operations 與
##    run_operations 皆為空陣列，見 _effect() helper :139-147，未額外賦值 operations）——
##    三者機制簽章按本檔判準（空集合 == 空集合）視為「完全相同」，比「只有數值不同」更
##    degenerate（連數值都沒有，直接是同一份定義）。若實作代理依本檔判準原樣實作此規則並
##    套用到 SyntheticContentFixture.build_valid()，會讓該基準本身變成不合規，進而讓所有
##    依賴「SyntheticContentFixture.build_valid() 應通過驗證/安裝」的既有測試轉紅——這個
##    數量遠超「3 處」，包含但不限於 test_content_validator.gd 的
##    test_valid_vertical_slice_and_population_reports，以及 tests/unit/meta_progression/
##    下大量呼叫 registry.install_validated(SyntheticContentFixture.build_valid(), ...) 並
##    期望 installed.ok 的測試。本檔測試作者已刻意避開 SyntheticContentFixture（見下方
##    _minimal_three_commander_input()，完全自建、不依賴共用 fixture），確保**本檔自身**的
##    紅燈只反映「規則尚未實作」，不被這個既有缺口污染；但這個更大範圍的衝突需要實作代理與
##    orchestrator 協調（多半必須同步修改 SyntheticContentFixture 讓三個 commander 使用不同
##    operation 型別的 passive，例如比照 content/packs/vertical_slice/commanders/ 真實內容
##    c0=AddGold／c1=HealExpeditionHp／c2=ModifyStat 的既有分工），不是本檔測試作者能片面
##    決定或處理的事。
## ==============================================================================================================

func test_three_commanders_with_identical_single_operation_passives_is_rejected() -> void:
	var input := _minimal_three_commander_input()
	_append_add_gold_effect(input, &"effect.c0_passive", 1)
	_append_add_gold_effect(input, &"effect.c1_passive", 2)
	_append_add_gold_effect(input, &"effect.c2_passive", 3)
	_set_passive(input, &"commander.c0", &"effect.c0_passive")
	_set_passive(input, &"commander.c1", &"effect.c1_passive")
	_set_passive(input, &"commander.c2", &"effect.c2_passive")

	var report := ContentValidator.new().validate(input)

	assert_true(
		_has_issue(report, &"CONTENT_COMMANDER_PASSIVE_HOMOGENEOUS"),
		"三名指揮官被動皆為 AddGoldOperationDef（只有 amount 不同）必須被拒絕: %s" % _issue_text(report)
	)


func test_three_commanders_with_distinct_mechanisms_is_accepted() -> void:
	var input := _minimal_three_commander_input()
	_append_add_gold_effect(input, &"effect.c0_passive_gold", 1)
	_append_heal_expedition_hp_effect(input, &"effect.c1_passive_heal", 1)
	_append_modify_stat_effect(input, &"effect.c2_passive_modify_stat")
	_set_passive(input, &"commander.c0", &"effect.c0_passive_gold")
	_set_passive(input, &"commander.c1", &"effect.c1_passive_heal")
	_set_passive(input, &"commander.c2", &"effect.c2_passive_modify_stat")

	var report := ContentValidator.new().validate(input)

	assert_false(
		_has_issue(report, &"CONTENT_COMMANDER_PASSIVE_HOMOGENEOUS"),
		(
			"三名指揮官各自不同機制（add_gold／heal／modify_stat）不應被拒絕（正對照組，"
			+ "對齊真實內容 c0/c1/c2 的既有分工）: %s"
		) % _issue_text(report)
	)


func _minimal_three_commander_input() -> ContentValidationInput:
	var definitions: Array[ContentDefinition] = []
	for index in 3:
		var commander := CommanderDef.new()
		commander.id = StringName("commander.c%d" % index)
		commander.display_name_key = StringName("loc.commander_c%d" % index)
		commander.population_bonus = 0
		definitions.append(commander)
	return ContentValidationInput.new(definitions, [], [], FakeContentDependencyPort.new(), 9)


func _set_passive(input: ContentValidationInput, commander_id: StringName, effect_id: StringName) -> void:
	var commander := _find(input, commander_id) as CommanderDef
	assert_not_null(commander)
	if commander == null:
		return
	commander.passive_effect_refs = [effect_id]


func _append_add_gold_effect(input: ContentValidationInput, effect_id: StringName, amount: int) -> void:
	var operation := AddGoldOperationDef.new()
	operation.operation_index = 0
	operation.amount = amount
	operation.claim_scope = &"always"
	var run_operations: Array[RunOperationDef] = [operation]
	_append_effect_with_run_ops(input, effect_id, run_operations)


func _append_heal_expedition_hp_effect(input: ContentValidationInput, effect_id: StringName, amount: int) -> void:
	var operation := HealExpeditionHpOperationDef.new()
	operation.operation_index = 0
	operation.amount = amount
	operation.claim_scope = &"always"
	var run_operations: Array[RunOperationDef] = [operation]
	_append_effect_with_run_ops(input, effect_id, run_operations)


func _append_modify_stat_effect(input: ContentValidationInput, effect_id: StringName) -> void:
	var effect := EffectDef.new()
	effect.id = effect_id
	effect.display_name_key = StringName("loc.%s" % String(effect_id))
	effect.content_role = &"general"
	effect.trigger = &"battle_start"
	effect.stacking = &"replace"
	effect.max_stacks = 1
	effect.duration_ticks = 20
	var operation := ModifyStatOperationDef.new()
	operation.operation_index = 0
	operation.stat = &"attack"
	operation.mode = &"flat"
	operation.amount = 1
	operation.duration_ticks = 20
	operation.target = &"self"
	effect.battle_operations = [operation]
	input.definitions.append(effect)


func _append_effect_with_run_ops(
	input: ContentValidationInput, effect_id: StringName, run_operations: Array[RunOperationDef]
) -> void:
	var effect := EffectDef.new()
	effect.id = effect_id
	effect.display_name_key = StringName("loc.%s" % String(effect_id))
	effect.content_role = &"general"
	effect.trigger = &"battle_start"
	effect.stacking = &"replace"
	effect.max_stacks = 1
	effect.duration_ticks = 1
	effect.run_operations = run_operations
	input.definitions.append(effect)


func _find(input: ContentValidationInput, content_id: StringName) -> ContentDefinition:
	for definition: ContentDefinition in input.definitions:
		if definition.id == content_id:
			return definition
	return null


func _has_issue(report: ContentValidationReport, code: StringName) -> bool:
	for issue: ContentValidationIssue in report.issues:
		if issue.code == code:
			return true
	return false


func _issue_text(report: ContentValidationReport) -> String:
	var values: Array[String] = []
	for issue: ContentValidationIssue in report.issues:
		values.append("%s:%s:%s" % [issue.code, issue.source_id, issue.field_path])
	return ", ".join(values)
