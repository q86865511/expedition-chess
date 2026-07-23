extends GutTest

# T07（S4 build-systems）內容驗證器擴充規則測試。
# 對應 specs/build-systems/design.md §7 (a)-(e)：
#   (a) EquipmentDef.unique_group 一致性
#   (b) RelicDef.category 四類覆蓋 + activation_limit 合法性
#   (c) 遺物 effect_refs 作用域須與 category（battle / 非 battle）相符
#   (d) 拆卸 ConsumableDef 的 use_timing/run_operations 語意
#   (e) 零件不得被 grant/reward 當成完整裝備／道具發放
#
# 以下判準是本測試對設計文件敘述的具體化（實作前的介面決策）；
# 若實作方向與此不符,請先回報「測試爭議」而非默默放寬斷言：
#   (a) has_unique_group=true 時 unique_group 須為合法 stable-id（StableIdValidator）；
#       has_unique_group=false 時 unique_group 須為空,避免旗標與值不一致。
#   (b) category 僅接受 battle/economy/route/rule 四類（封閉枚舉）；15 件遺物須四類皆 ≥1；
#       activation_limit 合法範圍取 [1, 99]（比照既有 max_stacks/max_uses_per_battle 界線慣例）。
#   (c) category == battle 的遺物,effect_refs 指向的 EffectDef 須有非空 battle_operations；
#       category != battle 的遺物,effect_refs 指向的 EffectDef 須有非空 run_operations。
#   (d) use_timing == &"dismantle" 視為拆卸道具；其 run_operations 須為空
#       （拆卸的實際效果由專屬 DismantleEquipmentCommand 表達,不透過通用 run_operations）。
#   (e) GrantItemOperationDef.content_ref 與 RewardCandidateDef(kind=&"item").content_ref
#       皆不得指向 ItemComponentDef。
#
# 已知連帶影響：SyntheticContentFixture.build_valid() 目前對全部 15 件遺物指定
# category=&"team"（不在四類封閉枚舉內）。一旦規則 (b) 掛進 ContentValidator.validate()，
# tests/fixtures/content/synthetic_content_fixture.gd 與
# tests/fixtures/content/content_verification_suite.gd 的既有 valid_slice / mutation 案例
# 將轉紅，需要同步補上有效 category 才能回綠——這是 T07 任務整體驗收的一部分（既有 fixture
# 補足），不在本測試檔的撰寫範圍內，留給實作代理處理。

const RELIC_IDS: Array[StringName] = [
	&"relic.r0", &"relic.r1", &"relic.r2", &"relic.r3", &"relic.r4", &"relic.r5", &"relic.r6",
	&"relic.r7", &"relic.r8", &"relic.r9", &"relic.r10", &"relic.r11", &"relic.r12", &"relic.r13",
	&"relic.r14",
]
const BATTLE_RELIC_IDS: Array[StringName] = [&"relic.r0", &"relic.r1", &"relic.r2", &"relic.r3", &"relic.r14"]
const ECONOMY_RELIC_IDS: Array[StringName] = [&"relic.r4", &"relic.r5", &"relic.r6", &"relic.r7"]
const ROUTE_RELIC_IDS: Array[StringName] = [&"relic.r8", &"relic.r9", &"relic.r10"]
const RULE_RELIC_IDS: Array[StringName] = [&"relic.r11", &"relic.r12", &"relic.r13"]

# ---------- 共用 baseline：五類規則同時合規（違規測試從此 clone 後破壞單一欄位）----------

func _compliant_input() -> ContentValidationInput:
	var input := SyntheticContentFixture.build_valid()
	for content_id in RELIC_IDS:
		var relic := _find(input, content_id) as RelicDef
		relic.activation_limit = 1
		if BATTLE_RELIC_IDS.has(content_id):
			relic.category = &"battle"
			relic.effect_refs = [&"effect.summon"]
		elif ECONOMY_RELIC_IDS.has(content_id):
			relic.category = &"economy"
			relic.effect_refs = [&"effect.operation_matrix"]
		elif ROUTE_RELIC_IDS.has(content_id):
			relic.category = &"route"
			relic.effect_refs = [&"effect.operation_matrix"]
		else:
			relic.category = &"rule"
			relic.effect_refs = [&"effect.operation_matrix"]
	var grouped_equipment := _find(input, &"equipment.c0_c1") as EquipmentDef
	grouped_equipment.has_unique_group = true
	grouped_equipment.unique_group = &"unique_group.test_pair"
	var dismantle_kit := ConsumableDef.new()
	dismantle_kit.id = &"consumable.dismantle_kit"
	dismantle_kit.schema_version = 1
	dismantle_kit.display_name_key = &"loc.consumable.dismantle_kit"
	dismantle_kit.use_timing = &"dismantle"
	dismantle_kit.run_operations = []
	dismantle_kit.stack_limit = 1
	input.definitions.append(dismantle_kit)
	return input

func _find(input: ContentValidationInput, content_id: StringName) -> ContentDefinition:
	for definition in input.definitions:
		if definition.id == content_id: return definition
	return null

func _has_issue(report: ContentValidationReport, code: StringName) -> bool:
	for issue: ContentValidationIssue in report.issues:
		if issue.code == code: return true
	return false

func _issue_text(report: ContentValidationReport) -> String:
	var values: Array[String] = []
	for issue: ContentValidationIssue in report.issues:
		values.append("%s:%s:%s" % [issue.code, issue.source_id, issue.field_path])
	return ", ".join(values)

# ================= baseline sanity =================

func test_compliant_baseline_has_no_build_systems_issues() -> void:
	var report := ContentValidator.new().validate(_compliant_input())
	assert_true(report.valid, _issue_text(report))

# ================= (a) EquipmentDef.unique_group 一致性 =================

func test_equipment_flagged_unique_group_requires_non_empty_stable_id() -> void:
	var input := _compliant_input()
	(_find(input, &"equipment.c0_c1") as EquipmentDef).unique_group = &""
	var report := ContentValidator.new().validate(input)
	assert_false(report.valid)
	assert_true(_has_issue(report, &"CONTENT_EQUIPMENT_UNIQUE_GROUP"), _issue_text(report))

func test_equipment_flagged_unique_group_requires_valid_stable_id_shape() -> void:
	var input := _compliant_input()
	(_find(input, &"equipment.c0_c1") as EquipmentDef).unique_group = &"NotAStableId"
	var report := ContentValidator.new().validate(input)
	assert_false(report.valid)
	assert_true(_has_issue(report, &"CONTENT_EQUIPMENT_UNIQUE_GROUP"), _issue_text(report))

func test_equipment_unflagged_unique_group_must_not_carry_stale_value() -> void:
	var input := _compliant_input()
	var stray_equipment := _find(input, &"equipment.c0_c2") as EquipmentDef
	stray_equipment.has_unique_group = false
	stray_equipment.unique_group = &"unique_group.test_pair"
	var report := ContentValidator.new().validate(input)
	assert_false(report.valid)
	assert_true(_has_issue(report, &"CONTENT_EQUIPMENT_UNIQUE_GROUP"), _issue_text(report))

# ================= (b) 遺物 category 四類覆蓋與 activation_limit =================

func test_relic_category_outside_the_four_supported_kinds_is_rejected() -> void:
	var input := _compliant_input()
	(_find(input, &"relic.r0") as RelicDef).category = &"team"
	var report := ContentValidator.new().validate(input)
	assert_false(report.valid)
	assert_true(_has_issue(report, &"CONTENT_RELIC_CATEGORY"), _issue_text(report))

func test_relic_category_coverage_requires_all_four_kinds_present() -> void:
	var input := _compliant_input()
	for content_id in ROUTE_RELIC_IDS:
		(_find(input, content_id) as RelicDef).category = &"battle"
	var report := ContentValidator.new().validate(input)
	assert_false(report.valid)
	assert_true(_has_issue(report, &"CONTENT_RELIC_CATEGORY_COVERAGE"), _issue_text(report))

func test_relic_activation_limit_must_be_at_least_one() -> void:
	var input := _compliant_input()
	(_find(input, &"relic.r0") as RelicDef).activation_limit = 0
	var report := ContentValidator.new().validate(input)
	assert_false(report.valid)
	assert_true(_has_issue(report, &"CONTENT_RELIC_ACTIVATION_LIMIT"), _issue_text(report))

func test_relic_activation_limit_must_not_exceed_upper_bound() -> void:
	var input := _compliant_input()
	(_find(input, &"relic.r0") as RelicDef).activation_limit = 100
	var report := ContentValidator.new().validate(input)
	assert_false(report.valid)
	assert_true(_has_issue(report, &"CONTENT_RELIC_ACTIVATION_LIMIT"), _issue_text(report))

# ================= (c) 遺物效果作用域須與 category 相符 =================

func test_battle_relic_effect_refs_must_resolve_to_a_battle_capable_effect() -> void:
	var input := _compliant_input()
	# effect.general 未設定 battle_operations，對 battle 類遺物而言不可解為戰鬥效果。
	(_find(input, &"relic.r0") as RelicDef).effect_refs = [&"effect.general"]
	var report := ContentValidator.new().validate(input)
	assert_false(report.valid)
	assert_true(_has_issue(report, &"CONTENT_RELIC_EFFECT_SCOPE"), _issue_text(report))

func test_non_battle_relic_effect_refs_must_carry_a_supported_run_intent() -> void:
	var input := _compliant_input()
	# effect.summon 只有 battle_operations、沒有 run_operations，對非 battle 類遺物而言不是可用的 run intent。
	(_find(input, &"relic.r4") as RelicDef).effect_refs = [&"effect.summon"]
	var report := ContentValidator.new().validate(input)
	assert_false(report.valid)
	assert_true(_has_issue(report, &"CONTENT_RELIC_EFFECT_SCOPE"), _issue_text(report))

func test_relic_effect_refs_must_not_be_empty() -> void:
	var input := _compliant_input()
	(_find(input, &"relic.r0") as RelicDef).effect_refs = []
	var report := ContentValidator.new().validate(input)
	assert_false(report.valid)
	assert_true(_has_issue(report, &"CONTENT_RELIC_EFFECT_EMPTY"), _issue_text(report))

func test_relic_effect_refs_pointing_at_a_non_effect_definition_is_rejected_not_skipped() -> void:
	var input := _compliant_input()
	# item_component.c0 存在於 _by_id 但不是 EffectDef——舊實作對此靜默 continue，
	# 等同該筆 effect_ref 完全不受作用域規則檢查；補強後須產出 issue 而非放行。
	(_find(input, &"relic.r0") as RelicDef).effect_refs = [&"item_component.c0"]
	var report := ContentValidator.new().validate(input)
	assert_false(report.valid)
	assert_true(_has_issue(report, &"CONTENT_RELIC_EFFECT_SCOPE"), _issue_text(report))

# ================= (d) 拆卸 ConsumableDef 語意 =================

func test_dismantle_consumable_must_not_carry_run_operations() -> void:
	var input := _compliant_input()
	var dismantle_kit := _find(input, &"consumable.dismantle_kit") as ConsumableDef
	var stray_gold := AddGoldOperationDef.new()
	stray_gold.operation_index = 0
	stray_gold.amount = 1
	stray_gold.claim_scope = &"once_per_node"
	dismantle_kit.run_operations = [stray_gold]
	var report := ContentValidator.new().validate(input)
	assert_false(report.valid)
	assert_true(_has_issue(report, &"CONTENT_CONSUMABLE_DISMANTLE"), _issue_text(report))

# ================= (e) 零件不得被 grant/reward 當成完整裝備／道具發放 =================

func test_grant_item_operation_must_not_target_an_item_component() -> void:
	var input := _compliant_input()
	var event_node := _find(input, &"map_node.event_0") as MapNodeDef
	var grant := event_node.enter_operations[1] as GrantItemOperationDef
	assert_not_null(grant, "fixture layout changed: map_node.event_0.enter_operations[1] is no longer GrantItemOperationDef")
	grant.content_ref = &"item_component.c0"
	var report := ContentValidator.new().validate(input)
	assert_false(report.valid)
	assert_true(_has_issue(report, &"CONTENT_ITEM_GRANT_COMPONENT"), _issue_text(report))

func test_reward_candidate_item_kind_must_not_target_an_item_component() -> void:
	var input := _compliant_input()
	var table := _find(input, &"reward_table.default") as RewardTableDef
	var candidate := RewardCandidateDef.new()
	candidate.kind = &"item"
	candidate.has_content_ref = true
	candidate.content_ref = &"item_component.c0"
	candidate.weight_i32 = 1
	table.reward_candidates.append(candidate)
	var report := ContentValidator.new().validate(input)
	assert_false(report.valid)
	assert_true(_has_issue(report, &"CONTENT_ITEM_GRANT_COMPONENT"), _issue_text(report))

# ================= (W2-F6) NORMAL/ELITE MapNodeRule 數量必須對等（route 遺物覆寫 kind 時 RNG bound 不變）=================

func _extra_map_node(content_id: StringName, kind: StringName) -> MapNodeDef:
	var node := MapNodeDef.new()
	node.id = content_id
	node.schema_version = 1
	node.display_name_key = StringName("loc.%s" % String(content_id))
	node.node_type = kind
	node.generator_ref = StringName("encounter.%s" % String(kind))
	return node

func test_map_node_rule_count_parity_flags_normal_elite_imbalance() -> void:
	var input := _compliant_input()
	# 基準 fixture 的 normal/elite 各 1 筆；多加一筆 elite、不補對應的 normal，
	# 使兩者數量失衡（1 normal / 2 elite），對應 map_service.gd 覆寫 NORMAL -> ELITE
	# 後 rule_draw bound 會分歧的情境。
	input.definitions.append(_extra_map_node(&"map_node.elite_extra", &"elite"))
	var report := ContentValidator.new().validate(input)
	assert_false(report.valid)
	assert_true(_has_issue(report, &"CONTENT_MAP_NODE_RULE_COUNT_PARITY"), _issue_text(report))

func test_map_node_rule_count_parity_allows_matched_normal_and_elite_counts() -> void:
	var input := _compliant_input()
	# 同時各加一筆 normal 與 elite，維持對等（2 normal / 2 elite）——確認規則比較的是
	# 「數量相等」而非「恰為 1」，等量時不應誤報。
	input.definitions.append(_extra_map_node(&"map_node.normal_extra", &"normal"))
	input.definitions.append(_extra_map_node(&"map_node.elite_extra", &"elite"))
	var report := ContentValidator.new().validate(input)
	assert_false(_has_issue(report, &"CONTENT_MAP_NODE_RULE_COUNT_PARITY"), _issue_text(report))

# W2-F6 fix 2026-07-23
