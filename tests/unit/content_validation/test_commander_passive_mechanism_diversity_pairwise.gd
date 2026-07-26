extends GutTest

## S5 wave5 雙審 A6 修正（.pipeline/reviews/2026-07-25-reviewer-w5.md）：
## content_validator.gd 的 _validate_commander_passive_diversity() 判準原為「三者機制簽章
## 完全相同才拒」，與架構規格 04-content-and-meta-progression.md:81／design.md §7.2「三名
## 指揮官的優勢不得只是相同被動的數值階級」不符——「任兩名共用同一被動機制」就已是「相同被動
## 的數值階級」，不必等三者全同；且三者被動皆空（尚未著作）也會被舊判準誤判為「完全相同」而
## 誤觸發。本檔補三個裁定要求的新案例，鎖定測試
## tests/unit/content_validation/test_commander_passive_mechanism_diversity.gd 維持不動——
## 兩兩語意嚴格強於三者全同語意，該檔既有兩案例（三同觸發／三異不觸發）在新判準下維持相同
## 結果，不受影響。
##
## 本檔複用該鎖定測試檔的 _minimal_three_commander_input() 等 helper 寫法（自建、不依賴
## SyntheticContentFixture，避免被其被動內容基準污染），不修改鎖定檔本身。

func test_two_of_three_share_mechanism_one_distinct_is_rejected() -> void:
	var input := _minimal_three_commander_input()
	_append_add_gold_effect(input, &"effect.c0_passive", 1)
	_append_add_gold_effect(input, &"effect.c1_passive", 99)
	_append_heal_expedition_hp_effect(input, &"effect.c2_passive", 1)
	_set_passive(input, &"commander.c0", &"effect.c0_passive")
	_set_passive(input, &"commander.c1", &"effect.c1_passive")
	_set_passive(input, &"commander.c2", &"effect.c2_passive")

	var report := ContentValidator.new().validate(input)

	assert_true(
		_has_issue(report, &"CONTENT_COMMANDER_PASSIVE_HOMOGENEOUS"),
		(
			"c0/c1 皆為 AddGoldOperationDef（只有 amount 不同），c2 為 HealExpeditionHp——"
			+ "兩兩比對下 c0/c1 這一對已構成「相同被動的數值階級」，即使 c2 不同也必須拒絕: %s"
		) % _issue_text(report)
	)


func test_three_commanders_with_no_passives_at_all_is_accepted() -> void:
	var input := _minimal_three_commander_input()
	# 三名指揮官皆未著作任何 passive_effect_refs（維持 CommanderDef 預設空陣列）——
	# 三者機制簽章皆為空集合，空簽章不參與兩兩比對，不應觸發本規則（尚未著作被動屬另一層
	# 內容完整性問題，不是本規則的職責）。

	var report := ContentValidator.new().validate(input)

	assert_false(
		_has_issue(report, &"CONTENT_COMMANDER_PASSIVE_HOMOGENEOUS"),
		"三名指揮官皆無被動時空簽章不參與比對，不應誤判為同質: %s" % _issue_text(report)
	)


func test_three_commanders_all_pairwise_distinct_mechanisms_is_accepted() -> void:
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
		"三者兩兩機制皆不同（add_gold／heal／modify_stat）不應被任何一對觸發: %s" % _issue_text(report)
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
