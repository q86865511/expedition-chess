extends GutTest

## W4-F1／W4-F2（2026-07-24 使用者裁決）— 非 battle 遺物引用效果的 claim_scope 收斂規則。
## 封洞來源：.pipeline/reviews/2026-07-24-reviewer-w4.md 意見 #1（claim_scope 豁免＋消費端忽略
## scope 的組合破洞）與 #2（validator↔builder 對 claim_scope 分歧）。
##
## 兩層防護，本檔各自鎖定：
## - Fix 1（validator）：非 battle 類遺物 effect_refs 指向的效果，其 scalar run_operations
##   （add_gold/add_xp/heal_expedition_hp/shop_discount）claim_scope 必須全為 &"always"，
##   否則 CONTENT_RELIC_EFFECT_SCOPE。純 run 與混合效果（帶 battle_operations）皆適用。
## - Fix 2（builder）：RunRelicTableBuilder 對解出的每一筆 run intent claim_scope 非 always
##   一律 UNSUPPORTED_INTENT，移除 W3-F5 對混合效果的豁免。
## run-layer 消費端（RunRelicTable.sum_operation_amount）逐節點無條件加總、不看 claim_scope，
## 故 always 是唯一與實際行為一致的宣告；非 always 會被靜默違反，兩層都必須擋下。

# ---------- Fix 1：validator 收斂非 battle 遺物 run intent 的 claim_scope ----------

func test_validator_flags_economy_relic_referencing_mixed_effect_with_non_always_run_scope() -> void:
	# 混合效果（帶 battle_operations）+ 非 always run intent，正是審查 #1 描述的破洞形狀：
	# 舊 validator 只檢查 run_operations 非空即放行 → 商店每次刷新都套折扣、違反宣告 scope。
	var input := SyntheticContentFixture.build_valid()
	input.definitions.append(_mixed_effect(&"effect.w4_mixed_non_always", &"once_per_node"))
	(_find(input, &"relic.r4") as RelicDef).effect_refs = [&"effect.w4_mixed_non_always"]
	var report := ContentValidator.new().validate(input)
	assert_false(report.valid, _issue_text(report))
	assert_true(_has_issue(report, &"CONTENT_RELIC_EFFECT_SCOPE"), _issue_text(report))

func test_validator_flags_economy_relic_referencing_pure_run_effect_with_non_always_scope() -> void:
	# 純 run 效果（不帶 battle_operations）+ once_per_node，正是審查 #2 的 validator↔builder 分歧：
	# 作者比照舊慣例新增 once_per_node 經濟遺物效果 → 過驗證但 builder build 硬失敗。
	var input := SyntheticContentFixture.build_valid()
	input.definitions.append(_pure_run_effect(&"effect.w4_pure_non_always", &"once_per_node"))
	(_find(input, &"relic.r5") as RelicDef).effect_refs = [&"effect.w4_pure_non_always"]
	var report := ContentValidator.new().validate(input)
	assert_false(report.valid, _issue_text(report))
	assert_true(_has_issue(report, &"CONTENT_RELIC_EFFECT_SCOPE"), _issue_text(report))

func test_validator_accepts_economy_relic_referencing_always_run_effect() -> void:
	# 邊界：always run intent 不應被新規則誤擋（規則只收斂非 always，不誤傷合規內容）。
	var input := SyntheticContentFixture.build_valid()
	input.definitions.append(_pure_run_effect(&"effect.w4_pure_always", &"always"))
	(_find(input, &"relic.r6") as RelicDef).effect_refs = [&"effect.w4_pure_always"]
	var report := ContentValidator.new().validate(input)
	assert_true(report.valid, _issue_text(report))

func test_validator_leaves_battle_relic_run_scope_semantics_untouched() -> void:
	# 邊界：battle 類遺物的 run intent scope 屬戰鬥層語意，不受本規則約束。以 battle 遺物
	# relic.r0 引用帶 once_per_node run intent 的混合效果，其 battle_operations 滿足 battle 作用域，
	# 不應因 run scope 非 always 觸發 CONTENT_RELIC_EFFECT_SCOPE。
	var input := SyntheticContentFixture.build_valid()
	input.definitions.append(_mixed_effect(&"effect.w4_battle_mixed_non_always", &"once_per_node"))
	# relic.r0 於 fixture 既為 battle 類；改指向帶 once_per_node run intent 的混合效果。
	(_find(input, &"relic.r0") as RelicDef).effect_refs = [&"effect.w4_battle_mixed_non_always"]
	var report := ContentValidator.new().validate(input)
	# 新規則只在非 battle 分支檢查 run scope；battle 遺物不應因 run scope 非 always 被標記。
	assert_false(_has_issue(report, &"CONTENT_RELIC_EFFECT_SCOPE"), _issue_text(report))

# ---------- Fix 2：builder 移除混合效果豁免 ----------

func test_builder_rejects_non_battle_relic_referencing_mixed_effect_with_non_always_run_scope() -> void:
	# 移除豁免的核心：混合效果（舊 is_pure_run_intent=false）過去被放行，現須與純 run 一致拒絕。
	# 以 _install_authoring_unchecked 繞過已收緊的 validator，直取 builder 自身判準。
	var registry := ContentRegistryService.new()
	add_child_autofree(registry)
	var input := SyntheticContentFixture.build_valid()
	input.definitions.append(_mixed_effect(&"effect.w4_builder_mixed_non_always", &"once_per_node"))
	(_find(input, &"relic.r4") as RelicDef).effect_refs = [&"effect.w4_builder_mixed_non_always"]
	var installed := registry._install_authoring_unchecked(
		input.definitions, "fixture.w4_mixed.1", [&"pack.core"], input.aliases, input.tombstones, input
	)
	assert_true(installed.ok, "unchecked install 仍應能編譯結構完整的紀錄")
	if not installed.ok:
		return
	var built := RunRelicTableBuilder.new().build(
		registry, installed.handle.manifest_digest, [&"relic.r4"]
	)
	assert_false(built.ok, "混合效果的非 always run intent 不再被豁免，builder 須拒絕")
	if built.ok:
		return
	assert_eq(built.error.code, RunRelicTableError.UNSUPPORTED_INTENT)

func test_builder_accepts_non_battle_relic_referencing_mixed_effect_with_always_run_scope() -> void:
	# 邊界：混合效果的 always run intent 應被接受（builder 正確解出混合效果的 run 部分並放行）。
	var registry := ContentRegistryService.new()
	add_child_autofree(registry)
	var input := SyntheticContentFixture.build_valid()
	input.definitions.append(_mixed_effect(&"effect.w4_builder_mixed_always", &"always"))
	(_find(input, &"relic.r4") as RelicDef).effect_refs = [&"effect.w4_builder_mixed_always"]
	var installed := registry._install_authoring_unchecked(
		input.definitions, "fixture.w4_mixed.2", [&"pack.core"], input.aliases, input.tombstones, input
	)
	assert_true(installed.ok)
	if not installed.ok:
		return
	var built := RunRelicTableBuilder.new().build(
		registry, installed.handle.manifest_digest, [&"relic.r4"]
	)
	assert_true(built.ok, "%s" % [String(built.error.code) if not built.ok and built.error != null else "ok"])

# ---------- 共用建構 ----------

func _pure_run_effect(effect_id: StringName, scope: StringName) -> EffectDef:
	var operation := AddGoldOperationDef.new()
	operation.operation_index = 0
	operation.amount = 3
	operation.claim_scope = scope
	var effect := EffectDef.new()
	effect.id = effect_id
	effect.schema_version = 1
	effect.display_name_key = StringName("loc.%s" % String(effect_id))
	effect.content_role = &"general"
	effect.trigger = &"battle_start"
	effect.stacking = &"replace"
	effect.max_stacks = 1
	effect.duration_ticks = 1
	effect.run_operations = [operation]
	return effect

func _mixed_effect(effect_id: StringName, scope: StringName) -> EffectDef:
	var effect := _pure_run_effect(effect_id, scope)
	var damage := DamageOperationDef.new()
	damage.operation_index = 0
	damage.base = 10
	damage.scaling = &"attack"
	damage.damage_type = &"physical"
	damage.target = &"target"
	effect.battle_operations = [damage]
	return effect

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
