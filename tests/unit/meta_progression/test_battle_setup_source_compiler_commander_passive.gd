extends GutTest

## T06(specs/meta-progression) — BattleSetupSourceCompiler.compile 新增可選
## commander_passive_effect_ids 參數，產 source_category=commander/source_side=player 的
## BattleEffectSnapshot，隨 BattleSetup hash 凍結、進模擬。
## Covers：S5-AC-003；tasks.md T06 驗收：「battle 層 commander_passive_effect_ids 產
## source_category="commander"/source_side="player" snapshot 進 BattleSetup hash」。
## 依據 design.md §6.2:119-121：「BattleSetupSourceCompiler.compile 新增可選
## commander_passive_effect_ids 參數，產...BattleEffectSnapshot(比照 relic effects
## battle_setup_source_compiler.gd:220-246)，隨 BattleSetup hash 凍結、進模擬」。
##
## 假設聲明：
## 1. 新參數為第 3 個位置參數、預設 []（比照既有 relic_table/active_relic_ids 等「尾端可選
##    參數、預設 null/[]，既有 2-arg 呼叫端完全不變」慣例，見
##    tests/unit/economy_expediton/test_income_service_relics.gd 等四檔的假設聲明）。
## 2. BattleSetupSourceBundle.commander_effects/commander_sources_resolved 兩個欄位已存在
##    (domain/run/controller/combat/battle_setup_source_bundle.gd:9,15)，本片只需讓 compile()
##    實際填入非空內容,不新增欄位。commander_sources_resolved 沿用既有「無拒絕路徑、恆
##    true」慣例(compile() doc:"無拒絕路徑",見檔案頂部注解)。
## 3. source_stable_id 的確切取值 design.md 未給定(只給 source_category/source_side 兩個
##    欄位)——本檔不斷言其具體值,只斷言 BattleSetupInputsValidator 明確要求的性質
##    (domain/battle/battle_setup_inputs_validator.gd:716-770 對 commander 類的
##    owner_mode=null、maximum_slot=0、以及跨筆 identity 唯一)由 StartCombatEvent 整條
##    管線驗證通過來間接保證,而非直接讀取 source_stable_id 欄位值。
## 4. 多筆 commander_passive_effect_ids 測試時,本檔刻意選用「已按字典序排列」的 id
##    (effect.commander_alpha < effect.commander_beta),讓斷言不論實作是否對輸出重新排序
##    (BattleSetupInputsValidator 對 commander 類要求依 source_stable_id 排序)都能成立，
##    避免對 source_stable_id 的具體命名方案做多餘假設。
##
## 範圍聲明：commander_id 從 CommanderDef.passive_effect_refs 解析成
## commander_passive_effect_ids 這一步的「內容解析」不在本檔鎖定範圍(此參數本身即為呼叫端
## 已解析好的 effect id 清單，比照 compile() 對 relic battle_effect_ids 的既有消費方式——
## 只消費,不解析 CommanderDef)；challenge_modifiers 由 T07 負責，本檔不測。

const _DIGEST: String = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

func test_compile_without_commander_ids_still_compiles_and_yields_empty_commander_effects() -> void:
	var catalog := _catalog_with([], [], [], [], [])
	var bundle := BattleSetupSourceCompiler.new().compile(_empty_roster(), catalog)
	assert_not_null(bundle, "既有 2-arg 呼叫必須繼續可用(S4 呼叫端零修改)")
	if bundle == null:
		return
	assert_eq(bundle.commander_effects.size(), 0)

func test_compile_with_commander_passive_effect_ids_produces_commander_player_snapshots() -> void:
	var catalog := _catalog_with(
		[], [], [], [],
		[_effect_rule(&"effect.commander_alpha"), _effect_rule(&"effect.commander_beta")]
	)
	var ids: Array[StringName] = [&"effect.commander_alpha", &"effect.commander_beta"]
	var bundle := BattleSetupSourceCompiler.new().compile(_empty_roster(), catalog, ids)
	assert_not_null(bundle)
	if bundle == null:
		return
	assert_eq(bundle.commander_effects.size(), 2)
	var effect_ids_seen: Array[StringName] = []
	for effect: BattleEffectSnapshot in bundle.commander_effects:
		assert_eq(effect.source_category, &"commander")
		assert_eq(effect.source_side, &"player")
		assert_eq(effect.source_slot, 0, "commander 效果無槽位概念,source_slot 應為 0")
		assert_null(effect.source_instance_id, "commander 效果不綁定任何 instance(比照 trait/challenge 慣例)")
		assert_eq(effect.target_ids.size(), 0)
		effect_ids_seen.append(effect.effect_id)
	assert_true(effect_ids_seen.has(&"effect.commander_alpha"))
	assert_true(effect_ids_seen.has(&"effect.commander_beta"))

func test_compile_with_empty_commander_passive_effect_ids_array_yields_no_commander_effects() -> void:
	var catalog := _catalog_with([], [], [], [], [])
	var empty_ids: Array[StringName] = []
	var bundle := BattleSetupSourceCompiler.new().compile(_empty_roster(), catalog, empty_ids)
	assert_not_null(bundle)
	if bundle == null:
		return
	assert_eq(bundle.commander_effects.size(), 0)

func test_compile_is_deterministic_for_same_commander_passive_effect_ids() -> void:
	var catalog := _catalog_with([], [], [], [], [_effect_rule(&"effect.commander_alpha")])
	var ids: Array[StringName] = [&"effect.commander_alpha"]
	var compiler := BattleSetupSourceCompiler.new()
	var first := compiler.compile(_empty_roster(), catalog, ids)
	var second := compiler.compile(_empty_roster(), catalog, ids)
	assert_not_null(first)
	assert_not_null(second)
	if first == null or second == null:
		return
	assert_eq(first.commander_effects.size(), second.commander_effects.size())
	assert_eq(first.commander_effects[0].effect_id, second.commander_effects[0].effect_id)
	# 互不共用同一個底層物件——更動一份不應影響另一份。
	first.commander_effects[0].priority = 999
	assert_ne(second.commander_effects[0].priority, 999)

func test_compiled_commander_effects_pass_start_combat_event_and_enter_combat() -> void:
	var fixture := _combat_ready_fixture([&"effect.commander_alpha", &"effect.commander_beta"])
	var run: RunState = fixture["run"]
	var catalog: BattleRuleCatalog = fixture["catalog"]
	var ids: Array[StringName] = [&"effect.commander_alpha", &"effect.commander_beta"]
	var sources := BattleSetupSourceCompiler.new().compile(run.roster_state, catalog, ids)
	assert_not_null(sources)
	if sources == null:
		return
	assert_true(sources.all_sources_resolved())
	assert_eq(sources.commander_effects.size(), 2)
	var applied := StartCombatEvent.new(catalog, sources).apply_to(run)
	assert_true(
		applied.ok,
		"帶 commander_passive_effect_ids 的編譯產物必須通過完整驗證管線並可實際開戰: %s" \
			% _apply_error(applied)
	)
	if not applied.ok:
		return
	var pending := run.resolution_state as CombatPendingResolutionState
	assert_not_null(pending)
	if pending == null:
		return
	var effect_ids_in_setup: Array[StringName] = []
	for effect: BattleEffectSnapshot in pending.battle_setup.inputs.commander_effects:
		effect_ids_in_setup.append(effect.effect_id)
	assert_true(effect_ids_in_setup.has(&"effect.commander_alpha"))
	assert_true(effect_ids_in_setup.has(&"effect.commander_beta"))
	assert_false(String(pending.battle_setup.battle_setup_hash).is_empty())

func test_different_commander_passive_effect_ids_yield_different_battle_setup_hash() -> void:
	var fixture_a := _combat_ready_fixture([&"effect.commander_alpha"])
	var ids_a: Array[StringName] = [&"effect.commander_alpha"]
	var sources_a := BattleSetupSourceCompiler.new().compile(
		(fixture_a["run"] as RunState).roster_state, fixture_a["catalog"], ids_a
	)
	var applied_a := StartCombatEvent.new(fixture_a["catalog"], sources_a).apply_to(fixture_a["run"])
	assert_true(applied_a.ok, "fixture_a: %s" % _apply_error(applied_a))

	var fixture_b := _combat_ready_fixture([&"effect.commander_alpha", &"effect.commander_beta"])
	var ids_b: Array[StringName] = [&"effect.commander_alpha", &"effect.commander_beta"]
	var sources_b := BattleSetupSourceCompiler.new().compile(
		(fixture_b["run"] as RunState).roster_state, fixture_b["catalog"], ids_b
	)
	var applied_b := StartCombatEvent.new(fixture_b["catalog"], sources_b).apply_to(fixture_b["run"])
	assert_true(applied_b.ok, "fixture_b: %s" % _apply_error(applied_b))
	if not applied_a.ok or not applied_b.ok:
		return

	var hash_a: StringName = ((fixture_a["run"] as RunState).resolution_state as CombatPendingResolutionState).battle_setup.battle_setup_hash
	var hash_b: StringName = ((fixture_b["run"] as RunState).resolution_state as CombatPendingResolutionState).battle_setup.battle_setup_hash
	assert_ne(
		hash_a, hash_b,
		"僅 commander_passive_effect_ids 不同(其餘 roster/catalog/run_seed 皆相同)必須產生不同的" +
		"battle_setup_hash——證明 commander 效果確實隨 BattleSetup hash 凍結"
	)

func test_baseline_without_commander_ids_still_matches_existing_start_combat_event_behavior() -> void:
	# 回歸測試(S4 既有行為不變)：不傳 commander_passive_effect_ids 時,行為與 S4 完全相同
	# (commander_effects 空、apply 仍成功)。
	var fixture := _combat_ready_fixture([])
	var run: RunState = fixture["run"]
	var catalog: BattleRuleCatalog = fixture["catalog"]
	var sources := BattleSetupSourceCompiler.new().compile(run.roster_state, catalog)
	assert_not_null(sources)
	if sources == null:
		return
	assert_eq(sources.commander_effects.size(), 0)
	var applied := StartCombatEvent.new(catalog, sources).apply_to(run)
	assert_true(applied.ok, "%s" % _apply_error(applied))

func _catalog_with(
	units: Array[BattleUnitRule],
	traits: Array[BattleTraitRule],
	equipment: Array[BattleEquipmentRule],
	relics: Array[BattleRelicRule],
	effects: Array[BattleEffectRule]
) -> BattleRuleCatalog:
	var abilities: Array[BattleAbilityRule] = []
	var encounters: Array[BattleEncounterRule] = []
	var configs: Array[BattleCombatConfigRule] = []
	return BattleRuleCatalog.new(
		_DIGEST, units, traits, abilities, effects, encounters, equipment, configs, relics
	)

func _effect_rule(effect_id: StringName) -> BattleEffectRule:
	var rule := BattleEffectRule.new()
	rule.effect_id = effect_id
	rule.content_role = &"general"
	rule.trigger = &"battle_start"
	rule.stacking = &"replace"
	rule.max_stacks = 1
	rule.duration_ticks = 1
	return rule

func _empty_relic_slots() -> Array[RelicSlotState]:
	var slots: Array[RelicSlotState] = []
	for index: int in range(5):
		slots.append(RelicSlotState.new(index, null))
	return slots

func _empty_roster() -> RosterState:
	var placements: Array[BoardPlacementState] = []
	var strings: Array[String] = []
	var units: Array[UnitInstance] = []
	var items: Array[ItemInstanceState] = []
	return RosterState.new(BoardState.new(placements), strings, units, items, strings, strings, _empty_relic_slots())

func _unit_rule(unit_id: StringName, trait_ids: Array) -> BattleUnitRule:
	var rule := BattleUnitRule.new()
	rule.unit_id = unit_id
	var typed_traits: Array[StringName] = []
	for value in trait_ids:
		typed_traits.append(value as StringName)
	rule.trait_ids = typed_traits
	rule.base_stats = BattleUnitStatsRule.new()
	rule.base_stats.health = 100
	rule.base_stats.attack = 10
	rule.base_stats.armor = 0
	rule.base_stats.magic_resist = 0
	rule.base_stats.attack_speed_milli = 1000
	rule.base_stats.attack_range_cells = 1
	rule.base_stats.start_mana = 0
	rule.base_stats.max_mana = 50
	rule.base_stats.move_speed_milli = 1000
	var scaling := BattleStarScalingRule.new()
	scaling.star = 1
	scaling.health_bps = 10000
	scaling.attack_bps = 10000
	scaling.armor_bps = 10000
	scaling.magic_resist_bps = 10000
	scaling.attack_speed_bps = 10000
	scaling.attack_range_bps = 10000
	scaling.start_mana_bps = 10000
	scaling.max_mana_bps = 10000
	scaling.move_speed_bps = 10000
	rule.star_scalings = [scaling]
	rule.ai_profile = &"melee"
	rule.basic_attack_profile = &"melee"
	rule.availability = &"always"
	rule.shop_condition = &"none"
	return rule

func _combat_config() -> BattleCombatConfigRule:
	var config := BattleCombatConfigRule.new()
	config.config_id = &"config.combat_default"
	var defaults := BattleRulesSnapshot.new()
	for property: StringName in BattleCombatConfigRule._integer_properties():
		config.set(property, defaults.get(property))
	return config

func _combat_ready_fixture(commander_effect_ids: Array) -> Dictionary:
	var root := SaveRootFixture.create_valid_root()
	var run := root.run
	run.run_phase = RunState.RunPhase.PREPARE
	run.act_index = 1
	run.resolution_state = IdleResolutionState.new()
	var enemy := UnitBattleSnapshot.new()
	enemy.instance_id = &"e_0000000000000001"
	enemy.unit_id = &"unit.foe"
	enemy.side = &"enemy"
	enemy.logical_y = 4
	enemy.logical_x = 3
	enemy.star = 1
	enemy.health = 30
	enemy.attack = 10
	enemy.attack_speed_milli = 1000
	enemy.attack_range_cells = 1
	enemy.max_mana = 0
	enemy.move_speed_milli = 1000
	var preview := EncounterPreviewSnapshot.new()
	preview.preview_schema_version = 1
	preview.encounter_id = &"encounter.test"
	preview.manifest_digest = StringName(SaveRootFixture.MANIFEST_DIGEST)
	preview.enemy_units.append(enemy)
	var node_key_result := RuntimeKeySchemaRegistry.new().build_node(
		StringName(run.run_id), 1, &"normal", 0, 0
	)
	assert_true(node_key_result.ok)
	var node_key := node_key_result.key_state as NodeKeyState
	var nodes: Array[MapNodeState] = [MapNodeState.new(
		String(node_key.digest), node_key, &"mapnode.fixture", 1, 0, 0,
		MapNodeState.NodeKind.NORMAL,
		"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
		preview, false
	)]
	var edges: Array[MapEdgeState] = []
	var completed: Array[String] = []
	run.map_state = MapState.new(
		nodes, edges, OptionalStringValue.new(String(node_key.digest)), completed
	)
	run.current_node_id = OptionalStringValue.new(String(node_key.digest))
	var placements: Array[BoardPlacementState] = [
		BoardPlacementState.new(3, 3, "u_0000000000000001")
	]
	var empty_equipment: Array[String] = []
	var units: Array[UnitInstance] = [UnitInstance.new(
		"u_0000000000000001", &"unit.hero", 1, empty_equipment, U64Bits.zero()
	)]
	var empty_strings: Array[String] = []
	var empty_items: Array[ItemInstanceState] = []
	run.roster_state = RosterState.new(
		BoardState.new(placements), empty_strings, units, empty_items,
		empty_strings, empty_strings, _empty_relic_slots()
	)
	var battle_units: Array[BattleUnitRule] = [
		_unit_rule(&"unit.foe", []), _unit_rule(&"unit.hero", []),
	]
	var configs: Array[BattleCombatConfigRule] = [_combat_config()]
	var traits: Array[BattleTraitRule] = []
	var abilities: Array[BattleAbilityRule] = []
	var encounters: Array[BattleEncounterRule] = []
	var equipment: Array[BattleEquipmentRule] = []
	var relics: Array[BattleRelicRule] = []
	var effects: Array[BattleEffectRule] = []
	for effect_id in commander_effect_ids:
		effects.append(_effect_rule(effect_id as StringName))
	var catalog := BattleRuleCatalog.new(
		SaveRootFixture.MANIFEST_DIGEST,
		battle_units, traits, abilities, effects, encounters, equipment, configs, relics
	)
	return {"run": run, "catalog": catalog}

func _apply_error(result: CommandApplyResult) -> String:
	if result == null or result.error == null:
		return "unknown apply failure"
	return "%s at %s" % [String(result.error.code), String(result.error.field_path)]
