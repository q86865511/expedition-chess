extends GutTest

## T10 (specs/meta-progression) — S5-AC-004／design.md §7.2 字面要求 challenge 鏈
## modifier_refs 必指 challenge_affix 效果：現行 content_validator.gd
## _validate_challenge_affix_roles（content/validation/content_validator.gd:354-383）把
## NEUTRAL_EFFECT_ROLE（&"general"，EffectDef.content_role 的預設值）與 CHALLENGE_AFFIX_ROLE
## 一併放行（:364 的 `not in [CHALLENGE_AFFIX_ROLE, NEUTRAL_EFFECT_ROLE]`），與 design.md
## §7.2「modifier_refs 必指向 challenge_affix effects（非 elite_affix）」的字面要求不符
## （字面唯一允許值是 challenge_affix，未提及可放行預設/未分類角色）。tasks.md T10 驗收欄
## 「challenge 鏈 modifier_refs 必指 challenge_affix」與本任務簡報第 3 點明訂本任務要收緊為
## 「必須恰為 challenge_affix」。本檔鎖定收緊後的行為：content_role == &"general" 的效果被
## challenge 鏈 modifier_refs 引用時，必須新增回 CONTENT_CHALLENGE_AFFIX_ROLE（沿用既有
## issue code，不新增 code——只收緊放行條件）。
##
## ============================== 假設聲明 ==============================
## 1. 收緊方式：把 content_validator.gd:364 的
##    `content_role not in [CHALLENGE_AFFIX_ROLE, NEUTRAL_EFFECT_ROLE]` 改為
##    `content_role != CHALLENGE_AFFIX_ROLE`（移除 NEUTRAL_EFFECT_ROLE 的放行）。本檔只斷言
##    可觀察行為（&"general" 角色的效果被引用時必須產生 CONTENT_CHALLENGE_AFFIX_ROLE），不
##    綁定實作必須逐字這樣改——只要語意等價，實作代理可自行決定寫法。
## 2. 已查證不受影響／受影響範圍（務必在派工回報中轉達，這點更正了本任務簡報原先的預警）：
##    a. SyntheticContentFixture.build_valid()（tests/fixtures/content/
##       synthetic_content_fixture.gd:520-536）的 challenge 鏈 modifier_refs 已在 T07 改為
##       指向 _challenge_affix_effects()（content_role 全為 &"challenge_affix"，
##       :154-181），不受本次收緊影響——SyntheticContentFixture 自身基準與所有依賴它的既有
##       測試（install_validated(SyntheticContentFixture.build_valid())...）不會因本次收緊
##       轉紅。
##    b. 【更正本任務簡報「兩處探針效果」的預警】逐行核對
##       tests/unit/content_validation/test_challenge_affix_operation_validation.gd 全文
##       （337 行）後確認：該檔全部 4 處 content_role=&"general" 的探針效果
##       （effect.probe_surcharge_negative:74／probe_drain_negative:88／
##       probe_surcharge_bad_scope:102／probe_valid_operations:114）均只用
##       _append_effect_with_run_ops() 掛進 input.definitions，未被任何一個測試呼叫
##       _set_modifier_refs() 引用進 challenge 鏈——_validate_challenge_affix_roles() 的
##       `authored` 旗標對這 4 個測試恆為 false（因為對應 level 的 modifier_refs 從未被賦
##       值），函式在檢查角色前就已 `if not authored: return`，完全不受本次收緊影響。本檔
##       測試作者判定該檔**不受影響**，與本任務簡報原先「兩處探針效果須實作代理同步」的預警
##       不同，回報中會註明此更正，避免實作代理浪費時間查一個不存在的問題。
##    c. tests/unit/meta_progression/test_run_modifier_table_builder.gd 內
##       _append_add_gold_effect()（:333-348，content_role 寫死 &"general"）被 4 個測試用來
##       覆寫 unlock.slice_challenge_1/2 的 modifier_refs 並期望
##       registry.install_validated(...).ok == true：
##       test_challenge_level_zero_yields_no_challenge_contribution_even_when_higher_levels_have_content
##       （assert_true(installed.ok) 於 :172）、
##       test_challenge_chain_at_requested_level_contributes_its_modifiers（:196）、
##       test_challenge_chain_accumulates_contributions_across_multiple_levels（:219）、
##       test_same_effect_on_two_challenge_levels_contributes_only_once（:307）。這 4 處在
##       本次收緊後會轉紅（install_validated 會因 CONTENT_CHALLENGE_AFFIX_ROLE 而
##       ok=false，導致各測試自己的 assert_true(installed.ok) 先行失敗）——這是本任務簡報
##       第 3 點原先預期、且經本檔測試作者驗證屬實的既有測試同步責任，**不在本檔修改範圍**，
##       需由實作代理同步（例如把 _append_add_gold_effect() 的 content_role 改為
##       &"challenge_affix"，或另立 role=challenge_affix 的等效 helper）。
## 3. 本檔沿用 test_challenge_affix_operation_validation.gd 已建立的 _minimal_challenge_input()
##    模式（完全獨立於 SyntheticContentFixture 的最小 6-UnlockDef challenge 鏈），避免對共用
##    fixture 產生任何耦合或副作用；本檔不匯入/呼叫該檔（GDScript 無跨檔案共享 GutTest 私有
##    helper 的慣用機制，故小量重複這些 helper 屬本專案既有慣例，比對
##    test_content_validator.gd 與 test_challenge_affix_operation_validation.gd 兩檔案皆
##    各自重複定義 _find/_has_issue/_issue_text 可證）。
## ========================================================================

func test_challenge_chain_modifier_pointing_to_neutral_role_is_rejected() -> void:
	var input := _minimal_challenge_input()
	_append_effect(input, &"effect.neutral_role_probe", &"general")
	_set_modifier_refs(input, 1, [&"effect.neutral_role_probe"])

	var report := ContentValidator.new().validate(input)

	assert_true(
		_has_issue(report, &"CONTENT_CHALLENGE_AFFIX_ROLE"),
		"content_role=general（預設/未分類）的效果被 challenge 鏈引用必須被拒絕: %s" % _issue_text(report)
	)


func test_challenge_chain_modifier_with_challenge_affix_role_is_accepted() -> void:
	var input := _minimal_challenge_input()
	_append_effect(input, &"effect.challenge_affix_role_probe", &"challenge_affix")
	_set_modifier_refs(input, 1, [&"effect.challenge_affix_role_probe"])

	var report := ContentValidator.new().validate(input)

	assert_false(
		_has_issue(report, &"CONTENT_CHALLENGE_AFFIX_ROLE"),
		"content_role=challenge_affix 的效果引用不應被拒絕（正對照組）: %s" % _issue_text(report)
	)


func _minimal_challenge_input() -> ContentValidationInput:
	var definitions: Array[ContentDefinition] = []
	for level in range(6):
		var unlock := UnlockDef.new()
		unlock.id = StringName("unlock.slice_challenge_%d" % level)
		unlock.display_name_key = StringName("loc.unlock_slice_challenge_%d" % level)
		unlock.unlock_kind = &"challenge"
		unlock.challenge_level = level
		if level > 0:
			unlock.prerequisite_refs = [StringName("unlock.slice_challenge_%d" % (level - 1))]
		definitions.append(unlock)
	return ContentValidationInput.new(definitions, [], [], FakeContentDependencyPort.new(), 9)


func _set_modifier_refs(input: ContentValidationInput, level: int, effect_ids: Array[StringName]) -> void:
	var unlock := _find(input, StringName("unlock.slice_challenge_%d" % level)) as UnlockDef
	assert_not_null(unlock)
	unlock.modifier_refs = effect_ids


func _append_effect(input: ContentValidationInput, effect_id: StringName, role: StringName) -> void:
	var effect := EffectDef.new()
	effect.id = effect_id
	effect.display_name_key = StringName("loc.%s" % String(effect_id))
	effect.content_role = role
	effect.trigger = &"battle_start"
	effect.stacking = &"replace"
	effect.max_stacks = 1
	effect.duration_ticks = 1
	var modify := ModifyStatOperationDef.new()
	modify.operation_index = 0
	modify.stat = &"attack"
	modify.mode = &"flat"
	modify.amount = 1
	modify.duration_ticks = 20
	modify.target = &"self"
	effect.battle_operations = [modify]
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
