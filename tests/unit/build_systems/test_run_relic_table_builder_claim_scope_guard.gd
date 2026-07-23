extends GutTest

## T12（specs/build-systems）— W3-F5 補充規則：RunRelicTableBuilder 對 claim_scope
## 非 &"always"（或等價預設哨兵）的 run intent 拒絕。
## Covers：REQ-RELIC-001（W3-F5，tasks.md T12 補充：wave2 雙審延後項，使用者裁決 2026-07-23）。
## 依據 tasks.md 原文：「RunRelicOperationRule.claim_scope 已解碼但無消費點（on_first_clear 等
## scope 語意未被遵守），T12/正式接線時定 scope 語意並補防重放」，
## 及本任務簡報：「預期行為：RunRelicTableBuilder 對 claim_scope 非 always（或等價預設哨兵）
## 的 run intent 拒絕（UNSUPPORTED_INTENT 慣例，S5 才實作真語意）」。
##
## 假設聲明（本檔新增，非既有慣例——目前 codebase 沒有任何地方使用 &"always" 作為
## claim_scope 哨兵值，content_validator.gd:672 目前只允許 [&"once_per_node", &"on_first_clear"]）：
## 1. builder 拒絕的錯誤碼沿用既有 RunRelicTableError.UNSUPPORTED_INTENT（與「死內容」防禦共用
##    同一錯誤碼家族，因為兩者語意相近：run intent 在目前 run-layer 無法被正確消費）。
## 2. 哨兵值採用簡報建議的字面量 &"always"。
## 3. 本檔只鎖定 builder 的拒絕行為本身；content/packs/build_systems 與 content/packs/
##    vertical_slice 底下現有遺物 .tres 內容全數使用 once_per_node/on_first_clear（非 always），
##    若此規則被實作，這些既有內容檔與 content_validator.gd 的 claim_scope 允許集合、以及
##    tests/unit/build_systems/test_run_relic_table_operations.gd 等既有測試的 fixture
##    （SyntheticContentFixture 預設 claim_scope 亦為 once_per_node）都需要在實作段同步調整，
##    否則會產生新的迴歸失敗——這點在本檔範圍外，回報中另行提出，不在此處修正任何內容或既有測試。
##    （後記 2026-07-24：上述同步已於 W4-F1/F2 實作段完成——validator 允許集合含 always 並對
##    非 battle 遺物 run intent 收緊、內容與 fixture 已改 always；本檔第一個測試因此改用
##    unchecked 注入以繼續鎖定 builder 縱深判準。）

func test_builder_rejects_economy_relic_whose_only_run_intent_has_a_non_always_claim_scope() -> void:
	var registry := ContentRegistryService.new()
	add_child_autofree(registry)
	var fixture := SyntheticContentFixture.build_valid()
	var operation := AddGoldOperationDef.new()
	operation.operation_index = 0
	operation.amount = 5
	operation.claim_scope = &"once_per_node"
	var effect := EffectDef.new()
	effect.id = &"effect.non_always_claim_scope"
	effect.schema_version = 1
	effect.display_name_key = &"loc.effect_non_always_claim_scope"
	effect.content_role = &"general"
	effect.trigger = &"battle_start"
	effect.stacking = &"replace"
	effect.max_stacks = 1
	effect.duration_ticks = 1
	effect.run_operations = [operation]
	fixture.definitions.append(effect)
	var relic := _find(fixture, &"relic.r4") as RelicDef
	assert_not_null(relic)
	if relic == null:
		return
	relic.effect_refs = [&"effect.non_always_claim_scope"]
	# W4-F1/F2（2026-07-24 裁決）：validator 已同步收緊，install_validated 會在安裝階段
	# 先拒絕 once_per_node run intent；本測試鎖定的是 builder 自身判準（縱深防線），
	# 故比照同檔案族慣例改用 _install_authoring_unchecked() 繞過驗證器注入。
	var installed := registry._install_authoring_unchecked(
		fixture.definitions, "fixture.claim_scope.1", [&"pack.core"], fixture.aliases, fixture.tombstones, fixture
	)
	assert_true(installed.ok, "unchecked install should still compile a structurally well-formed record")
	if not installed.ok:
		return
	var built := RunRelicTableBuilder.new().build(
		registry, installed.handle.manifest_digest, [&"relic.r4"]
	)
	assert_false(built.ok, "a run intent whose claim_scope is not the always sentinel must be rejected by the builder")
	if built.ok:
		return
	assert_eq(built.error.code, RunRelicTableError.UNSUPPORTED_INTENT)

func test_builder_accepts_economy_relic_whose_run_intent_uses_the_always_claim_scope() -> void:
	var registry := ContentRegistryService.new()
	add_child_autofree(registry)
	var fixture := SyntheticContentFixture.build_valid()
	var operation := AddGoldOperationDef.new()
	operation.operation_index = 0
	operation.amount = 5
	operation.claim_scope = &"always"
	var effect := EffectDef.new()
	effect.id = &"effect.always_claim_scope"
	effect.schema_version = 1
	effect.display_name_key = &"loc.effect_always_claim_scope"
	effect.content_role = &"general"
	effect.trigger = &"battle_start"
	effect.stacking = &"replace"
	effect.max_stacks = 1
	effect.duration_ticks = 1
	effect.run_operations = [operation]
	fixture.definitions.append(effect)
	var relic := _find(fixture, &"relic.r4") as RelicDef
	assert_not_null(relic)
	if relic == null:
		return
	relic.effect_refs = [&"effect.always_claim_scope"]
	# 目前 content_validator.gd 的 claim_scope 允許集合不含 &"always"（見檔頭假設聲明第3點），
	# 故用 _install_authoring_unchecked 繞過驗證器直接注入，鎖定 builder 自身的判準
	# （比照 test_run_relic_table_operations.gd 的 test_builder_rejects_effect_ref_that_is_not_an_effect_definition）。
	var installed := registry._install_authoring_unchecked(
		fixture.definitions, "fixture.claim_scope.2", [&"pack.core"], fixture.aliases, fixture.tombstones, fixture
	)
	assert_true(installed.ok, "unchecked install should still compile a structurally well-formed record")
	if not installed.ok:
		return
	var built := RunRelicTableBuilder.new().build(
		registry, installed.handle.manifest_digest, [&"relic.r4"]
	)
	assert_true(
		built.ok,
		"%s" % [String(built.error.code) if not built.ok and built.error != null else "ok"]
	)

func _find(fixture: ContentValidationInput, content_id: StringName) -> ContentDefinition:
	for definition: ContentDefinition in fixture.definitions:
		if definition.id == content_id:
			return definition
	return null
