extends GutTest

## T07 (specs/meta-progression) — content_validator.gd 擴充：
##   (a) ShopSurchargeOperationDef／DrainExpeditionHpOperationDef 進 scalar run operation
##       解碼白名單，維持 amount≥0 不變量；
##   (b) 新增 challenge_affix 內容規則：challenge 鏈 1..5 的 modifier_refs 必須指向
##       content_role=&"challenge_affix" 的效果（非 elite_affix）；四類分類覆蓋。
## Covers：S5-AC-010；design.md §7.2；tasks.md T07 驗收「validator 解碼分支...維持 amount≥0
## 不變量」「challenge 鏈 modifier_refs 必指 challenge_affix...四類分類覆蓋」。
##
## ============================== 假設聲明（design.md 未釘死處） ==============================
## 1. ShopSurchargeOperationDef / DrainExpeditionHpOperationDef 為 RunOperationDef 子類，路徑
##    res://content/definitions/shop_surcharge_operation_def.gd /
##    drain_expedition_hp_operation_def.gd，欄位 amount:int + claim_scope:StringName（與
##    AddGoldOperationDef 同形狀），operation_type() 分別回傳 0x3109 / 0x310A（緊接既有
##    run operation code 0x3101..0x3108，未使用過）。兩者納入
##    content_validator._validate_run_operations 的 scalar 分支（與既有 AddGold/AddXp/
##    HealExpeditionHp/ShopDiscount 同組判斷：`_scalar_run_amount`/`_scalar_run_claim_scope`
##    對兩者的支援亦一併擴充），故在 EffectDef.run_operations 脈絡（battle_source 恆為
##    true）下 amount<0 或 claim_scope 不在 {once_per_node,on_first_clear,always} 時回
##    CONTENT_RUN_INTENT_FORBIDDEN（既有四種 scalar op 的既定行為，非本檔新規則，只是延伸
##    覆蓋範圍）；amount≥0 且 scope 合法時被视為「已知 operation」，不觸發
##    CONTENT_OPERATION_INVALID(index/type)。
## 2. 新增 _validate_challenge_chain 規則（本檔斷言的新行為，實作前不存在，測試作者發明的
##    issue code 字串——只要實作端用「等價語意＋這兩個確切字串」即可通過；認為應合併/拆分
##    為不同 code 屬測試爭議範疇）：
##      CONTENT_CHALLENGE_AFFIX_ROLE：challenge unlock 鏈 level 1..5 的 modifier_refs 中，
##        任一 effect_id 若能解析到定義但 content_role != &"challenge_affix"（含解析到
##        非 EffectDef 的情形），逐效果回一筆 issue（source_id=該 effect_id）。
##      CONTENT_CHALLENGE_AFFIX_COVERAGE：把 level 1..5 modifier_refs 引用到的所有
##        content_role=&"challenge_affix" 效果聯集起來，若未能同時覆蓋以下三個「可機械判別
##        的桶」，回一筆聚合性 issue（source_id=&"catalog.challenge_affix"）：
##          (a) 至少一個效果 battle_operations 非空（軌 A——design §7.1「四類」的敵人編成/
##              遭遇規則兩者依 §6.3 皆屬同一機制「軌 A」、內容 schema 無獨立欄位可再細分，
##              故本檔只驗證這三桶的聯集覆蓋，不強加軌 A 內部二次分類）
##          (b) 至少一個效果的 run_operations 含 operation_type()==0x3109（ShopSurcharge，
##              經濟壓力）
##          (c) 至少一個效果的 run_operations 含 operation_type()==0x310A
##              （DrainExpeditionHp，遠征傷害）
## 3. 【重大風險，務必在派工回報中轉達】tests/fixtures/content/synthetic_content_fixture.gd
##    的 SyntheticContentFixture.build_valid() 目前預設把 unlock.challenge_1..5 的
##    modifier_refs 指向 effect.affix_0..4（content_role=&"elite_affix"）——這是 S1~S4 遺留、
##    T07 之前從未被檢查過的既有形狀。若嚴格按上面第 2 點實作 CONTENT_CHALLENGE_AFFIX_ROLE，
##    會讓 SyntheticContentFixture.build_valid() 的「未修改」輸出本身變成不合規，進而讓大量
##    既有、已通過的測試轉紅（至少包含：tests/unit/meta_progression/
##    test_run_modifier_table_builder.gd 內所有呼叫 registry.install_validated(
##    SyntheticContentFixture.build_valid()/_fixture_with_renamed_challenge_chain(), ...)
##    且未逐一覆寫 challenge modifier_refs role 的測試；tests/unit/content_validation/
##    test_content_validator.gd 的 test_valid_vertical_slice_and_population_reports 透過
##    ContentVerificationSuite.run("valid_slice") 對 SyntheticContentFixture 基準的 0-issue
##    期望）。本檔測試作者不擅自修改 SyntheticContentFixture.gd（風險過大、非本任務授權範圍、
##    牽動其他波次已鎖定測試），故本檔全部改用完全獨立、自建的最小 ContentValidationInput
##    （_minimal_challenge_input()，不依賴 SyntheticContentFixture），使本檔紅燈只反映 T07
##    尚未實作、不受此既有缺口污染。這個衝突需要 T07 實作階段與 SyntheticContentFixture 的
##    維護者協調（多半必須同步更新 SyntheticContentFixture 的預設 challenge 鏈內容），不是
##    測試作者能片面決定的事，故不在此處靜默處理，留給回報與後續實作代理裁決。
## ============================================================================================
##
## GUT 陷阱處理：ShopSurchargeOperationDef/DrainExpeditionHpOperationDef 尚不存在，不可用
## class_name 靜態建構（見 tests/unit/meta_progression/test_run_discovery_log.gd 說明）。本檔
## 一律用 load(path)+GDScript.new() 動態建構，屬性用 Object.set() 賦值，回傳值只宣告為既有的
## RunOperationDef 基底型別（可安全靜態參照，因為它早已存在），不宣告為子類名稱。

const SHOP_SURCHARGE_SCRIPT_PATH := "res://content/definitions/shop_surcharge_operation_def.gd"
const DRAIN_EXPEDITION_HP_SCRIPT_PATH := "res://content/definitions/drain_expedition_hp_operation_def.gd"


func test_modify_stat_flat_mode_is_rejected_by_content_validator() -> void:
	var input := _minimal_challenge_input()
	_append_modify_stat_effect(input, &"effect.probe_flat_mode", &"flat", 5)
	var report := ContentValidator.new().validate(input)
	assert_true(
		_has_issue(report, &"CONTENT_OPERATION_INVALID"),
		"ModifyStatOperationDef.mode=flat 必須在 content gate 被拒絕: %s" % _issue_text(report)
	)


func test_modify_stat_add_and_bounded_multiply_modes_are_accepted() -> void:
	for mode: StringName in [&"add", &"multiply_bps"]:
		var input := _minimal_challenge_input()
		_append_modify_stat_effect(input, StringName("effect.probe_%s" % mode), mode, 100000)
		var report := ContentValidator.new().validate(input)
		assert_false(
			_has_issue(report, &"CONTENT_OPERATION_INVALID"),
			"合法 modify_stat mode 不應被拒絕 (%s): %s" % [mode, _issue_text(report)]
		)


func test_modify_stat_multiply_bps_above_canonical_bound_is_rejected() -> void:
	var input := _minimal_challenge_input()
	_append_modify_stat_effect(input, &"effect.probe_multiply_overflow", &"multiply_bps", 100001)
	var report := ContentValidator.new().validate(input)
	assert_true(
		_has_issue(report, &"CONTENT_OPERATION_INVALID"),
		"multiply_bps > 100000 必須在 content gate 被拒絕: %s" % _issue_text(report)
	)


func test_shop_surcharge_negative_amount_is_forbidden_on_effect() -> void:
	var operation := _new_shop_surcharge(0, -1, &"always")
	if operation == null:
		return
	var input := _minimal_challenge_input()
	var run_operations: Array[RunOperationDef] = [operation]
	_append_effect_with_run_ops(input, &"effect.probe_surcharge_negative", &"general", run_operations)
	var report := ContentValidator.new().validate(input)
	assert_true(
		_has_issue(report, &"CONTENT_RUN_INTENT_FORBIDDEN"),
		"amount<0 的 ShopSurchargeOperationDef 必須被拒絕: %s" % _issue_text(report)
	)


func test_drain_expedition_hp_negative_amount_is_forbidden_on_effect() -> void:
	var operation := _new_drain_expedition_hp(0, -1, &"always")
	if operation == null:
		return
	var input := _minimal_challenge_input()
	var run_operations: Array[RunOperationDef] = [operation]
	_append_effect_with_run_ops(input, &"effect.probe_drain_negative", &"general", run_operations)
	var report := ContentValidator.new().validate(input)
	assert_true(
		_has_issue(report, &"CONTENT_RUN_INTENT_FORBIDDEN"),
		"amount<0 的 DrainExpeditionHpOperationDef 必須被拒絕: %s" % _issue_text(report)
	)


func test_shop_surcharge_invalid_claim_scope_is_forbidden() -> void:
	var operation := _new_shop_surcharge(0, 3, &"never_heard_of_this_scope")
	if operation == null:
		return
	var input := _minimal_challenge_input()
	var run_operations: Array[RunOperationDef] = [operation]
	_append_effect_with_run_ops(input, &"effect.probe_surcharge_bad_scope", &"general", run_operations)
	var report := ContentValidator.new().validate(input)
	assert_true(_has_issue(report, &"CONTENT_RUN_INTENT_FORBIDDEN"), _issue_text(report))


func test_shop_surcharge_and_drain_with_valid_amount_and_scope_are_known_operations() -> void:
	var surcharge := _new_shop_surcharge(0, 3, &"always")
	var drain := _new_drain_expedition_hp(1, 5, &"always")
	if surcharge == null or drain == null:
		return
	var input := _minimal_challenge_input()
	var run_operations: Array[RunOperationDef] = [surcharge, drain]
	_append_effect_with_run_ops(input, &"effect.probe_valid_operations", &"general", run_operations)
	var report := ContentValidator.new().validate(input)
	assert_false(
		_has_issue(report, &"CONTENT_OPERATION_INVALID"),
		"合法 amount/scope 的兩個新 operation 必須被辨識為已知 operation: %s" % _issue_text(report)
	)
	assert_false(
		_has_issue(report, &"CONTENT_RUN_INTENT_FORBIDDEN"),
		"合法 amount/scope 不應被拒絕: %s" % _issue_text(report)
	)


func test_challenge_chain_modifier_pointing_to_non_challenge_affix_role_is_rejected() -> void:
	var input := _minimal_challenge_input()
	_append_effect(input, &"effect.wrong_role_probe", &"elite_affix", true)
	_fill_all_levels_with_compliant_filler(input, [1])
	_set_modifier_refs(input, 1, [&"effect.wrong_role_probe"])
	var report := ContentValidator.new().validate(input)
	assert_true(
		_has_issue(report, &"CONTENT_CHALLENGE_AFFIX_ROLE"),
		"content_role=elite_affix 的效果被 challenge 鏈引用必須被拒絕: %s" % _issue_text(report)
	)


func test_challenge_chain_modifier_with_challenge_affix_role_and_full_coverage_has_no_new_issues() -> void:
	var input := _minimal_challenge_input()
	var surcharge := _new_shop_surcharge(0, 2, &"always")
	var drain := _new_drain_expedition_hp(0, 3, &"always")
	if surcharge == null or drain == null:
		return
	_append_effect(input, &"effect.ca_battle", &"challenge_affix", true)
	var surcharge_ops: Array[RunOperationDef] = [surcharge]
	var drain_ops: Array[RunOperationDef] = [drain]
	_append_effect_with_run_ops(input, &"effect.ca_surcharge", &"challenge_affix", surcharge_ops)
	_append_effect_with_run_ops(input, &"effect.ca_drain", &"challenge_affix", drain_ops)
	_set_modifier_refs(input, 1, [&"effect.ca_battle"])
	_set_modifier_refs(input, 2, [&"effect.ca_surcharge"])
	_set_modifier_refs(input, 3, [&"effect.ca_drain"])
	_set_modifier_refs(input, 4, [&"effect.ca_battle"])
	_set_modifier_refs(input, 5, [&"effect.ca_battle"])
	var report := ContentValidator.new().validate(input)
	assert_false(_has_issue(report, &"CONTENT_CHALLENGE_AFFIX_ROLE"), _issue_text(report))
	assert_false(_has_issue(report, &"CONTENT_CHALLENGE_AFFIX_COVERAGE"), _issue_text(report))


## G2 difficulty-curve T06（DC-REQ-006，BP-SI-001 已解除）：run-operation 桶（ShopSurcharge／
## DrainExpeditionHp）回復為必要覆蓋，不再暫緩。此檔原斷言「暫緩」的行為（見 git 歷史
## 805a592）已隨規格解除而反轉——只覆蓋軌 A＋ShopSurcharge、缺 DrainExpeditionHp 桶時
## 三桶 gate 必須 FAIL。
func test_challenge_affix_missing_drain_bucket_is_rejected() -> void:
	var input := _minimal_challenge_input()
	var surcharge := _new_shop_surcharge(0, 2, &"always")
	if surcharge == null:
		return
	_append_effect(input, &"effect.ca_battle_only", &"challenge_affix", true)
	var surcharge_ops: Array[RunOperationDef] = [surcharge]
	_append_effect_with_run_ops(input, &"effect.ca_surcharge_only", &"challenge_affix", surcharge_ops)
	for level in range(1, 6):
		_set_modifier_refs(input, level, [&"effect.ca_battle_only", &"effect.ca_surcharge_only"])
	var report := ContentValidator.new().validate(input)
	assert_true(
		_has_issue(report, &"CONTENT_CHALLENGE_AFFIX_COVERAGE"),
		"DC-REQ-006 三桶 gate：只覆蓋軌 A＋ShopSurcharge、缺 DrainExpeditionHp 桶時必須 FAIL: %s" % _issue_text(report)
	)


func test_challenge_affix_coverage_missing_battle_track_is_rejected() -> void:
	var input := _minimal_challenge_input()
	var surcharge := _new_shop_surcharge(0, 2, &"always")
	var drain := _new_drain_expedition_hp(0, 3, &"always")
	if surcharge == null or drain == null:
		return
	var surcharge_ops: Array[RunOperationDef] = [surcharge]
	var drain_ops: Array[RunOperationDef] = [drain]
	_append_effect_with_run_ops(input, &"effect.ca_surcharge_only2", &"challenge_affix", surcharge_ops)
	_append_effect_with_run_ops(input, &"effect.ca_drain_only2", &"challenge_affix", drain_ops)
	for level in range(1, 6):
		_set_modifier_refs(input, level, [&"effect.ca_surcharge_only2", &"effect.ca_drain_only2"])
	var report := ContentValidator.new().validate(input)
	assert_true(
		_has_issue(report, &"CONTENT_CHALLENGE_AFFIX_COVERAGE"),
		"全鏈缺軌 A（battle_operations 非空）桶時必須回覆蓋不足: %s" % _issue_text(report)
	)


## W4-F（Sonnet#4）修正（2026-07-25）：非-always claim_scope 的消費限制之前只掛在
## RelicDef.effect_refs 驗證路徑（_validate_relic_effect_scope），challenge 鏈
## modifier_refs 引用的效果完全沒被驗證器檢查過——RunModifierTableBuilder.build() 對
## commander/challenge 來源只放行 &"always"（見 run_relic_table_builder.gd
## _scope_supported），故 once_per_node 在這裡必定會在 build 階段被拒絕；validator 必須
## 先一步具名拒絕，不留下「install_validated 通過、run 建表才失敗」的時間差。
func test_challenge_chain_modifier_with_non_always_claim_scope_is_rejected() -> void:
	var operation := _new_shop_surcharge(0, 2, &"once_per_node")
	if operation == null:
		return
	var input := _minimal_challenge_input()
	var run_operations: Array[RunOperationDef] = [operation]
	_append_effect_with_run_ops(input, &"effect.ca_non_always_scope", &"challenge_affix", run_operations)
	_set_modifier_refs(input, 1, [&"effect.ca_non_always_scope"])
	var report := ContentValidator.new().validate(input)
	assert_true(
		_has_issue(report, &"CONTENT_RELIC_EFFECT_SCOPE"),
		"challenge 鏈引用的效果若 claim_scope 非 always，消費端（RunModifierTableBuilder）必定拒絕，validator 必須先擋: %s" % _issue_text(report)
	)
	# DC-REQ-006（BP-SI-001 已解除，combat-core/design.md:117/:236）：RunOperation 禁令
	# 的作用域限於進入 BattleSetup 的 EffectSourceState——本效果只有 run_operations、
	# 無 battle_operations，不進 battle catalog，不再觸發 CONTENT_EFFECT_SOURCE_LIFECYCLE
	# （原斷言反映 BP-SI-001 解除前的舊行為，見 git 歷史）。
	assert_false(
		_has_issue(report, &"CONTENT_EFFECT_SOURCE_LIFECYCLE"),
		"純 run_operations 的 challenge 詞綴不進 BattleSetup，不受 RunOperation 禁令限制: %s" % _issue_text(report)
	)


## DC-REQ-006 的禁令仍全面適用於雙軌（battle_operations＋run_operations 同時非空）效果：
## 一旦效果同時攜帶 battle_operations，該效果就會被 pin 進 BattleSetup 的 EffectSourceState，
## RunOperation 因此仍不得存在（對照 test_challenge_affix_battle_catalog.gd 的
## registry-level 版本，本檔驗證 ContentValidator 自身這一層先擋）。
func test_challenge_dual_track_battle_and_run_operations_is_rejected_at_lifecycle() -> void:
	var surcharge := _new_shop_surcharge(0, 2, &"always")
	if surcharge == null:
		return
	var input := _minimal_challenge_input()
	_append_effect(input, &"effect.ca_dual_track", &"challenge_affix", true)
	var dual_effect := _find(input, &"effect.ca_dual_track") as EffectDef
	var run_operations: Array[RunOperationDef] = [surcharge]
	dual_effect.run_operations = run_operations
	_set_modifier_refs(input, 1, [&"effect.ca_dual_track"])
	var report := ContentValidator.new().validate(input)
	assert_true(
		_has_issue(report, &"CONTENT_EFFECT_SOURCE_LIFECYCLE"),
		"雙軌（battle_operations＋run_operations）challenge 效果仍必須被拒絕: %s" % _issue_text(report)
	)


func _new_shop_surcharge(operation_index: int, amount: int, claim_scope: StringName) -> RunOperationDef:
	var script := load(SHOP_SURCHARGE_SCRIPT_PATH) as GDScript
	assert_not_null(script, "ShopSurchargeOperationDef (%s) must exist" % SHOP_SURCHARGE_SCRIPT_PATH)
	if script == null:
		return null
	var operation: RunOperationDef = script.new()
	operation.set("operation_index", operation_index)
	operation.set("amount", amount)
	operation.set("claim_scope", claim_scope)
	return operation


func _new_drain_expedition_hp(operation_index: int, amount: int, claim_scope: StringName) -> RunOperationDef:
	var script := load(DRAIN_EXPEDITION_HP_SCRIPT_PATH) as GDScript
	assert_not_null(script, "DrainExpeditionHpOperationDef (%s) must exist" % DRAIN_EXPEDITION_HP_SCRIPT_PATH)
	if script == null:
		return null
	var operation: RunOperationDef = script.new()
	operation.set("operation_index", operation_index)
	operation.set("amount", amount)
	operation.set("claim_scope", claim_scope)
	return operation


## 完全獨立於 SyntheticContentFixture 的最小 challenge 鏈輸入：僅 6 個 UnlockDef
## （level 0..5，正確的 prerequisite_refs 鏈），level 1..5 的 modifier_refs 預設為空
## （呼叫端用 _set_modifier_refs 逐一補上）。刻意不含任何 unit/relic/commander 等其他分類，
## 因為本檔只用 _has_issue／not _has_issue 檢查兩個新 issue code 的存在與否，不要求
## report.valid 整體為 true，其餘分類缺失產生的既有 issue 不影響本檔斷言。
func _minimal_challenge_input() -> ContentValidationInput:
	var definitions: Array[ContentDefinition] = []
	for level in range(6):
		var unlock := UnlockDef.new()
		unlock.id = StringName("unlock.slice_challenge_%d" % level)
		unlock.schema_version = 1
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


## 供只想測試單一 level 的測試把「其餘必填 level」填上一個中性、合規的 filler effect，避免
## CONTENT_CHALLENGE_CHAIN(modifier_refs missing) 這類無關 issue 干擾（本檔多數斷言只查特定
## code 的存在與否，理論上不受干擾，但仍保留這個 helper 供需要更乾淨 report 的測試使用）。
func _fill_all_levels_with_compliant_filler(input: ContentValidationInput, skip_levels: Array[int]) -> void:
	var filler_id := &"effect.compliant_filler"
	if _find(input, filler_id) == null:
		_append_effect(input, filler_id, &"challenge_affix", true)
	for level in range(1, 6):
		if skip_levels.has(level):
			continue
		_set_modifier_refs(input, level, [filler_id])


func _append_effect(
	input: ContentValidationInput, effect_id: StringName, role: StringName, with_battle_operation: bool
) -> void:
	var effect := EffectDef.new()
	effect.id = effect_id
	effect.schema_version = 1
	effect.display_name_key = StringName("loc.%s" % String(effect_id))
	effect.content_role = role
	effect.trigger = &"battle_start"
	effect.stacking = &"replace"
	effect.max_stacks = 1
	effect.duration_ticks = 20
	if with_battle_operation:
		var operation := ModifyStatOperationDef.new()
		operation.operation_index = 0
		operation.stat = &"attack"
		operation.mode = &"add"
		operation.amount = 1
		operation.duration_ticks = 20
		operation.target = &"all_enemies"
		effect.battle_operations = [operation]
	input.definitions.append(effect)


func _append_modify_stat_effect(
	input: ContentValidationInput,
	effect_id: StringName,
	mode: StringName,
	amount: int
) -> void:
	var effect := EffectDef.new()
	effect.id = effect_id
	effect.schema_version = 1
	effect.display_name_key = StringName("loc.%s" % String(effect_id))
	effect.content_role = &"general"
	effect.trigger = &"battle_start"
	effect.stacking = &"replace"
	effect.max_stacks = 1
	effect.duration_ticks = 20
	var operation := ModifyStatOperationDef.new()
	operation.operation_index = 0
	operation.stat = &"attack"
	operation.mode = mode
	operation.amount = amount
	operation.duration_ticks = 20
	operation.target = &"self"
	effect.battle_operations = [operation]
	input.definitions.append(effect)


func _append_effect_with_run_ops(
	input: ContentValidationInput, effect_id: StringName, role: StringName, run_operations: Array[RunOperationDef]
) -> void:
	var effect := EffectDef.new()
	effect.id = effect_id
	effect.schema_version = 1
	effect.display_name_key = StringName("loc.%s" % String(effect_id))
	effect.content_role = role
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
