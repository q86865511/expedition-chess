extends GutTest

func test_content_v2_compiles_combat_config_and_boss_source_round_trip() -> void:
	var fixture := SyntheticContentFixture.build_valid()
	var config: CombatConfigDef = _definition(fixture, &"config.combat_default") as CombatConfigDef
	var encounter: EncounterDef = _definition(fixture, &"encounter.boss_0") as EncounterDef
	assert_not_null(config)
	assert_not_null(encounter)
	var compiler := ContentDefinitionCompilerV2.new()
	var codec := ContentCanonicalCodecV2.new()
	var compiled_config := compiler.compile(config)
	var compiled_encounter := compiler.compile(encounter)
	assert_true(compiled_config.ok)
	assert_true(compiled_encounter.ok)
	if not compiled_config.ok or not compiled_encounter.ok:
		return
	assert_eq(compiled_config.entry.payload.record_type, ContentCategory.COMBAT_CONFIG)
	# DC-REQ-001 重算：26 個既有純量 + 3 個 per-act 敵方成長乘數 + 3 個共用欄位。
	assert_eq(compiled_config.entry.payload.children.size(), 32)
	var encoded_config := codec.encode_entry(compiled_config.entry)
	var encoded_encounter := codec.encode_entry(compiled_encounter.entry)
	assert_true(encoded_config.ok)
	assert_true(encoded_encounter.ok)
	assert_eq(codec.decode_entry(encoded_config.canonical_bytes).entry.payload.children.size(), 32)
	var decoded_encounter := codec.decode_entry(encoded_encounter.canonical_bytes)
	assert_true(decoded_encounter.ok)
	if decoded_encounter.ok:
		var phase: ContentValue = decoded_encounter.entry.payload.children[7].children[0]
		assert_eq(phase.children[2].string_value, "boss_0")
		assert_eq(codec.encode_entry(decoded_encounter.entry).canonical_bytes, encoded_encounter.canonical_bytes)

func test_battle_rule_catalog_is_pinned_transitive_and_clone_isolated() -> void:
	var registry := ContentRegistryService.new()
	add_child_autofree(registry)
	var installed := registry.install_validated(
		SyntheticContentFixture.build_valid(),
		"fixture.1",
		[&"pack.core"]
	)
	assert_true(installed.ok, "valid v2 catalog should install")
	if not installed.ok:
		return
	var required: Array[StringName] = [
		&"encounter.boss_0",
		&"equipment.c0_c0",
		&"unit.player_00",
	]
	var built := BattleRuleCatalogBuilder.new().build(
		registry,
		installed.handle.manifest_digest,
		required
	)
	assert_true(built.ok, "battle closure should decode from pinned generation")
	if not built.ok:
		return
	assert_eq(built.catalog.manifest_digest_value(), installed.handle.manifest_digest)
	var config := built.catalog.try_combat_config_rule(&"config.combat_default")
	var encounter := built.catalog.try_encounter_rule(&"encounter.boss_0")
	var equipment := built.catalog.try_equipment_rule(&"equipment.c0_c0")
	assert_not_null(config)
	assert_not_null(encounter)
	assert_not_null(equipment)
	assert_eq(config.tick_rate, 20)
	assert_eq(encounter.boss_phases[0].source_spawn_key, "boss_0")
	assert_not_null(built.catalog.try_effect_rule(&"effect.general"), "transitive effect should be pinned")
	assert_not_null(built.catalog.try_trait_rule(&"trait.faction_0"), "condition reference should be pinned")
	config.tick_rate = 999
	encounter.boss_phases[0].source_spawn_key = "tampered"
	assert_eq(built.catalog.try_combat_config_rule(&"config.combat_default").tick_rate, 20)
	assert_eq(built.catalog.try_encounter_rule(&"encounter.boss_0").boss_phases[0].source_spawn_key, "boss_0")
	var inputs := BattleSetupInputs.new()
	inputs.manifest_digest = StringName(installed.handle.manifest_digest)
	inputs.encounter_snapshot = EncounterPreviewSnapshot.new()
	inputs.encounter_snapshot.manifest_digest = inputs.manifest_digest
	var summoner := UnitBattleSnapshot.new()
	summoner.ability_id = OptionalStringNameValue.of(&"ability.summon")
	inputs.encounter_snapshot.enemy_units.append(summoner)
	var closure := BattleRulesSnapshotBuilder.new().build(
		built.catalog, inputs, 1, &"boss"
	)
	assert_true(closure.ok, "summon closure should build only from pinned rules")
	if closure.ok:
		assert_eq(closure.snapshot.summoned_unit_templates.size(), 1)
		assert_eq(closure.snapshot.summoned_unit_templates[0].unit_id, &"unit.monster_01")
		assert_eq(closure.snapshot.ability_rules[0].ability_id, &"ability.summon")
		assert_eq(closure.snapshot.effect_rules[0].effect_id, &"effect.summon")
	var wrong_generation := inputs.deep_clone()
	wrong_generation.manifest_digest = StringName("f".repeat(64))
	var rejected := BattleRulesSnapshotBuilder.new().build(
		built.catalog, wrong_generation, 1, &"boss"
	)
	assert_false(rejected.ok)
	assert_eq(rejected.error.code, BattleRulesSnapshotBuildError.GENERATION_MISMATCH)

func test_battle_rule_catalog_never_falls_through_to_latest_generation() -> void:
	var registry := ContentRegistryService.new()
	add_child_autofree(registry)
	var fixture_a := SyntheticContentFixture.build_valid()
	var installed_a := registry.install_validated(fixture_a, "fixture.1", [&"pack.core"])
	assert_true(installed_a.ok)
	if not installed_a.ok:
		return
	var fixture_b := SyntheticContentFixture.build_valid()
	var config_b: CombatConfigDef = _definition(fixture_b, &"config.combat_default") as CombatConfigDef
	config_b.attack_mana_gain = 11
	var installed_b := registry.install_validated(fixture_b, "fixture.2", [&"pack.core"])
	assert_true(installed_b.ok)
	if not installed_b.ok:
		return
	var required: Array[StringName] = [&"unit.player_00"]
	var catalog_a := BattleRuleCatalogBuilder.new().build(registry, installed_a.handle.manifest_digest, required)
	var catalog_b := BattleRuleCatalogBuilder.new().build(registry, installed_b.handle.manifest_digest, required)
	assert_true(catalog_a.ok)
	assert_true(catalog_b.ok)
	if catalog_a.ok and catalog_b.ok:
		assert_eq(catalog_a.catalog.try_combat_config_rule(&"config.combat_default").attack_mana_gain, 10)
		assert_eq(catalog_b.catalog.try_combat_config_rule(&"config.combat_default").attack_mana_gain, 11)

## T25 M5 修正防回歸:codec 3(resource_schema_version==2)的 UNIT/EFFECT payload
## 必須是唯一 exact arity(多 presentation_ref 等新欄位共 14/13 children),不得
## 同時放行 n 與 n+1——缺欄位的 schema 2 payload 不可被靜默當成 codec 2(schema 1)
## 形狀接受。直接呼叫 _payload_is 隔離測試,避免需經過完整 registry/codec 管線
## 才能構造出「結構合法但缺欄位」的 payload(該管線本身的 arity 檢查會先擋下)。
func test_battle_rule_catalog_payload_arity_is_exact_per_resource_schema_version() -> void:
	var builder := BattleRuleCatalogBuilder.new()

	var schema1_unit := _fake_view(&"unit.schema1", ContentCategory.UNIT, 1, 13)
	assert_true(builder.call(&"_payload_is", schema1_unit, ContentCategory.UNIT, 13))

	var schema2_unit := _fake_view(&"unit.schema2", ContentCategory.UNIT, 2, 14)
	assert_true(builder.call(&"_payload_is", schema2_unit, ContentCategory.UNIT, 13))

	var schema2_unit_missing_presentation_ref := \
		_fake_view(&"unit.broken", ContentCategory.UNIT, 2, 13)
	assert_false(
		builder.call(&"_payload_is", schema2_unit_missing_presentation_ref, ContentCategory.UNIT, 13),
		"schema 2 UNIT payload missing presentation_ref must be rejected, not accepted as schema 1 shape"
	)

	var schema1_effect := _fake_view(&"effect.schema1", ContentCategory.EFFECT, 1, 12)
	assert_true(builder.call(&"_payload_is", schema1_effect, ContentCategory.EFFECT, 12))

	var schema2_effect := _fake_view(&"effect.schema2", ContentCategory.EFFECT, 2, 13)
	assert_true(builder.call(&"_payload_is", schema2_effect, ContentCategory.EFFECT, 12))

	var schema2_effect_missing_field := _fake_view(&"effect.broken", ContentCategory.EFFECT, 2, 12)
	assert_false(
		builder.call(&"_payload_is", schema2_effect_missing_field, ContentCategory.EFFECT, 12),
		"schema 2 EFFECT payload missing its extra field must be rejected, not accepted as schema 1 shape"
	)


## T25 L1 修正防回歸:ability primary effect 被 battle_setup_source_compiler.gd／
## encounter_compiler.gd 併入 unit 的被動 effect source,故解析出的 EffectDef 必須
## trigger==cast,否則同一效果會同時被動與 cast 觸發。此處以 SyntheticContentFixture
## 的既有 ability.summon/effect.summon 為底,竄改 trigger 驗證 builder 在內容安裝期
## fail-closed(對照組維持預設 cast 應成功)。
func test_battle_rule_catalog_rejects_non_cast_trigger_for_ability_primary_effect() -> void:
	var registry := ContentRegistryService.new()
	add_child_autofree(registry)
	var fixture := SyntheticContentFixture.build_valid()
	(_definition(fixture, &"effect.summon") as EffectDef).trigger = &"battle_start"
	var installed := registry.install_validated(fixture, "fixture.trigger", [&"pack.core"])
	assert_true(installed.ok, "fixture with mutated trigger should still install")
	if not installed.ok:
		return
	var rejected := BattleRuleCatalogBuilder.new().build(
		registry, installed.handle.manifest_digest, [&"ability.summon"]
	)
	assert_false(rejected.ok, "non-cast trigger ability primary effect must fail-closed")
	if not rejected.ok:
		assert_eq(rejected.error.code, BattleRuleCatalogError.ABILITY_EFFECT_TRIGGER_INVALID)

	var control_fixture := SyntheticContentFixture.build_valid()
	var control_installed := registry.install_validated(
		control_fixture, "fixture.trigger.control", [&"pack.core"]
	)
	assert_true(control_installed.ok)
	if not control_installed.ok:
		return
	var accepted := BattleRuleCatalogBuilder.new().build(
		registry, control_installed.handle.manifest_digest, [&"ability.summon"]
	)
	assert_true(accepted.ok, "default cast-trigger ability primary effect should still build")


func _fake_view(
	content_id: StringName,
	type_id: int,
	schema_version: int,
	child_count: int
) -> ContentDefinitionView:
	var children: Array[ContentValue] = []
	for _index in range(child_count):
		children.append(ContentValue.u32(0))
	var view := ContentDefinitionView.new()
	view.content_id = content_id
	view.resource_schema_version = schema_version
	view.payload = ContentValue.record(type_id, PackedInt32Array(), children)
	return view


func _definition(input: ContentValidationInput, content_id: StringName) -> ContentDefinition:
	for definition: ContentDefinition in input.definitions:
		if definition.id == content_id:
			return definition
	return null
