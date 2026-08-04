extends GutTest

## T01 (specs/build-systems) — RunRelicTable。
## Covers：REQ-RELIC-001、S4-AC-011（經濟/路線/規則類遺物→typed intent，依 category 分類；
## battle 類遺物不在此表產出，於 BattleRelicRule/battle catalog 作用，見 §4/§6）。
## 依據 design.md §3「RunRelicTable（relic_id -> {category, run effect intents}）」、
## §6「作用點統一由 RunRelicTable 提供 typed intent（非 Dictionary）」。
##
## 假設聲明（design.md 未給 typed intent 的精確欄位形狀，本檔採最小、可驗證、與
## BattleRelicRule.battle_effect_ids 對稱的介面：RunRelicRule{relic_id, category, effect_ids}；
## 「intent 如何在各 run-layer service 被解讀」屬 T06 範疇，不在此鎖定)。

func test_run_relic_table_builder_categorizes_relics_and_excludes_battle_category() -> void:
	var registry := ContentRegistryService.new()
	add_child_autofree(registry)
	var fixture := _fixture_with_categorized_relics()
	var installed := registry.install_validated(fixture, "fixture.run_relic.1", [&"pack.core"])
	assert_true(installed.ok)
	if not installed.ok:
		return
	var built := RunRelicTableBuilder.new().build(
		registry, installed.handle.manifest_digest, _non_battle_relic_ids()
	)
	assert_true(built.ok, "run relic table should decode economy/route/rule relics from the pinned generation")
	if not built.ok:
		return
	assert_eq(built.table.manifest_digest_value(), installed.handle.manifest_digest)
	assert_eq(built.table.rules_for_category(&"economy").size(), 5)
	assert_eq(built.table.rules_for_category(&"route").size(), 5)
	assert_eq(built.table.rules_for_category(&"rule").size(), 4)
	assert_eq(
		built.table.rules_for_category(&"battle").size(), 0,
		"battle-category relics must never surface through RunRelicTable"
	)

func test_run_relic_table_builder_rejects_battle_category_relic_id() -> void:
	var registry := ContentRegistryService.new()
	add_child_autofree(registry)
	var fixture := _fixture_with_categorized_relics()
	var installed := registry.install_validated(fixture, "fixture.run_relic.2", [&"pack.core"])
	assert_true(installed.ok)
	if not installed.ok:
		return
	var built := RunRelicTableBuilder.new().build(
		registry, installed.handle.manifest_digest, [&"relic.r14"]
	)
	assert_false(built.ok, "a battle-category relic id must not be accepted by RunRelicTableBuilder")
	assert_eq(built.error.code, RunRelicTableError.CATEGORY_MISMATCH)

func test_run_relic_table_try_rule_returns_typed_non_dictionary_intent() -> void:
	var registry := ContentRegistryService.new()
	add_child_autofree(registry)
	var fixture := _fixture_with_categorized_relics()
	var installed := registry.install_validated(fixture, "fixture.run_relic.3", [&"pack.core"])
	assert_true(installed.ok)
	if not installed.ok:
		return
	var built := RunRelicTableBuilder.new().build(
		registry, installed.handle.manifest_digest, _non_battle_relic_ids()
	)
	assert_true(built.ok)
	if not built.ok:
		return
	var rule: RunRelicRule = built.table.try_relic_rule(&"relic.r0")
	assert_not_null(rule)
	if rule == null:
		return
	assert_true(rule is RunRelicRule, "RunRelicTable must return a named type, not a raw Dictionary")
	assert_eq(rule.relic_id, &"relic.r0")
	assert_eq(rule.category, &"economy")
	var expected_def := _find_relic_def(fixture, &"relic.r0")
	assert_not_null(expected_def, "fixture must define relic.r0")
	if expected_def == null:
		return
	assert_eq(rule.effect_ids.size(), expected_def.effect_refs.size())
	for index in rule.effect_ids.size():
		assert_eq(rule.effect_ids[index], expected_def.effect_refs[index])
	assert_null(built.table.try_relic_rule(&"relic.does_not_exist"))

func test_run_relic_table_only_resolves_from_pinned_manifest_digest() -> void:
	var registry := ContentRegistryService.new()
	add_child_autofree(registry)
	var fixture := _fixture_with_categorized_relics()
	var installed := registry.install_validated(fixture, "fixture.run_relic.4", [&"pack.core"])
	assert_true(installed.ok)
	if not installed.ok:
		return
	var wrong_digest := "f".repeat(64)
	var built := RunRelicTableBuilder.new().build(registry, wrong_digest, _non_battle_relic_ids())
	assert_false(built.ok, "run relic table must not fall through to the latest/unpinned generation")
	assert_eq(built.error.code, RunRelicTableError.RESOLVE_FAILED)

func test_run_relic_table_deep_clone_isolated_from_lookup_mutation() -> void:
	var registry := ContentRegistryService.new()
	add_child_autofree(registry)
	var fixture := _fixture_with_categorized_relics()
	var installed := registry.install_validated(fixture, "fixture.run_relic.5", [&"pack.core"])
	assert_true(installed.ok)
	if not installed.ok:
		return
	var built := RunRelicTableBuilder.new().build(
		registry, installed.handle.manifest_digest, _non_battle_relic_ids()
	)
	assert_true(built.ok)
	if not built.ok:
		return
	var first := built.table.try_relic_rule(&"relic.r0")
	assert_not_null(first)
	if first == null:
		return
	first.effect_ids.append(&"effect.tampered")
	var second := built.table.try_relic_rule(&"relic.r0")
	assert_not_null(second)
	if second == null:
		return
	assert_eq(second.effect_ids.size(), 1, "mutating a fetched rule must not leak into the table's stored state")

## relic.r0..r4 -> economy(5)、relic.r5..r9 -> route(5)、relic.r10..r13 -> rule(4)、
## relic.r14 -> battle(1)。共 15 件、四類皆 >=1，對應 S4-AC-011。
func _fixture_with_categorized_relics() -> ContentValidationInput:
	var fixture := SyntheticContentFixture.build_valid()
	for definition: ContentDefinition in fixture.definitions:
		if not (definition is RelicDef):
			continue
		var relic := definition as RelicDef
		var index := _relic_index(relic.id)
		if index < 0:
			continue
		relic.category = _category_for_index(index)
		if relic.category == &"battle":
			relic.effect_refs = [&"effect.global_battle"]
		else:
			relic.effect_refs = [&"effect.operation_matrix"]
	return fixture

func _non_battle_relic_ids() -> Array[StringName]:
	var result: Array[StringName] = []
	for index in 14:
		result.append(StringName("relic.r%d" % index))
	return result

func _category_for_index(index: int) -> StringName:
	if index < 5: return &"economy"
	if index < 10: return &"route"
	if index < 14: return &"rule"
	return &"battle"

func _find_relic_def(fixture: ContentValidationInput, relic_id: StringName) -> RelicDef:
	for definition: ContentDefinition in fixture.definitions:
		if definition is RelicDef and (definition as RelicDef).id == relic_id:
			return definition as RelicDef
	return null

func _relic_index(content_id: StringName) -> int:
	var text := String(content_id)
	if not text.begins_with("relic.r"):
		return -1
	return text.substr(7).to_int()
