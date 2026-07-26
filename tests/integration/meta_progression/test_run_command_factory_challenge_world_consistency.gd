extends GutTest

## T11 (specs/meta-progression/design.md §3, §4.4, §6.3; requirements.md S5-AC-014;
## tasks.md T11's final sentence on "世代一致性") — proves the whole challenge-affix
## pipeline (ChallengeAffixResolver -> RunModifierTableBuilder -> RunCommandFactory ->
## EnterNodeEvent -> NodeEntryService -> EncounterCompiler) shares ONE content_snapshot.
## manifest_digest end to end, using a SINGLE real ContentRegistryService installation --
## not two independently-pinned fixture roots re-stitched together by hand.
##
## tasks.md T11 明文：test_challenge_affix_end_to_end.gd（tests/integration/
## meta_progression/test_challenge_affix_end_to_end.gd）"因橋接兩個獨立 fixture factory
## （ContentRegistryService／ResolutionFixtureFactory，見該檔 :67 註解）未覆蓋此面向"，本任務
## 不得只靠該檔既有斷言頂替——該檔自己的註解（:246-249）也承認它的 _loss_root() 用的是
## ResolutionFixtureFactory 產生的、與呼叫端 registry 世代無關的 root，只是事後把 catalog/
## relic_table 手動釘回同一個 digest；本檔改為從單一 ContentRegistryService 安裝（含
## commander/unlock/unit/encounter 全部真實可解析）一路建到 RunState，不重指世代。
##
## 同時釘住 T11「已知前置缺口」第 1 點（軌 A 在正式流程不生效）：BattleRuleCatalogBuilder
## 已能正確解碼 unlock 類內容（battle_rule_catalog_builder.gd:414-441），但沒有任何
## production 呼叫端把 challenge unlock 鏈餵給它的 required_ids —— 本檔直接對照「有無
## RunCompositionSupport.required_battle_ids() 的貢獻」兩種 battle_catalog，證明缺這一步
## 會讓 challenge>=1 的戰鬥節點進不去（ENCOUNTER_RULE_MISSING）。
##
## 假設聲明：RunCommandFactory／RunCompositionSupport 的簽章同
## tests/unit/meta_progression/test_run_command_factory.gd／test_run_composition_support.gd
## 檔頭已宣告者，不重複展開。

const FACTORY_SCRIPT_PATH := "res://domain/run/controller/run_command_factory.gd"
const SUPPORT_SCRIPT_PATH := "res://domain/run/controller/run_composition_support.gd"

const COMMANDER_ID: StringName = &"commander.c0"
const COMMANDER_UNIT_ID: StringName = &"unit.player_00"
const CHALLENGE_AFFIX_LEVEL_1: StringName = &"effect.challenge_affix_0"


func test_challenge_battle_affix_reaches_the_encounter_only_with_required_ids_helper() -> void:
	var factory_script := _load(FACTORY_SCRIPT_PATH, "RunCommandFactory")
	var support_script := _load(SUPPORT_SCRIPT_PATH, "RunCompositionSupport")
	if factory_script == null or support_script == null:
		return

	var registry := ContentRegistryService.new()
	add_child_autofree(registry)
	var installed := registry.install_validated(
		_challenge_ready_fixture(), "fixture.t11_world_consistency", [&"pack.core"]
	)
	assert_true(installed.ok, "install_validated failed: %s" % (
		String(installed.error.code) if not installed.ok else ""
	))
	if not installed.ok:
		return
	var digest := installed.handle.manifest_digest

	# --- 缺口 1 對照：base_ids（無 challenge 鏈）建出的 battle_catalog 進 challenge 1 的
	# normal 節點必須因 RULE_MISSING 失敗（EncounterCompiler 找不到 effect.challenge_affix_0
	# 的規則，因為它只透過 unlock.slice_challenge_1 的 modifier_refs 可達，不在
	# unit/encounter 的遞移閉包內）。
	var base_ids: Array[StringName] = [COMMANDER_UNIT_ID, &"encounter.normal"]
	var naive_catalog_result := BattleRuleCatalogBuilder.new().build(registry, digest, base_ids)
	assert_true(naive_catalog_result.ok, "%s" % (
		String(naive_catalog_result.error.code) if not naive_catalog_result.ok else ""
	))
	if not naive_catalog_result.ok:
		return
	var naive_compile := EncounterCompiler.new().compile(
		_encounter_request(digest, 1), naive_catalog_result.catalog
	)
	assert_false(
		naive_compile.ok,
		"without the challenge chain in required_ids, the level-1 battle affix must be unreachable"
	)
	if naive_compile.ok:
		return
	assert_eq(naive_compile.error.code, EncounterCompiler.RULE_MISSING)

	# --- 正解：required_ids 依 RunCompositionSupport.required_battle_ids() 補上
	# unlock.slice_challenge_1 後，同一份 encounter 編譯必須成功且真的看到該詞綴。
	var required_ids: Array[StringName] = support_script.call("required_battle_ids", base_ids, 1)
	var correct_catalog_result := BattleRuleCatalogBuilder.new().build(registry, digest, required_ids)
	assert_true(correct_catalog_result.ok, "%s" % (
		String(correct_catalog_result.error.code) if not correct_catalog_result.ok else ""
	))
	if not correct_catalog_result.ok:
		return
	var correct_compile := EncounterCompiler.new().compile(
		_encounter_request(digest, 1), correct_catalog_result.catalog
	)
	assert_true(correct_compile.ok, "%s:%s" % [
		String(correct_compile.error.code) if not correct_compile.ok else "ok",
		String(correct_compile.error.field_path) if not correct_compile.ok else "",
	])
	if not correct_compile.ok:
		return
	var affix_ids: Array[StringName] = []
	for assignment: BattleEffectSourceAssignmentSnapshot in correct_compile.preview.affix_effects:
		affix_ids.append(assignment.effect_id)
	assert_eq(affix_ids, [CHALLENGE_AFFIX_LEVEL_1])

	# --- 世界一致性：RunModifierTableBuilder／ChallengeAffixResolver／RunCommandFactory／
	# EnterNodeEvent 全部釘同一個 digest，一路走完整條 production wiring（而非各自手動釘回
	# 某個世代），最終在真正的 RunState 上進 challenge 節點成功、affix 生效。
	var relic_built := RunModifierTableBuilder.new().build(registry, digest, [], COMMANDER_ID, 1)
	assert_true(relic_built.ok, "%s" % (String(relic_built.error.code) if not relic_built.ok else ""))
	if not relic_built.ok:
		return
	assert_eq(relic_built.table.manifest_digest_value(), digest)

	var resolver_result := ChallengeAffixResolver.new().resolve(registry, digest, 1)
	assert_true(resolver_result.ok, "%s" % (String(resolver_result.error.code) if not resolver_result.ok else ""))
	if not resolver_result.ok:
		return
	var battle_track_ids: Array[StringName] = []
	for entry: ChallengeAffixEntryState in resolver_result.entries:
		if entry.track == ChallengeAffixEntryState.BATTLE_AFFIX_TRACK:
			battle_track_ids.append(entry.effect_id)
	assert_eq(battle_track_ids, [CHALLENGE_AFFIX_LEVEL_1])

	var economy_catalog := EconomyTestFixture.catalog(digest)
	var factory: Object = factory_script.new(
		economy_catalog, relic_built.table, correct_catalog_result.catalog, battle_track_ids
	)
	var draft := _single_normal_node_run(digest, economy_catalog, 1)
	var node_id: String = draft.map_state.nodes[0].node_id
	var enter_event: EnterNodeEvent = factory.call("enter_node_event", node_id)
	var applied := enter_event.apply_to(draft)
	assert_true(applied.ok, "%s:%s" % [
		"NODE_ENTRY_FAILED" if not applied.ok else "ok",
		String(applied.error.field_path) if not applied.ok else "",
	])
	if not applied.ok:
		return
	var entered_node := applied.draft.map_state.nodes[0]
	assert_not_null(entered_node.encounter_preview)
	if entered_node.encounter_preview == null:
		return
	var entered_affix_ids: Array[StringName] = []
	for assignment: BattleEffectSourceAssignmentSnapshot in entered_node.encounter_preview.affix_effects:
		entered_affix_ids.append(assignment.effect_id)
	assert_eq(
		entered_affix_ids, [CHALLENGE_AFFIX_LEVEL_1],
		"RunCommandFactory's EnterNodeEvent, wired end to end from one registry install, must" +
		" surface the same challenge affix ChallengeAffixResolver reported for this run's" +
		" own content_snapshot.manifest_digest"
	)


func _encounter_request(digest: String, challenge_level: int) -> EncounterCompileRequest:
	var request := EncounterCompileRequest.new()
	request.manifest_digest = digest
	request.encounter_id = &"encounter.normal"
	request.node_id = &"node_world_consistency_0000000000000000000000000000000000000000000"
	request.act_index = 1
	request.depth = 0
	request.challenge_level = challenge_level
	request.challenge_affix_effect_ids = [CHALLENGE_AFFIX_LEVEL_1]
	return request


## Single reachable NORMAL node (act 1, layer 0) so NodeEntryService._reachable() accepts it
## with an empty completed_node_ids -- mirrors ResolutionFixtureFactory/SaveRootFixture's
## own "act_index==1 and layer_index==0" convention for a run's first node.
func _single_normal_node_run(
	digest: String, economy_catalog: EconomyExpeditionCatalog, challenge_level: int
) -> RunState:
	var root := SaveRootFixture.create_valid_root()
	var run := root.run
	var snapshot_result := ContentSnapshotState.from_pinned_receipt(_receipt_for(digest))
	assert_true(snapshot_result.ok)
	run.content_snapshot = snapshot_result.snapshot
	run.commander_id = COMMANDER_ID
	run.challenge_level = challenge_level
	run.run_phase = RunState.RunPhase.MAP
	run.current_node_id = null
	var registry := RuntimeKeySchemaRegistry.new()
	var node_result := registry.build_node(StringName(run.run_id), 1, &"normal", 0, 0)
	var node_key := node_result.key_state as NodeKeyState
	# w5 仲裁（2026-07-25）：def_id 必須對得上 EconomyTestFixture.catalog() 的 map node 規則命名
	# （map_node.normal，generator=encounter.normal）；原案的 mapnode.normal_fixture 屬另一組
	# fixture 命名，try_map_node 查無規則即回 NODE_ENTRY_FAILED:map_node.generator_id。
	var node := MapNodeState.new(
		String(node_key.digest), node_key, &"map_node.normal", 1, 0, 0,
		MapNodeState.NodeKind.NORMAL, "a".repeat(64), null, false
	)
	var empty_edges: Array[MapEdgeState] = []
	var empty_completed: Array[String] = []
	run.map_state = MapState.new([node], empty_edges, null, empty_completed)
	run.economy_state = EconomyState.new(20, 3, 0, 0, 0, 0, [])
	run.unit_pool_state = economy_catalog.create_initial_pool()
	run.income_claimed_node_ids = []
	return run


## A PinnedCatalogBuildReceipt whose manifest_digest matches the installed registry
## generation, so RunState.content_snapshot round-trips through the same
## ContentSnapshotState.from_pinned_receipt() production path every other run uses. The
## other receipt fields are placeholders (this test never saves/loads through SaveRepository,
## only content_snapshot.manifest_digest_value() is read downstream).
func _receipt_for(digest: String) -> PinnedCatalogBuildReceipt:
	# w5 仲裁（2026-07-25）：ContentSnapshotState._build_candidate 硬性要求 enabled ids 必含
	# economy_config_id/combat_config_id/meta_reward_table_id 三者（content_snapshot_state.gd:188-202），
	# 原案漏列導致 from_pinned_receipt 失敗、run.content_snapshot 為 null。補齊並依 canonical set
	# 要求嚴格升序排序。
	var active_ids: Array[StringName] = [
		COMMANDER_UNIT_ID, COMMANDER_ID,
		&"economy.default", &"config.combat_default", &"meta.default",
	]
	active_ids.sort_custom(func(left: StringName, right: StringName) -> bool:
		return String(left) < String(right)
	)
	var empty_names: Array[StringName] = []
	return PinnedCatalogBuildReceipt.new(
		1, 2, "fixture.t11_world_consistency", "d".repeat(64), active_ids,
		&"economy.default", &"config.combat_default", empty_names, empty_names, empty_names,
		&"meta.default", digest
	)


## SyntheticContentFixture.build_valid() already ships a challenge chain and challenge_affix
## effects that fit this test's needs untouched -- commander.c0 has population_bonus=1 and a
## starting unit.player_00, unlock.challenge_1's modifier_refs already point to a pure
## battle_operations-only effect.challenge_affix_0 (synthetic_content_fixture.gd:154-166,
## 382-395, 527-535) -- the only transformation needed is renaming the unlock.challenge_N
## chain to unlock.slice_challenge_N, which is the naming convention
## ChallengeAffixResolver/RunModifierTableBuilder hard-code (challenge_affix_resolver.gd:33,
## run_modifier_table_builder.gd:90). Copied verbatim from
## test_challenge_affix_end_to_end.gd's _fixture_with_renamed_challenge_chain() (same
## rename, same reasoning) rather than importing it, since GDScript test files cannot import
## private helpers from one another.
func _challenge_ready_fixture() -> ContentValidationInput:
	var fixture := SyntheticContentFixture.build_valid()
	for level in range(6):
		var unlock := _find(fixture, StringName("unlock.challenge_%d" % level)) as UnlockDef
		assert_not_null(unlock, "SyntheticContentFixture should ship unlock.challenge_%d" % level)
		unlock.id = StringName("unlock.slice_challenge_%d" % level)
	for level in range(1, 6):
		var unlock := _find(fixture, StringName("unlock.slice_challenge_%d" % level)) as UnlockDef
		unlock.prerequisite_refs = [StringName("unlock.slice_challenge_%d" % (level - 1))]
	return fixture


func _find(fixture: ContentValidationInput, content_id: StringName) -> ContentDefinition:
	for definition: ContentDefinition in fixture.definitions:
		if definition.id == content_id:
			return definition
	return null


func _load(path: String, type_name: String) -> GDScript:
	var script := load(path) as GDScript
	assert_not_null(script, "%s (%s) must exist" % [type_name, path])
	return script
