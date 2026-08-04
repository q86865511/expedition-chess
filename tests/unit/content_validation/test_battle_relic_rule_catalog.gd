extends GutTest

## T01 (specs/build-systems) — BattleRelicRule 擴充。
## Covers：REQ-RELIC-001（battle 類遺物→battle_effect_ids）、S4-AC-011（作用點基礎）。
## 依據 design.md §2「新增 BattleRelicRule（battle 類遺物→effect_ids）由 catalog builder 填入」、
## §4「BattleRelicRule.battle_effect_ids」（欄位命名以此為準）。
## 慣例沿用 domain/battle/catalog/battle_equipment_rule.gd（typed rule + deep_clone）、
## battle_rule_catalog_builder.gd 既有 try_* 存取與 category match 擴充模式。

const _RELIC_ONLY_EFFECT_ID: StringName = &"effect.relic_battle_only"

func test_battle_rule_catalog_builder_decodes_battle_relic_rule_from_pinned_manifest() -> void:
	var fixture := _fixture_with_battle_relic(&"relic.r0", [_RELIC_ONLY_EFFECT_ID])
	var registry := ContentRegistryService.new()
	add_child_autofree(registry)
	var installed := registry.install_validated(fixture, "fixture.relic_battle.1", [&"pack.core"])
	assert_true(installed.ok, "battle-category relic content should install validly")
	if not installed.ok:
		return
	var required: Array[StringName] = [&"relic.r0", &"unit.player_00"]
	var built := BattleRuleCatalogBuilder.new().build(registry, installed.handle.manifest_digest, required)
	assert_true(built.ok, "battle catalog builder should decode a battle-category relic")
	if not built.ok:
		return
	var relic_rule: BattleRelicRule = built.catalog.try_relic_rule(&"relic.r0")
	assert_not_null(relic_rule, "try_relic_rule should return the decoded rule")
	if relic_rule == null:
		return
	assert_eq(relic_rule.relic_id, &"relic.r0")
	assert_eq(relic_rule.battle_effect_ids.size(), 1)
	assert_eq(relic_rule.battle_effect_ids[0], _RELIC_ONLY_EFFECT_ID)
	# 遺物引用的 effect 必須被遞移式一併 pin 進同一份 catalog（沿用既有 trait/equipment 的遞移 pin 慣例）。
	assert_not_null(
		built.catalog.try_effect_rule(_RELIC_ONLY_EFFECT_ID),
		"effect referenced only by the relic must be transitively pinned"
	)

func test_battle_rule_catalog_legacy_construction_without_relics_has_no_relic_rules() -> void:
	# 既有呼叫端（見 tests/unit/battle_encounter/test_encounter_compiler.gd 等 6 個檔）
	# 用 8-positional-arg 呼叫 BattleRuleCatalog.new(...)，擴充後不可讓這些呼叫端炸掉：
	# relics 參數必須是有預設值的擴充欄位（catalog schema 為擴充非破壞）。
	var catalog := BattleRuleCatalog.new(
		"a".repeat(64),
		[] as Array[BattleUnitRule],
		[] as Array[BattleTraitRule],
		[] as Array[BattleAbilityRule],
		[] as Array[BattleEffectRule],
		[] as Array[BattleEncounterRule],
		[] as Array[BattleEquipmentRule],
		[] as Array[BattleCombatConfigRule]
	)
	assert_null(catalog.try_relic_rule(&"relic.anything"), "legacy 8-arg construction should have empty relic rules")

func test_battle_relic_rule_deep_clone_isolated_from_catalog_mutation() -> void:
	var fixture := _fixture_with_battle_relic(&"relic.r0", [_RELIC_ONLY_EFFECT_ID])
	var registry := ContentRegistryService.new()
	add_child_autofree(registry)
	var installed := registry.install_validated(fixture, "fixture.relic_battle.2", [&"pack.core"])
	assert_true(installed.ok)
	if not installed.ok:
		return
	var required: Array[StringName] = [&"relic.r0", &"unit.player_00"]
	var built := BattleRuleCatalogBuilder.new().build(registry, installed.handle.manifest_digest, required)
	assert_true(built.ok)
	if not built.ok:
		return
	var first: BattleRelicRule = built.catalog.try_relic_rule(&"relic.r0")
	assert_not_null(first)
	if first == null:
		return
	first.battle_effect_ids.append(&"effect.tampered")
	var second: BattleRelicRule = built.catalog.try_relic_rule(&"relic.r0")
	assert_not_null(second)
	if second == null:
		return
	assert_eq(second.battle_effect_ids.size(), 1, "mutating a fetched copy must not leak into the catalog's stored state")

func test_battle_relic_rule_only_resolves_from_pinned_manifest_digest() -> void:
	var fixture := _fixture_with_battle_relic(&"relic.r0", [_RELIC_ONLY_EFFECT_ID])
	var registry := ContentRegistryService.new()
	add_child_autofree(registry)
	var installed := registry.install_validated(fixture, "fixture.relic_battle.3", [&"pack.core"])
	assert_true(installed.ok)
	if not installed.ok:
		return
	var required: Array[StringName] = [&"relic.r0"]
	var wrong_digest := "f".repeat(64)
	var built := BattleRuleCatalogBuilder.new().build(registry, wrong_digest, required)
	assert_false(built.ok, "a battle relic rule must not fall through to the latest/unpinned generation")
	assert_eq(built.error.code, BattleRuleCatalogError.RESOLVE_FAILED)

func _fixture_with_battle_relic(relic_id: StringName, effect_ids: Array[StringName]) -> ContentValidationInput:
	var fixture := SyntheticContentFixture.build_valid()
	var relic: RelicDef = null
	for definition: ContentDefinition in fixture.definitions:
		if definition.id == relic_id:
			relic = definition as RelicDef
			break
	assert_not_null(relic, "fixture must already contain %s" % relic_id)
	relic.category = &"battle"
	relic.effect_refs = effect_ids.duplicate()
	for effect_id: StringName in effect_ids:
		var already_present := false
		for definition: ContentDefinition in fixture.definitions:
			if definition.id == effect_id:
				already_present = true
				break
		if not already_present:
			fixture.definitions.append(_minimal_effect(effect_id))
	return fixture

func _minimal_effect(content_id: StringName) -> EffectDef:
	var value := EffectDef.new()
	value.id = content_id
	value.schema_version = 2
	value.display_name_key = StringName("loc.%s" % String(content_id))
	value.content_role = &"general"
	value.trigger = &"battle_start"
	value.stacking = &"replace"
	value.max_stacks = 1
	value.duration_ticks = 1
	value.description_key = StringName(
		"loc.%s.description" % String(content_id)
	)
	var damage := DamageOperationDef.new()
	damage.operation_index = 0
	damage.base = 0
	damage.scaling = &"flat"
	damage.damage_type = &"physical"
	damage.target = &"all_enemies"
	value.battle_operations = [damage]
	return value
