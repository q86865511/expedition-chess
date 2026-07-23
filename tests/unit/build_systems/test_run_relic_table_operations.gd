extends GutTest

## T06 (specs/build-systems) — RunRelicTable 的 run-layer typed intent 解碼與槽序消費。
## Covers：REQ-RELIC-001、S4-AC-011（經濟/路線/規則類遺物的 effect_refs 須落在 RunRelicTable
## 支援的 kind，並依 slot_index 升序提供給各 run-layer service 消費）。
## 依據 design.md §6「作用點統一由 RunRelicTable 提供 typed intent（非 Dictionary），
## 觸發序＝slot_index 升序」；§7 規則(c)「非 battle 類的 run effect intent 落在 RunRelicTable
## 支援 kind」（content_validator.gd 只驗證 run_operations 非空，未鎖定具體 kind 集合——
## test_content_validator_build_systems.gd:161-167 已確認)。
##
## 假設聲明（design.md 未給 typed intent 的精確欄位形狀，本檔延續 T01 的「最小可驗證」慣例，
## 並直接重用本專案既有的 EffectDef.run_operations 詞彙——add_gold/add_xp/heal_expedition_hp，
## 這三種 kind 已由 content_definition_compiler.gd（_run_operation, 0x3101-0x3103）與
## battle_rule_catalog_builder.gd（_decode_run_operation）雙向支援，SyntheticContentFixture 的
## effect.operation_matrix 也已內建三者各一筆，是本片新增 typed intent 的最低風險落點）：
## 1. 新增 RunRelicOperationRule{operation_index, kind, amount, claim_scope}（RefCounted,
##    deep_clone()）——鏡射既有 BattleRunOperationRule 的形狀。
## 2. RunRelicRule 新增欄位 run_operations: Array[RunRelicOperationRule]（additive，
##    不動 T01 鎖定的 relic_id/category/effect_ids 斷言）。
## 3. RunRelicTableBuilder 對每個非 battle 遺物，除既有 effect_ids 擷取外，另對每個
##    effect_id 呼叫 registry.resolve() 取得其 EffectDef payload（category == &"effect"，
##    record_type == ContentCategory.EFFECT，children.size() == 12），解碼 children[8]
##    （run_operations 清單，形狀同 battle_rule_catalog_builder._decode_run_operation：
##    record_type ∈ {0x3101 add_gold, 0x3102 add_xp, 0x3103 heal_expedition_hp}，
##    children = [operation_index, amount, claim_scope]），彙整進 rule.run_operations。
##    effect_id 解不到、非 &"effect" 分類、或 payload 形狀不符 → build 失敗
##    （RunRelicTableError.PAYLOAD_INVALID, field_path &"relic.run_operations"）。
## 4. RunRelicTable 新增 ordered_rules(active_relic_ids: Array[StringName]) ->
##    Array[RunRelicRule]：依呼叫端傳入順序（呼叫端負責依 RosterState.active_relic_slots
##    的 slot_index 升序排列）回傳對應規則，找不到的 id 靜默略過（不報錯、不中斷）。
## 5. 新增 RunRelicActivation（domain/run/build/run_relic_activation.gd）static
##    active_ids_in_slot_order(slots: Array[RelicSlotState]) -> Array[StringName]：
##    依 slot_index 數值升序（非陣列既有順序）回傳非空槽位的 relic_id，讓「slot_index 升序」
##    可直接從 RosterState 的真實型別推導，不需呼叫端自行排序。
##
## 範圍聲明：RunController／各 command 呼叫端如何把 active_relic_slots 接到
## IncomeService/ShopService/MapService/BattleSettlementService 的實際呼叫（composition-root
## 接線）不在本檔鎖定範圍——tasks.md 的相依圖顯示 T10（ViewModel）才整合 T02~T06，
## 本檔只鎖定 T06 自身的 table/service 級契約。

func test_builder_decodes_run_operations_from_referenced_effect_for_economy_relic() -> void:
	var registry := ContentRegistryService.new()
	add_child_autofree(registry)
	var fixture := SyntheticContentFixture.build_valid()
	var installed := registry.install_validated(fixture, "fixture.run_relic_ops.1", [&"pack.core"])
	assert_true(installed.ok)
	if not installed.ok:
		return
	var built := RunRelicTableBuilder.new().build(
		registry, installed.handle.manifest_digest, _non_battle_relic_ids()
	)
	assert_true(built.ok, "run relic table should decode run_operations from effect.operation_matrix")
	if not built.ok:
		return
	var rule: RunRelicRule = built.table.try_relic_rule(&"relic.r4")
	assert_not_null(rule)
	if rule == null:
		return
	assert_eq(rule.category, &"economy")
	assert_eq(rule.run_operations.size(), 3, "effect.operation_matrix carries add_gold/add_xp/heal_expedition_hp")
	for operation: RunRelicOperationRule in rule.run_operations:
		assert_true(operation is RunRelicOperationRule, "run_operations entries must be a named type, not a Dictionary")
	var by_kind: Dictionary = {}
	for operation: RunRelicOperationRule in rule.run_operations:
		by_kind[operation.kind] = operation
	assert_true(by_kind.has(&"add_gold"))
	assert_true(by_kind.has(&"add_xp"))
	assert_true(by_kind.has(&"heal_expedition_hp"))
	if by_kind.has(&"add_gold"):
		var add_gold: RunRelicOperationRule = by_kind[&"add_gold"]
		assert_eq(add_gold.operation_index, 0)
		assert_eq(add_gold.amount, 1)
		# W4-F1（2026-07-24）：斷言語意不變——驗證 builder 保真回傳 effect 宣告的 claim_scope。
		# fixture 的 effect.operation_matrix 因新規則改宣告 &"always"（非 battle 遺物 run intent
		# 必須 always），斷言值隨之同步；仍鎖定「解碼保真」而非放寬。
		assert_eq(add_gold.claim_scope, &"always")

func test_builder_run_operations_isolated_from_lookup_mutation() -> void:
	var registry := ContentRegistryService.new()
	add_child_autofree(registry)
	var fixture := SyntheticContentFixture.build_valid()
	var installed := registry.install_validated(fixture, "fixture.run_relic_ops.2", [&"pack.core"])
	assert_true(installed.ok)
	if not installed.ok:
		return
	var built := RunRelicTableBuilder.new().build(
		registry, installed.handle.manifest_digest, _non_battle_relic_ids()
	)
	assert_true(built.ok)
	if not built.ok:
		return
	var first := built.table.try_relic_rule(&"relic.r4")
	assert_not_null(first)
	if first == null:
		return
	var stray := RunRelicOperationRule.new()
	stray.operation_index = 99
	stray.kind = &"add_gold"
	stray.amount = 999
	stray.claim_scope = &"tampered"
	first.run_operations.append(stray)
	var second := built.table.try_relic_rule(&"relic.r4")
	assert_not_null(second)
	if second == null:
		return
	assert_eq(second.run_operations.size(), 3, "mutating a fetched rule's run_operations must not leak into the table's stored state")

func test_builder_rejects_effect_ref_that_is_not_an_effect_definition() -> void:
	# CONTENT_RELIC_EFFECT_SCOPE（test_content_validator_build_systems.gd:176-183）已鎖定
	# ContentValidator 對此形狀的內容拒收，install_validated() 走完整驗證會在到達 builder
	# 之前就失敗。本測試驗證的是 builder 自身的縱深防禦（已通過驗證的舊內容 fallback），
	# 故比照 test_forge_recipe_table.gd 的
	# test_forge_recipe_table_builder_rejects_component_pair_outside_one_or_two_shape，
	# 改用 _install_authoring_unchecked() 繞過驗證器注入該非法內容。
	var registry := ContentRegistryService.new()
	add_child_autofree(registry)
	var fixture := SyntheticContentFixture.build_valid()
	var relic := _find(fixture, &"relic.r4") as RelicDef
	assert_not_null(relic)
	if relic == null:
		return
	relic.effect_refs = [&"item_component.c0"]
	var installed := registry._install_authoring_unchecked(
		fixture.definitions, "fixture.run_relic_ops.3", [&"pack.core"], fixture.aliases, fixture.tombstones, fixture
	)
	assert_true(installed.ok, "unchecked install should still compile a structurally well-formed record")
	if not installed.ok:
		return
	var built := RunRelicTableBuilder.new().build(
		registry, installed.handle.manifest_digest, _non_battle_relic_ids()
	)
	assert_false(built.ok, "a relic effect_ref that does not resolve to an EffectDef must fail the build")
	assert_eq(built.error.code, RunRelicTableError.PAYLOAD_INVALID)

func test_ordered_rules_preserves_caller_supplied_order_and_skips_unknown_ids() -> void:
	var registry := ContentRegistryService.new()
	add_child_autofree(registry)
	var fixture := SyntheticContentFixture.build_valid()
	var installed := registry.install_validated(fixture, "fixture.run_relic_ops.4", [&"pack.core"])
	assert_true(installed.ok)
	if not installed.ok:
		return
	var built := RunRelicTableBuilder.new().build(
		registry, installed.handle.manifest_digest, _non_battle_relic_ids()
	)
	assert_true(built.ok)
	if not built.ok:
		return
	var requested: Array[StringName] = [&"relic.r11", &"relic.r7", &"relic.does_not_exist", &"relic.r9"]
	var ordered := built.table.ordered_rules(requested)
	assert_eq(ordered.size(), 3, "unknown ids must be skipped, not raise or short-circuit")
	assert_eq(ordered[0].relic_id, &"relic.r11")
	assert_eq(ordered[1].relic_id, &"relic.r7")
	assert_eq(ordered[2].relic_id, &"relic.r9")

func test_active_relic_ids_are_derived_in_ascending_slot_index_order_regardless_of_array_position() -> void:
	var slots: Array[RelicSlotState] = [
		RelicSlotState.new(4, OptionalStringNameValue.of(&"relic.slot4")),
		RelicSlotState.new(1, OptionalStringNameValue.of(&"relic.slot1")),
		RelicSlotState.new(0, null),
		RelicSlotState.new(3, OptionalStringNameValue.of(&"relic.slot3")),
		RelicSlotState.new(2, null),
	]
	var ordered_ids := RunRelicActivation.active_ids_in_slot_order(slots)
	assert_eq(ordered_ids, [&"relic.slot1", &"relic.slot3", &"relic.slot4"])

## W2-F2（死內容防禦）：非 battle 遺物的 run intent 若沒有任何一筆落在該 category
## 實際消費端的支援 (category, kind) 集合，其效果永遠不會被讀取（死內容）→ build 失敗
## 回具名 error RunRelicTableError.UNSUPPORTED_INTENT。此處以「economy 遺物只帶 add_xp」
## （economy 僅支援 add_gold/shop_discount）驗證拒絕路徑；同載多 kind 只要其一受支援即
## 放行的 alive 判準已由 test_builder_decodes_run_operations_from_referenced_effect_for_economy_relic
## （economy 遺物同載 add_gold/add_xp/heal_expedition_hp 仍 build.ok）鎖定。
func test_builder_rejects_relic_whose_run_intents_are_all_unsupported_for_its_category() -> void:
	var registry := ContentRegistryService.new()
	add_child_autofree(registry)
	var fixture := SyntheticContentFixture.build_valid()
	var dead_operation := AddXpOperationDef.new()
	dead_operation.operation_index = 0
	dead_operation.amount = 1
	dead_operation.claim_scope = &"always"
	var dead_effect := EffectDef.new()
	dead_effect.id = &"effect.dead_economy_intent"
	dead_effect.schema_version = 1
	dead_effect.display_name_key = &"loc.effect_dead_economy_intent"
	dead_effect.content_role = &"general"
	dead_effect.trigger = &"battle_start"
	dead_effect.stacking = &"replace"
	dead_effect.max_stacks = 1
	dead_effect.duration_ticks = 1
	dead_effect.run_operations = [dead_operation]
	fixture.definitions.append(dead_effect)
	# relic.r4 為 economy 類；改指向只帶 add_xp 的 effect，使其 run intent 全數不受支援。
	var relic := _find(fixture, &"relic.r4") as RelicDef
	assert_not_null(relic)
	if relic == null:
		return
	relic.effect_refs = [&"effect.dead_economy_intent"]
	var installed := registry.install_validated(fixture, "fixture.run_relic_ops.5", [&"pack.core"])
	assert_true(installed.ok, "economy×add_xp 為合法內容形狀（驗證器不鎖 category-kind），應可安裝")
	if not installed.ok:
		return
	var built := RunRelicTableBuilder.new().build(
		registry, installed.handle.manifest_digest, [&"relic.r4"]
	)
	assert_false(built.ok, "an economy relic whose only run intent is add_xp is dead content and must fail the build")
	assert_eq(built.error.code, RunRelicTableError.UNSUPPORTED_INTENT)

func _non_battle_relic_ids() -> Array[StringName]:
	var result: Array[StringName] = []
	for index in range(4, 15):
		result.append(StringName("relic.r%d" % index))
	return result

func _find(fixture: ContentValidationInput, content_id: StringName) -> ContentDefinition:
	for definition: ContentDefinition in fixture.definitions:
		if definition.id == content_id:
			return definition
	return null
