extends GutTest

## T07 (specs/meta-progression) — 端到端：Challenge N 遠征的詞綴 1..N 累積、經作用點/run 參數
## 實際生效，決定性（同輸入同結果）。串接本任務其餘測試各自鎖定的單點行為
## （ChallengeAffixResolver／EncounterCompiler／ShopService／BattleSettlementService），驗證
## 它們接在一起確實構成 design §6.3 描述的完整雙軌管線。
## Covers：S5-AC-009（端到端段："詞綴 1..N 累積實際生效"）、S5-AC-010；design.md §6.3、§9
## （"§5.1、§4.2" 端到端流程另由 T02/T05 覆蓋，本檔只聚焦詞綴雙軌這一段的串接，不重跑
## StartExpeditionCommand／MetaSettlementCommand 的存檔交易——那些是各自任務的既有測試範圍）。
##
## 情境設計：三階挑戰鏈——level 1 掛軌 A（battle affix）、level 2 掛軌 B 的 ShopSurcharge、
## level 3 掛軌 B 的 DrainExpeditionHp。在 Challenge 3 建構的管線必須同時看到三者；在
## Challenge 2 建構的管線只看到前兩者（尚未累積到 level 3 的 drain）——直接驗證「1..N 累積」
## 而非只驗證「最終態」，呼應 design「詞綴 1..N 累積」的逐階疊加語意。
##
## 假設聲明：本檔沿用同任務其餘檔案已宣告的簽名假設（ChallengeAffixResolver.resolve(registry,
## manifest_digest, challenge_level)、RunModifierTableBuilder.build(registry, manifest_digest,
## relic_ids, commander_id, challenge_level)——RunModifierTableBuilder 為既有型別，非本任務新增
## ——ShopSurchargeOperationDef/DrainExpeditionHpOperationDef 兩個內容編譯層新類別），不重複
## 展開理由，詳見各自檔案的假設聲明段。

const RESOLVER_SCRIPT_PATH := "res://domain/run/build/challenge_affix_resolver.gd"

const BATTLE_AFFIX_ID: StringName = &"effect.e2e_battle_l1"
const SURCHARGE_AFFIX_ID: StringName = &"effect.e2e_surcharge_l2"
const DRAIN_AFFIX_ID: StringName = &"effect.e2e_drain_l3"


func test_challenge_three_accumulates_all_three_prior_levels_deterministically() -> void:
	var registry := ContentRegistryService.new()
	add_child_autofree(registry)
	var installed := _install(registry, "fixture.challenge_e2e.1")
	if not installed.ok:
		assert_true(installed.ok, "install_validated failed: %s" % installed.error.code)
		return
	var digest := installed.handle.manifest_digest
	var no_relics: Array[StringName] = []

	# --- 軌 B：RunModifierTableBuilder 在 Challenge 3 必須同時看到 surcharge(level2) 與
	# drain(level3) 的 always-active 貢獻 ---
	var built_lvl3 := RunModifierTableBuilder.new().build(registry, digest, no_relics, &"commander.c0", 3)
	assert_true(built_lvl3.ok, "%s" % (built_lvl3.error.code if not built_lvl3.ok else ""))
	if not built_lvl3.ok:
		return
	assert_eq(built_lvl3.table.sum_always_active(&"economy", &"shop_surcharge"), 4, "level2 的 surcharge 貢獻必須累積進 Challenge 3")
	assert_eq(built_lvl3.table.sum_always_active(&"rule", &"drain_expedition_hp"), 6, "level3 自身的 drain 貢獻")

	# --- 軌 B 實際生效：ShopService 成本反映 surcharge ---
	var shop_catalog := _shop_catalog(digest, 10)
	var shop_result := ShopService.new().generate_offers(GenerateOffersRequest.new(
		&"run_e2e", &"node_e2e", EconomyState.new(50, 3, 0, 0, 0, 0, []),
		shop_catalog.create_initial_pool(), EconomyTestFixture.empty_roster(),
		EconomyTestFixture.empty_owners(), EconomyTestFixture.shop_rng(),
		U64Bits.zero(), U64Bits.one(), shop_catalog, built_lvl3.table, []
	))
	assert_true(shop_result.ok)
	if shop_result.ok:
		for offer: ShopOffer in shop_result.transaction.economy_state.shop_offers:
			assert_eq(offer.cost, 14, "10 base + 4 challenge surcharge(累積自 level2)")

	# --- 軌 B 實際生效：BattleSettlementService 戰敗損失反映 drain ---
	var loss_root := _loss_root(100, 20)
	var root_digest := loss_root.run.content_snapshot.manifest_digest_value()
	var settlement_catalog := EconomyTestFixture.settlement_catalog(root_digest)
	# 規則本體＝上方 RunModifierTableBuilder 從 registry 解出的 Challenge 3 規則，僅把表重釘到
	# root 的世代以滿足 BattleSettlementService 的世代守衛（三方同世代）。
	var settlement_table := RunRelicTable.new(root_digest, built_lvl3.table.all_rules())
	var settled := BattleSettlementService.new().settle(loss_root.run, settlement_catalog, settlement_table, [])
	assert_true(settled.ok, "%s" % (settled.error.code if not settled.ok else ""))
	if settled.ok:
		assert_eq(settled.run_state.expedition_hp, 74, "100 - (20 damage + 6 challenge drain(累積自 level3))")

	# --- 軌 A：ChallengeAffixResolver 在 Challenge 3 必須列出 level1 的 battle affix ---
	var resolver_result := _resolve(registry, digest, 3)
	if resolver_result == null:
		return
	assert_true(bool(resolver_result.get("ok")), _error_text(resolver_result))
	if not bool(resolver_result.get("ok")):
		return
	var battle_ids := _battle_track_effect_ids(resolver_result.get("entries"))
	assert_eq(battle_ids, [BATTLE_AFFIX_ID], "軌 A 詞綴（level1）必須累積進 Challenge 3 的清單")

	# --- 軌 A 實際生效：EncounterCompiler 合併進 encounter 的 affix_effects ---
	var request := EncounterCompileRequest.new()
	request.manifest_digest = digest
	request.encounter_id = &"encounter.e2e"
	request.node_id = &"node_e2e_0000000000000000000000000000000000000000000000000000000"
	request.act_index = 1
	request.depth = 0
	request.challenge_level = 3
	request.set("challenge_affix_effect_ids", battle_ids)
	var compiled := EncounterCompiler.new().compile(request, _battle_catalog(digest, [BATTLE_AFFIX_ID]))
	assert_true(compiled.ok, _compile_error_text(compiled))
	if not compiled.ok:
		return
	var compiled_ids: Array[StringName] = []
	for assignment: BattleEffectSourceAssignmentSnapshot in compiled.preview.affix_effects:
		compiled_ids.append(assignment.effect_id)
	assert_eq(compiled_ids, [BATTLE_AFFIX_ID], "軌 A 詞綴必須實際合併進 encounter 編譯結果")

	# --- 決定性：同輸入（Challenge 3）第二次跑整條管線必須得到完全相同的結果 ---
	var built_lvl3_again := RunModifierTableBuilder.new().build(registry, digest, no_relics, &"commander.c0", 3)
	assert_true(built_lvl3_again.ok)
	if built_lvl3_again.ok:
		assert_eq(
			built_lvl3_again.table.sum_always_active(&"economy", &"shop_surcharge"),
			built_lvl3.table.sum_always_active(&"economy", &"shop_surcharge")
		)
		assert_eq(
			built_lvl3_again.table.sum_always_active(&"rule", &"drain_expedition_hp"),
			built_lvl3.table.sum_always_active(&"rule", &"drain_expedition_hp")
		)
	var resolver_result_again := _resolve(registry, digest, 3)
	if resolver_result_again != null and bool(resolver_result_again.get("ok")):
		assert_eq(
			_battle_track_effect_ids(resolver_result_again.get("entries")),
			battle_ids,
			"同輸入兩次 resolve 必須得到相同的軌 A 詞綴清單"
		)


func test_challenge_two_has_not_yet_accumulated_level_three_drain() -> void:
	var registry := ContentRegistryService.new()
	add_child_autofree(registry)
	var installed := _install(registry, "fixture.challenge_e2e.2")
	if not installed.ok:
		assert_true(installed.ok, "install_validated failed: %s" % installed.error.code)
		return
	var digest := installed.handle.manifest_digest
	var no_relics: Array[StringName] = []
	var built_lvl2 := RunModifierTableBuilder.new().build(registry, digest, no_relics, &"commander.c0", 2)
	assert_true(built_lvl2.ok)
	if not built_lvl2.ok:
		return
	assert_eq(built_lvl2.table.sum_always_active(&"economy", &"shop_surcharge"), 4, "level2 已累積")
	assert_eq(built_lvl2.table.sum_always_active(&"rule", &"drain_expedition_hp"), 0, "level3 尚未累積進 Challenge 2")


func test_challenge_zero_run_modifier_table_has_no_challenge_contribution() -> void:
	var registry := ContentRegistryService.new()
	add_child_autofree(registry)
	var installed := _install(registry, "fixture.challenge_e2e.3")
	if not installed.ok:
		assert_true(installed.ok, "install_validated failed: %s" % installed.error.code)
		return
	var digest := installed.handle.manifest_digest
	var no_relics: Array[StringName] = []
	var built_lvl0 := RunModifierTableBuilder.new().build(registry, digest, no_relics, &"commander.c0", 0)
	assert_true(built_lvl0.ok)
	if not built_lvl0.ok:
		return
	assert_eq(built_lvl0.table.sum_always_active(&"economy", &"shop_surcharge"), 0)
	assert_eq(built_lvl0.table.sum_always_active(&"rule", &"drain_expedition_hp"), 0)
	assert_eq(built_lvl0.table.always_active_count(&"economy"), 0)
	var resolver_result := _resolve(registry, digest, 0)
	if resolver_result == null:
		return
	assert_true(bool(resolver_result.get("ok")))
	if bool(resolver_result.get("ok")):
		assert_eq(_battle_track_effect_ids(resolver_result.get("entries")), [] as Array[StringName], "Challenge 0 無詞綴")


func _install(registry: ContentRegistryService, content_version: String) -> CatalogCompileResult:
	var fixture := _fixture_with_renamed_challenge_chain()
	_append_battle_only_effect(fixture, BATTLE_AFFIX_ID)
	_append_run_only_effect(fixture, SURCHARGE_AFFIX_ID, _surcharge_operation())
	_append_run_only_effect(fixture, DRAIN_AFFIX_ID, _drain_operation())
	_set_modifier_refs(fixture, 1, [BATTLE_AFFIX_ID])
	_set_modifier_refs(fixture, 2, [SURCHARGE_AFFIX_ID])
	_set_modifier_refs(fixture, 3, [DRAIN_AFFIX_ID])
	return registry.install_validated(fixture, content_version, [&"pack.core"])


func _surcharge_operation() -> RunOperationDef:
	var script := load("res://content/definitions/shop_surcharge_operation_def.gd") as GDScript
	assert_not_null(script, "ShopSurchargeOperationDef must exist")
	if script == null:
		return null
	var operation: RunOperationDef = script.new()
	operation.set("operation_index", 0)
	operation.set("amount", 4)
	operation.set("claim_scope", &"always")
	return operation


func _drain_operation() -> RunOperationDef:
	var script := load("res://content/definitions/drain_expedition_hp_operation_def.gd") as GDScript
	assert_not_null(script, "DrainExpeditionHpOperationDef must exist")
	if script == null:
		return null
	var operation: RunOperationDef = script.new()
	operation.set("operation_index", 0)
	operation.set("amount", 6)
	operation.set("claim_scope", &"always")
	return operation


func _resolve(registry: ContentRegistryService, manifest_digest: String, challenge_level: int) -> Object:
	var script := load(RESOLVER_SCRIPT_PATH) as GDScript
	assert_not_null(script, "ChallengeAffixResolver (%s) must exist" % RESOLVER_SCRIPT_PATH)
	if script == null:
		return null
	var resolver: Object = script.new()
	return resolver.call("resolve", registry, manifest_digest, challenge_level)


func _battle_track_effect_ids(entries: Array) -> Array[StringName]:
	var result: Array[StringName] = []
	for entry: Object in entries:
		if entry.get("track") == &"battle_affix":
			result.append(entry.get("effect_id"))
	return result


func _error_text(result: Object) -> String:
	if result == null:
		return "resolve() returned null"
	if bool(result.get("ok")):
		return ""
	var error: Object = result.get("error")
	return "%s" % String(error.get("code")) if error != null else "ok=false but error=null"


func _compile_error_text(result: EncounterCompileResult) -> String:
	if result.ok or result.error == null:
		return ""
	return "%s:%s:%s" % [
		String(result.error.code), String(result.error.field_path), String(result.error.source_id),
	]


## w4 仲裁（2026-07-25）：catalog 必須釘在呼叫端的 registry 世代，否則 ShopService 的世代守衛
## 回 GENERATION_MISMATCH，測試到不了 surcharge 行為。
func _shop_catalog(manifest_digest: String, unit_cost: int) -> EconomyExpeditionCatalog:
	var base := EconomyTestFixture.catalog(manifest_digest)
	var units: Array[ShopUnitRule] = [
		ShopUnitRule.new(&"unit.test_a", 1, unit_cost),
		ShopUnitRule.new(&"unit.test_b", 1, unit_cost),
	]
	var nodes: Array[MapNodeRule] = []
	for kind: int in range(7):
		nodes.append_array(base.map_nodes_for(kind))
	return EconomyExpeditionCatalog.new(base.manifest_digest_value(), base.config(), units, nodes)


## w4 仲裁（2026-07-25）：原案宣告 manifest_digest 卻從未使用，root 仍是 ResolutionFixtureFactory
## 的預設世代，BattleSettlementService 的世代守衛回 EXPEDITION_GENERATION_MISMATCH，測試到不了
## drain 行為。改為讓 root 保留自己的世代，由呼叫端把受測的 catalog 與 relic table 一併釘到該
## 世代（規則本體仍是 RunModifierTableBuilder 由 registry 解出的那批，見呼叫處）。
func _loss_root(expedition_hp: int, damage: int) -> SaveRoot:
	var root := ResolutionFixtureFactory.create_root(ResolutionState.Kind.BATTLE_RESULT_PENDING)
	root.run.run_phase = RunState.RunPhase.COMBAT
	root.run.expedition_hp = expedition_hp
	var node_id := root.run.map_state.nodes[0].node_id
	root.run.current_node_id = OptionalStringValue.new(node_id)
	root.run.map_state.current_node_id = OptionalStringValue.new(node_id)
	root.run.income_claimed_node_ids = [node_id]
	var empty_proposals: Array[RunMutationProposal] = []
	_set_result(root.run, &"player_loss", damage, empty_proposals)
	return root


func _set_result(
	run: RunState, outcome: StringName, damage: int, proposals: Array[RunMutationProposal]
) -> void:
	var previous := run.resolution_state as BattleResultPendingResolutionState
	var result := BattleResult.new()
	result.battle_setup_hash = StringName(previous.battle_setup_hash)
	result.outcome = outcome
	result.final_tick = 20
	result.survivor_instance_ids = [
		&"e_0000000000000001" if outcome == &"player_loss" else &"u_0000000000000001"
	]
	result.expedition_damage = damage
	for proposal: RunMutationProposal in proposals:
		result.run_mutation_proposals.append(proposal.deep_clone())
	result.summary_hash = &"0000000000000000000000000000000000000000000000000000000000000000"
	var sealed := BattleResultCodecV1.new().seal(result.to_record())
	assert_true(sealed.ok)
	run.resolution_state = BattleResultPendingResolutionState.new(
		previous.battle_setup_hash, BattleResult.from_record(sealed.record)
	)


func _battle_catalog(manifest_digest: String, known_effect_ids: Array[StringName]) -> BattleRuleCatalog:
	var unit := BattleUnitRule.new()
	unit.unit_id = &"unit.enemy"
	unit.base_stats = BattleUnitStatsRule.new()
	unit.base_stats.health = 100
	unit.base_stats.attack = 10
	unit.base_stats.armor = 5
	unit.base_stats.magic_resist = 5
	unit.base_stats.attack_speed_milli = 1000
	unit.base_stats.attack_range_cells = 1
	unit.base_stats.start_mana = 0
	unit.base_stats.max_mana = 100
	unit.base_stats.move_speed_milli = 1000
	for pair: Array in [[1, 10000], [2, 18000], [3, 32000]]:
		var scaling := BattleStarScalingRule.new()
		scaling.star = int(pair[0])
		scaling.health_bps = int(pair[1])
		scaling.attack_bps = int(pair[1])
		scaling.armor_bps = int(pair[1])
		scaling.magic_resist_bps = int(pair[1])
		scaling.attack_speed_bps = 10000
		scaling.attack_range_bps = 10000
		scaling.start_mana_bps = 10000
		scaling.max_mana_bps = 10000
		scaling.move_speed_bps = 10000
		unit.star_scalings.append(scaling)
	var spawn := BattleEnemySpawnRule.new()
	spawn.side = &"enemy"
	spawn.logical_y = 6
	spawn.logical_x = 3
	spawn.spawn_key = "enemy_0"
	spawn.unit_id = &"unit.enemy"
	spawn.star = 1
	var encounter := BattleEncounterRule.new()
	encounter.encounter_id = &"encounter.e2e"
	encounter.encounter_kind = &"normal"
	encounter.preview_schema_version = 1
	encounter.enemy_spawns = [spawn]
	encounter.affix_ids = []
	var effects: Array[BattleEffectRule] = []
	for effect_id: StringName in known_effect_ids:
		var effect := BattleEffectRule.new()
		effect.effect_id = effect_id
		effects.append(effect)
	var units: Array[BattleUnitRule] = [unit]
	var traits: Array[BattleTraitRule] = []
	var abilities: Array[BattleAbilityRule] = []
	var encounters: Array[BattleEncounterRule] = [encounter]
	var equipment: Array[BattleEquipmentRule] = []
	var configs: Array[BattleCombatConfigRule] = []
	return BattleRuleCatalog.new(
		manifest_digest, units, traits, abilities, effects, encounters, equipment, configs
	)


## SyntheticContentFixture 的預設 challenge 鏈 id 為 unlock.challenge_N；改名為
## unlock.slice_challenge_N（同任務其餘檔案的既定假設）。
func _fixture_with_renamed_challenge_chain() -> ContentValidationInput:
	var fixture := SyntheticContentFixture.build_valid()
	for level in range(6):
		var unlock := _find(fixture, StringName("unlock.challenge_%d" % level)) as UnlockDef
		assert_not_null(unlock, "SyntheticContentFixture 應含 unlock.challenge_%d" % level)
		unlock.id = StringName("unlock.slice_challenge_%d" % level)
	for level in range(1, 6):
		var unlock := _find(fixture, StringName("unlock.slice_challenge_%d" % level)) as UnlockDef
		unlock.prerequisite_refs = [StringName("unlock.slice_challenge_%d" % (level - 1))]
	# T10：SyntheticContentFixture 的 commander.c0 現在預設帶一個 always-active add_gold 被動
	# （滿足新的 CONTENT_COMMANDER_PASSIVE_HOMOGENEOUS 三名被動多樣性規則），這些測試只想量測
	# challenge 鏈自身的 always-active 貢獻（economy/shop_surcharge、rule/drain_expedition_hp、
	# always_active_count(&"economy")），故清空 c0 的被動，避免其 add_gold 額外貢獻一筆
	# economy 類 always-active 規則污染 always_active_count 的斷言。
	(_find(fixture, &"commander.c0") as CommanderDef).passive_effect_refs = []
	return fixture


func _set_modifier_refs(fixture: ContentValidationInput, level: int, effect_ids: Array[StringName]) -> void:
	var unlock := _find(fixture, StringName("unlock.slice_challenge_%d" % level)) as UnlockDef
	assert_not_null(unlock)
	unlock.modifier_refs = effect_ids


func _append_battle_only_effect(fixture: ContentValidationInput, effect_id: StringName) -> void:
	var operation := ModifyStatOperationDef.new()
	operation.operation_index = 0
	operation.stat = &"attack"
	operation.mode = &"flat"
	operation.amount = 1
	operation.duration_ticks = 20
	operation.target = &"self"
	var effect := EffectDef.new()
	effect.id = effect_id
	effect.schema_version = 2
	effect.display_name_key = StringName("loc.%s" % String(effect_id))
	effect.description_key = StringName("loc.%s.description" % String(effect_id))
	effect.content_role = &"challenge_affix"
	effect.trigger = &"battle_start"
	effect.stacking = &"replace"
	effect.max_stacks = 1
	effect.duration_ticks = 20
	effect.battle_operations = [operation]
	fixture.definitions.append(effect)


func _append_run_only_effect(fixture: ContentValidationInput, effect_id: StringName, operation: RunOperationDef) -> void:
	if operation == null:
		return
	var effect := EffectDef.new()
	effect.id = effect_id
	effect.schema_version = 2
	effect.display_name_key = StringName("loc.%s" % String(effect_id))
	effect.description_key = StringName("loc.%s.description" % String(effect_id))
	effect.content_role = &"challenge_affix"
	effect.trigger = &"battle_start"
	effect.stacking = &"replace"
	effect.max_stacks = 1
	effect.duration_ticks = 1
	effect.run_operations = [operation]
	fixture.definitions.append(effect)


func _find(fixture: ContentValidationInput, content_id: StringName) -> ContentDefinition:
	for definition: ContentDefinition in fixture.definitions:
		if definition.id == content_id:
			return definition
	return null
