extends GutTest

## W4 雙審修正（F1／F2，2026-07-25）——軌 A 的真實 BattleRuleCatalogBuilder 路徑。
## Covers：S5-AC-010（軌 A：挑戰詞綴進 encounter 實際生效）；design.md §6.3。
##
## T07 既有的軌 A 測試都用手工組出的 BattleRuleCatalog（test_challenge_affix_end_to_end.gd:285
## 的 _battle_catalog、test_encounter_compiler_challenge_affixes.gd:143 的 _catalog）繞過真實
## builder，因此兩個缺口沒有任何測試釘住：
## 1. F1：global source lifecycle 已裁決 challenge affix 不得同時攜帶 battle/run operations；
##    舊雙軌 fixture 必須在 content boundary fail-closed，而不是要求 battle catalog 解碼 run track。
## 2. F2：可達性走訪不含 unlock 分支，challenge 詞綴 effect 進不了 required_ids →
##    EncounterCompiler._compile_affixes 回 ENCOUNTER_RULE_MISSING。
##
## 內容一律用 SyntheticContentFixture 的既有 challenge 鏈（unlock.challenge_1..5 →
## effect.challenge_affix_0..4，其中 0..2 為軌 A、3＝ShopSurcharge、4＝DrainExpeditionHp），
## 只在需要時就地擴充，避免另造一套與正式內容形狀不同的挑戰鏈。

const BATTLE_AFFIX_ID: StringName = &"effect.challenge_affix_0"
const RUN_ONLY_AFFIX_ID: StringName = &"effect.challenge_affix_3"
const BATTLE_AFFIX_UNLOCK_ID: StringName = &"unlock.slice_challenge_1"
const RUN_ONLY_AFFIX_UNLOCK_ID: StringName = &"unlock.slice_challenge_4"
const ENCOUNTER_ID: StringName = &"encounter.normal"
const NODE_ID: StringName = &"node_fixture_0000000000000000000000000000000000000000000000000000"

func test_dual_track_challenge_affix_is_rejected_at_content_boundary() -> void:
	# BP-SI-001：challenge effect 的來源生命週期只能有一條；雙軌內容不得進 registry。
	var registry := _registry()
	var installed := registry.install_validated(
		_fixture_with_dual_track_affix(), "fixture.dual_track_affix.1", [&"pack.core"]
	)
	assert_false(installed.ok, "雙軌 challenge affix 必須在 content boundary 被拒絕")
	assert_eq(
		installed.error.code if not installed.ok else &"",
		&"CONTENT_EFFECT_SOURCE_LIFECYCLE",
		"不得把 challenge run_operations 帶進 battle catalog 後才處理"
	)

func test_challenge_unlock_pins_track_a_affix_effect_into_catalog() -> void:
	# F2 的失敗情境：required_ids 只放 challenge unlock（T11 接線後的實際形狀），
	# 詞綴 effect 必須由 unlock.modifier_refs 遞移 pin 進來。
	var registry := _registry()
	var installed := registry.install_validated(
		_fixture_with_slice_challenge_chain(), "fixture.challenge_catalog.1", [&"pack.core"]
	)
	assert_true(installed.ok)
	if not installed.ok:
		return
	var required: Array[StringName] = [BATTLE_AFFIX_UNLOCK_ID, ENCOUNTER_ID]
	var built := BattleRuleCatalogBuilder.new().build(
		registry, installed.handle.manifest_digest, required
	)
	assert_true(built.ok, _build_error_text(built))
	if not built.ok:
		return
	assert_not_null(
		built.catalog.try_effect_rule(BATTLE_AFFIX_ID),
		"challenge unlock 的軌 A 詞綴必須遞移 pin 進 battle catalog"
	)

func test_run_only_challenge_affix_is_not_pinned_into_battle_catalog() -> void:
	# 軌 B 詞綴（純 run_operations）由 run 層消費，不屬戰鬥規則：走訪只放行軌 A。
	var registry := _registry()
	var installed := registry.install_validated(
		_fixture_with_slice_challenge_chain(), "fixture.challenge_catalog.2", [&"pack.core"]
	)
	assert_true(installed.ok)
	if not installed.ok:
		return
	var required: Array[StringName] = [RUN_ONLY_AFFIX_UNLOCK_ID]
	var built := BattleRuleCatalogBuilder.new().build(
		registry, installed.handle.manifest_digest, required
	)
	assert_true(built.ok, _build_error_text(built))
	if not built.ok:
		return
	assert_null(
		built.catalog.try_effect_rule(RUN_ONLY_AFFIX_ID),
		"純 run 軌詞綴不得被灌進 battle catalog"
	)

func test_track_a_affix_compiles_into_encounter_through_real_builder_path() -> void:
	# 軌 A 全鏈：ChallengeAffixResolver → required_ids(unlock) → 真實 BattleRuleCatalogBuilder
	# → EncounterCompiler，全程不使用手工 catalog。
	var registry := _registry()
	var installed := registry.install_validated(
		_fixture_with_slice_challenge_chain(), "fixture.challenge_catalog.3", [&"pack.core"]
	)
	assert_true(installed.ok)
	if not installed.ok:
		return
	var digest := installed.handle.manifest_digest
	var resolved := ChallengeAffixResolver.new().resolve(registry, digest, 1)
	assert_true(resolved.ok, "%s" % (String(resolved.error.code) if not resolved.ok else ""))
	if not resolved.ok:
		return
	var battle_ids: Array[StringName] = []
	for entry: ChallengeAffixEntryState in resolved.entries:
		if entry.track == ChallengeAffixEntryState.BATTLE_AFFIX_TRACK:
			battle_ids.append(entry.effect_id)
	assert_eq(battle_ids, [BATTLE_AFFIX_ID] as Array[StringName], "Challenge 1 的軌 A 詞綴")
	var required: Array[StringName] = [BATTLE_AFFIX_UNLOCK_ID, ENCOUNTER_ID]
	var built := BattleRuleCatalogBuilder.new().build(registry, digest, required)
	assert_true(built.ok, _build_error_text(built))
	if not built.ok:
		return
	var request := EncounterCompileRequest.new()
	request.manifest_digest = digest
	request.encounter_id = ENCOUNTER_ID
	request.node_id = NODE_ID
	request.act_index = 1
	request.depth = 0
	request.challenge_level = 1
	request.challenge_affix_effect_ids = battle_ids
	var compiled := EncounterCompiler.new().compile(request, built.catalog)
	assert_true(compiled.ok, _compile_error_text(compiled))
	if not compiled.ok:
		return
	var compiled_ids: Array[StringName] = []
	for assignment: BattleEffectSourceAssignmentSnapshot in compiled.preview.affix_effects:
		compiled_ids.append(assignment.effect_id)
	assert_eq(
		compiled_ids,
		[BATTLE_AFFIX_ID] as Array[StringName],
		"軌 A 詞綴必須經真實 builder 建出的 catalog 實際編進 encounter"
	)

## ChallengeAffixResolver 與 RunModifierTableBuilder 以 unlock.slice_challenge_%d 的 id 慣例
## 逐階級查表（ContentRegistryService 無列舉能力），而 SyntheticContentFixture 的預設鏈是
## unlock.challenge_%d——沿用 test_challenge_affix_end_to_end.gd:342 的同一改名做法。
func _fixture_with_slice_challenge_chain() -> ContentValidationInput:
	var fixture := SyntheticContentFixture.build_valid()
	for level in range(6):
		var unlock := _find(fixture, StringName("unlock.challenge_%d" % level)) as UnlockDef
		assert_not_null(unlock, "SyntheticContentFixture 應含 unlock.challenge_%d" % level)
		if unlock == null:
			return fixture
		unlock.id = StringName("unlock.slice_challenge_%d" % level)
	for level in range(1, 6):
		var unlock := _find(fixture, StringName("unlock.slice_challenge_%d" % level)) as UnlockDef
		unlock.prerequisite_refs = [StringName("unlock.slice_challenge_%d" % (level - 1))]
	return fixture

## Negative fixture：effect.challenge_affix_0 已是 battle affix；就地補上 run intents，
## 明確證明 global source lifecycle 會在 content boundary 拒絕雙軌 challenge effect。
func _fixture_with_dual_track_affix() -> ContentValidationInput:
	var fixture := _fixture_with_slice_challenge_chain()
	var effect := _find(fixture, BATTLE_AFFIX_ID) as EffectDef
	assert_not_null(effect, "SyntheticContentFixture 應含 %s" % String(BATTLE_AFFIX_ID))
	if effect == null:
		return fixture
	var discount := ShopDiscountOperationDef.new()
	discount.operation_index = 0
	discount.amount = 1
	discount.claim_scope = &"always"
	var surcharge := ShopSurchargeOperationDef.new()
	surcharge.operation_index = 1
	surcharge.amount = 2
	surcharge.claim_scope = &"always"
	var drain := DrainExpeditionHpOperationDef.new()
	drain.operation_index = 2
	drain.amount = 3
	drain.claim_scope = &"always"
	effect.run_operations = [discount, surcharge, drain]
	return fixture

func _registry() -> ContentRegistryService:
	var registry := ContentRegistryService.new()
	add_child_autofree(registry)
	return registry

func _find(fixture: ContentValidationInput, content_id: StringName) -> ContentDefinition:
	for definition: ContentDefinition in fixture.definitions:
		if definition.id == content_id:
			return definition
	return null

func _build_error_text(result: BattleRuleCatalogBuildResult) -> String:
	if result.ok or result.error == null:
		return ""
	var source := ""
	if result.error.source_id != null:
		source = String(result.error.source_id.value)
	return "%s:%s:%s" % [
		String(result.error.code), String(result.error.field_path), source,
	]

func _compile_error_text(result: EncounterCompileResult) -> String:
	if result.ok or result.error == null:
		return ""
	return "%s:%s:%s" % [
		String(result.error.code),
		String(result.error.field_path),
		String(result.error.source_id),
	]
