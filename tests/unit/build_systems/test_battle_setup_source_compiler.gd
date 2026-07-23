extends GutTest

## T02（specs/build-systems，Wave2）— BattleSetupSourceCompiler（羈絆計數/快照/裝備/battle 遺物編譯）。
## Covers：REQ-TRAIT-001/002、REQ-RELIC-001（battle 類）、S4-AC-001/002/003。
## 依據 design.md §4「compile(committed_roster, catalog) -> BattleSetupSourceBundle」
## （domain/run/controller/combat/battle_setup_source_compiler.gd，目前不存在）。
##
## 被測目標的預期契約（design.md §4 逐條翻譯，尚未實作）：
##   class_name BattleSetupSourceCompiler extends RefCounted
##   func compile(committed_roster: RosterState, catalog: BattleRuleCatalog) -> BattleSetupSourceBundle
## - 純函式式：只讀 clone、不修改輸入。
## - 羈絆計數：上場 placements 的「不同 def_id」set 決定 tier；板凳與同 def_id 重複不計入計數
##   （召喚物不計屬結構性事實——RosterState 不含召喚物欄位，compile 輸入本就不可能含召喚物）。
## - 裝備：逐上場棋 equipment_instance_ids -> ItemInstanceState.def_id -> try_equipment_rule
##   -> BattleEffectSnapshot(category=equipment, source_stable_id=equipment_id,
##      source_instance_id=item instance id, target_ids=[wearer instance id])。
## - 遺物（battle 類）：依 active_relic_slots 槽序（slot_index 升序）
##   -> BattleRelicRule.battle_effect_ids -> BattleEffectSnapshot(category=relic,
##      source_stable_id=relic_id, source_slot=slot_index)；非 battle 類（catalog 查無）不產出。
## - bundle.manifest_digest = catalog.manifest_digest_value()。
##
## 慣例沿用 domain/battle/encounter/encounter_compiler.gd 的 trait threshold 判定寫法、
## tests/unit/combat_transactions/test_combat_transaction_commands.gd 的 RunState/roster fixture 寫法、
## tests/fixtures/canonical/battle_setup_fixture.gd 的 BattleEffectSnapshot 欄位慣例
## （equipment_effect.target_ids=[wearer]、source_instance_id=item instance）。

const _DIGEST_A: String = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

# ---------------------------------------------------------------------------
# S4-AC-001 — 羈絆計數排除板凳／同 def_id 重複
# ---------------------------------------------------------------------------

func test_trait_not_active_when_distinct_board_def_id_count_below_threshold() -> void:
	# 2 個上場棋皆為 unit.a（同 def_id 重複）+ 1 個板凳棋 unit.b：
	# 不同上場 def_id set = {unit.a}，size=1，未達 threshold(2) -> trait 不產出。
	var catalog := _catalog_with(
		[_unit_rule(&"unit.a", [&"trait.pack"]), _unit_rule(&"unit.b", [&"trait.pack"])],
		[_trait_rule(&"trait.pack", [[2, [&"effect.pack_t1"]]])],
		[], [],
		[_effect_rule(&"effect.pack_t1")]
	)
	var roster := _roster(
		[_placement(0, 0, "u1"), _placement(0, 1, "u2")],
		["u3"],
		[_unit_instance("u1", &"unit.a"), _unit_instance("u2", &"unit.a"), _unit_instance("u3", &"unit.b")],
		[], [], _empty_relic_slots()
	)
	var bundle := BattleSetupSourceCompiler.new().compile(roster, catalog)
	assert_not_null(bundle, "compile 應回傳 BattleSetupSourceBundle")
	if bundle == null:
		return
	assert_eq(bundle.player_units.size(), 2, "bundle.player_units 只應含上場棋，不含板凳")
	assert_eq(
		_find_trait(bundle, &"trait.pack"), null,
		"距離門檻不足時,同 def_id 重複與板凳皆不應貢獻計數,trait 不應產出"
	)

func test_trait_becomes_active_when_distinct_board_def_id_count_reaches_threshold() -> void:
	# 3 個不同 def_id 上場（unit.a/unit.b/unit.c）-> 不同 def_id set size=2 需求：
	# 這裡改用 unit.a + unit.c 兩個「不同」def_id 上場,達到 threshold(2)。
	var catalog := _catalog_with(
		[_unit_rule(&"unit.a", [&"trait.pack"]), _unit_rule(&"unit.c", [&"trait.pack"])],
		[_trait_rule(&"trait.pack", [[2, [&"effect.pack_t1"]]])],
		[], [],
		[_effect_rule(&"effect.pack_t1")]
	)
	var roster := _roster(
		[_placement(0, 0, "u1"), _placement(0, 1, "u2")],
		[],
		[_unit_instance("u1", &"unit.a"), _unit_instance("u2", &"unit.c")],
		[], [], _empty_relic_slots()
	)
	var bundle := BattleSetupSourceCompiler.new().compile(roster, catalog)
	assert_not_null(bundle)
	if bundle == null:
		return
	var snapshot := _find_trait(bundle, &"trait.pack")
	assert_not_null(snapshot, "不同 def_id 數達門檻時應產出 trait snapshot")
	if snapshot == null:
		return
	assert_eq(snapshot.tier, 1)
	assert_eq(snapshot.effect_assignments.size(), 1)
	assert_eq(snapshot.effect_assignments[0].effect_id, &"effect.pack_t1")
	assert_eq(snapshot.effect_assignments[0].source_category, &"trait")
	assert_eq(snapshot.effect_assignments[0].source_stable_id, &"trait.pack")

# ---------------------------------------------------------------------------
# S4-AC-002 — 6+6 標籤結構、第三標籤三重計入、tier 依門檻遞增
# ---------------------------------------------------------------------------

func test_third_tag_unit_counts_toward_three_traits_simultaneously() -> void:
	var catalog := _catalog_with(
		[
			_unit_rule(&"unit.f1", [&"trait.faction"]),
			_unit_rule(&"unit.f2", [&"trait.faction"]),
			_unit_rule(&"unit.special", [&"trait.faction", &"trait.class", &"trait.third"]),
		],
		[
			_trait_rule(&"trait.faction", [[2, [&"effect.faction_t1"]], [4, [&"effect.faction_t2"]]]),
			_trait_rule(&"trait.class", [[1, [&"effect.class_t1"]]]),
			_trait_rule(&"trait.third", [[1, [&"effect.third_t1"]]]),
		],
		[], [],
		[
			_effect_rule(&"effect.faction_t1"), _effect_rule(&"effect.faction_t2"),
			_effect_rule(&"effect.class_t1"), _effect_rule(&"effect.third_t1"),
		]
	)
	var roster := _roster(
		[_placement(0, 0, "u1"), _placement(0, 1, "u2"), _placement(0, 2, "u3")],
		[],
		[
			_unit_instance("u1", &"unit.f1"), _unit_instance("u2", &"unit.f2"),
			_unit_instance("u3", &"unit.special"),
		],
		[], [], _empty_relic_slots()
	)
	var bundle := BattleSetupSourceCompiler.new().compile(roster, catalog)
	assert_not_null(bundle)
	if bundle == null:
		return
	assert_eq(bundle.player_active_traits.size(), 3, "第三標籤棋應同時啟動三個羈絆")
	var faction := _find_trait(bundle, &"trait.faction")
	var class_trait := _find_trait(bundle, &"trait.class")
	var third := _find_trait(bundle, &"trait.third")
	assert_not_null(faction)
	assert_not_null(class_trait)
	assert_not_null(third)
	if faction == null or class_trait == null or third == null:
		return
	assert_eq(faction.tier, 1, "faction 不同 def_id 數=3(f1/f2/special),達 threshold(2) 未達(4) -> tier 1")
	assert_true(
		_members_as_strings(faction).has("u3"),
		"帶第三標籤的棋應計入 trait.faction 的成員"
	)
	assert_eq(class_trait.tier, 1)
	assert_eq(_members_as_strings(class_trait), ["u3"])
	assert_eq(third.tier, 1)
	assert_eq(_members_as_strings(third), ["u3"])

func test_trait_tier_upgrades_when_distinct_def_id_count_crosses_next_threshold() -> void:
	var catalog := _catalog_with(
		[
			_unit_rule(&"unit.f1", [&"trait.faction"]),
			_unit_rule(&"unit.f2", [&"trait.faction"]),
			_unit_rule(&"unit.f3", [&"trait.faction"]),
			_unit_rule(&"unit.f4", [&"trait.faction"]),
		],
		[_trait_rule(&"trait.faction", [[2, [&"effect.faction_t1"]], [4, [&"effect.faction_t2"]]])],
		[], [],
		[_effect_rule(&"effect.faction_t1"), _effect_rule(&"effect.faction_t2")]
	)
	var roster := _roster(
		[
			_placement(0, 0, "u1"), _placement(0, 1, "u2"),
			_placement(0, 2, "u3"), _placement(0, 3, "u4"),
		],
		[],
		[
			_unit_instance("u1", &"unit.f1"), _unit_instance("u2", &"unit.f2"),
			_unit_instance("u3", &"unit.f3"), _unit_instance("u4", &"unit.f4"),
		],
		[], [], _empty_relic_slots()
	)
	var bundle := BattleSetupSourceCompiler.new().compile(roster, catalog)
	assert_not_null(bundle)
	if bundle == null:
		return
	var faction := _find_trait(bundle, &"trait.faction")
	assert_not_null(faction)
	if faction == null:
		return
	assert_eq(faction.tier, 2, "4 個不同 def_id 達第二門檻 -> tier 應遞增為 2")
	assert_eq(faction.effect_assignments.size(), 1)
	assert_eq(faction.effect_assignments[0].effect_id, &"effect.faction_t2")

# ---------------------------------------------------------------------------
# S4-AC-003 — 同一 roster+catalog 兩次 compile 逐欄位相等（preview==sim 同源）
# ---------------------------------------------------------------------------

func test_compile_is_deterministic_for_same_roster_and_catalog() -> void:
	var catalog := _catalog_with(
		[_unit_rule(&"unit.a", [&"trait.pack"]), _unit_rule(&"unit.c", [&"trait.pack"])],
		[_trait_rule(&"trait.pack", [[2, [&"effect.pack_t1"]]])],
		[_equipment_rule(&"equipment.sword", [&"effect.slash"])],
		[_relic_rule(&"relic.battle_one", [&"effect.relic_boost"])],
		[
			_effect_rule(&"effect.pack_t1"), _effect_rule(&"effect.slash"),
			_effect_rule(&"effect.relic_boost"),
		]
	)
	var relic_slots: Array[RelicSlotState] = [
		RelicSlotState.new(0, OptionalStringNameValue.of(&"relic.battle_one")),
		RelicSlotState.new(1, null), RelicSlotState.new(2, null),
		RelicSlotState.new(3, null), RelicSlotState.new(4, null),
	]
	var roster := _roster(
		[_placement(0, 0, "u1"), _placement(0, 1, "u2")],
		[],
		[
			_unit_instance_equipped("u1", &"unit.a", ["it1"]),
			_unit_instance("u2", &"unit.c"),
		],
		[_item("it1", &"equipment.sword", "u1")],
		[], relic_slots
	)
	var compiler := BattleSetupSourceCompiler.new()
	var first := compiler.compile(roster, catalog)
	var second := compiler.compile(roster, catalog)
	assert_not_null(first)
	assert_not_null(second)
	if first == null or second == null:
		return
	assert_eq(first.manifest_digest, second.manifest_digest)
	assert_eq(first.player_units.size(), second.player_units.size())
	assert_eq(first.player_active_traits.size(), second.player_active_traits.size())
	for index: int in range(first.player_active_traits.size()):
		assert_eq(
			first.player_active_traits[index].trait_id,
			second.player_active_traits[index].trait_id
		)
		assert_eq(first.player_active_traits[index].tier, second.player_active_traits[index].tier)
		assert_eq(
			_members_as_strings(first.player_active_traits[index]),
			_members_as_strings(second.player_active_traits[index])
		)
	assert_eq(first.player_equipment_effects.size(), second.player_equipment_effects.size())
	assert_eq(first.player_relic_effects.size(), second.player_relic_effects.size())
	# 互不共用同一個底層物件(各自獨立編譯結果),更動一份不應影響另一份。
	if first.player_active_traits.size() > 0:
		first.player_active_traits[0].tier = 999
		assert_ne(second.player_active_traits[0].tier, 999)

func test_compiled_bundle_passes_start_combat_event_committed_roster_check() -> void:
	# preview 與 combat entry 用同一 compile() 產物：驗證 StartCombatEvent 的
	# _player_sources_match_committed_roster 對 compiler 產物判定通過並可實際開戰。
	var fixture := _combat_ready_fixture()
	var run: RunState = fixture["run"]
	var catalog: BattleRuleCatalog = fixture["catalog"]
	var sources := BattleSetupSourceCompiler.new().compile(run.roster_state, catalog)
	assert_not_null(sources)
	if sources == null:
		return
	assert_true(sources.all_sources_resolved(), "compile 產物應標記全部 *_sources_resolved=true")
	var applied := StartCombatEvent.new(catalog, sources).apply_to(run)
	assert_true(
		applied.ok,
		"compiler 產物必須通過既有 _player_sources_match_committed_roster 比對並可開戰: %s" \
			% _apply_error(applied)
	)

func test_compiled_bundle_with_equipment_passes_start_combat_event() -> void:
	# W2-F1 回歸：帶裝備的上場棋經 compiler(source=物品 instance、target=[穿戴棋])
	# 產出的 player_equipment_effects,必須通過 StartCombatEvent 的 validate_for_build
	# 並成功開戰(先前 validator owner_mode=player_unit 會誤判 INPUT_INVALID)。
	for equipment_count: int in [1, 2, 3]:
		var fixture := _combat_ready_fixture(_equipment_specs(equipment_count))
		var run: RunState = fixture["run"]
		var catalog: BattleRuleCatalog = fixture["catalog"]
		var sources := BattleSetupSourceCompiler.new().compile(run.roster_state, catalog)
		assert_not_null(sources)
		if sources == null:
			continue
		assert_eq(
			sources.player_equipment_effects.size(), equipment_count,
			"每件上場裝備應各產生一個裝備效果 (count=%d)" % equipment_count
		)
		for effect: BattleEffectSnapshot in sources.player_equipment_effects:
			assert_true(
				effect.target_ids.has(&"u_0000000000000001"),
				"裝備效果應綁定至穿戴棋 (target_ids)"
			)
			assert_not_null(effect.source_instance_id, "裝備效果 source 應為物品 instance id")
		var applied := StartCombatEvent.new(catalog, sources).apply_to(run)
		assert_true(
			applied.ok,
			"帶 %d 件裝備的上場棋必須能開戰 (source=物品 instance、target=穿戴棋): %s" \
				% [equipment_count, _apply_error(applied)]
		)

func _equipment_specs(count: int) -> Array:
	var specs: Array = []
	for index: int in range(count):
		specs.append({
			"item_id": "it_%d" % index,
			"equipment_id": StringName("equipment.e%d" % index),
			"effect_id": StringName("effect.eq%d" % index),
		})
	return specs

# ---------------------------------------------------------------------------
# 裝備效果編譯：逐上場棋 equipment_instance_ids -> BattleEffectSnapshot(equipment)
# ---------------------------------------------------------------------------

func test_equipped_item_produces_equipment_effect_snapshot_bound_to_wearer() -> void:
	var catalog := _catalog_with(
		[_unit_rule(&"unit.knight", [])],
		[],
		[_equipment_rule(&"equipment.sword", [&"effect.slash"])],
		[],
		[_effect_rule(&"effect.slash")]
	)
	var roster := _roster(
		[_placement(0, 0, "u1")],
		[],
		[_unit_instance_equipped("u1", &"unit.knight", ["it1"])],
		[_item("it1", &"equipment.sword", "u1")],
		[], _empty_relic_slots()
	)
	var bundle := BattleSetupSourceCompiler.new().compile(roster, catalog)
	assert_not_null(bundle)
	if bundle == null:
		return
	assert_eq(bundle.player_equipment_effects.size(), 1)
	var effect := bundle.player_equipment_effects[0]
	assert_eq(effect.source_category, &"equipment")
	assert_eq(effect.source_stable_id, &"equipment.sword")
	assert_eq(effect.effect_id, &"effect.slash")
	assert_not_null(effect.source_instance_id, "裝備效果應記錄來源物品 instance id")
	if effect.source_instance_id != null:
		assert_eq(effect.source_instance_id.value, &"it1")
	assert_true(
		effect.target_ids.has(&"u1"),
		"裝備效果應綁定至穿戴該裝備的棋 instance"
	)

func test_unequipped_bench_item_produces_no_equipment_effect() -> void:
	# 零件/裝備尚在 inventory、未綁定任何棋時,不應產出任何裝備效果。
	var catalog := _catalog_with(
		[_unit_rule(&"unit.knight", [])],
		[],
		[_equipment_rule(&"equipment.sword", [&"effect.slash"])],
		[],
		[_effect_rule(&"effect.slash")]
	)
	var roster := _roster(
		[_placement(0, 0, "u1")],
		[],
		[_unit_instance("u1", &"unit.knight")],
		[ItemInstanceState.new("it1", &"equipment.sword", null, U64Bits.zero())],
		["it1"], _empty_relic_slots()
	)
	var bundle := BattleSetupSourceCompiler.new().compile(roster, catalog)
	assert_not_null(bundle)
	if bundle == null:
		return
	assert_eq(bundle.player_equipment_effects.size(), 0)

# ---------------------------------------------------------------------------
# battle 遺物效果編譯：依槽序、非 battle 類(catalog 查無)不產出
# ---------------------------------------------------------------------------

func test_relic_effects_follow_slot_order_and_skip_relics_missing_from_battle_catalog() -> void:
	# catalog 只含兩個 battle 類遺物規則；slot 0 指向一個「非 battle 類」遺物(在 catalog 查無 -> 跳過)。
	var catalog := _catalog_with(
		[], [], [],
		[
			_relic_rule(&"relic.battle_one", [&"effect.r1"]),
			_relic_rule(&"relic.battle_two", [&"effect.r2"]),
		],
		[_effect_rule(&"effect.r1"), _effect_rule(&"effect.r2")]
	)
	var relic_slots: Array[RelicSlotState] = [
		RelicSlotState.new(0, OptionalStringNameValue.of(&"relic.economy_only")),
		RelicSlotState.new(1, OptionalStringNameValue.of(&"relic.battle_two")),
		RelicSlotState.new(2, null),
		RelicSlotState.new(3, OptionalStringNameValue.of(&"relic.battle_one")),
		RelicSlotState.new(4, null),
	]
	var roster := _roster([], [], [], [], [], relic_slots)
	var bundle := BattleSetupSourceCompiler.new().compile(roster, catalog)
	assert_not_null(bundle)
	if bundle == null:
		return
	assert_eq(
		bundle.player_relic_effects.size(), 2,
		"非 battle 類(catalog 查無)的槽應被跳過,不應產生效果"
	)
	assert_eq(bundle.player_relic_effects[0].source_stable_id, &"relic.battle_two")
	assert_eq(bundle.player_relic_effects[0].source_slot, 1)
	assert_eq(bundle.player_relic_effects[0].effect_id, &"effect.r2")
	assert_eq(bundle.player_relic_effects[0].source_category, &"relic")
	assert_eq(bundle.player_relic_effects[1].source_stable_id, &"relic.battle_one")
	assert_eq(bundle.player_relic_effects[1].source_slot, 3)
	assert_eq(bundle.player_relic_effects[1].effect_id, &"effect.r1")

# ---------------------------------------------------------------------------
# manifest digest 傳遞
# ---------------------------------------------------------------------------

func test_compiled_bundle_carries_catalog_manifest_digest() -> void:
	var catalog := _catalog_with([], [], [], [], [])
	var bundle := BattleSetupSourceCompiler.new().compile(_roster([], [], [], [], [], _empty_relic_slots()), catalog)
	assert_not_null(bundle)
	if bundle == null:
		return
	assert_eq(bundle.manifest_digest, _DIGEST_A)

# ---------------------------------------------------------------------------
# fixtures / helpers
# ---------------------------------------------------------------------------

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
		_DIGEST_A, units, traits, abilities, effects, encounters, equipment, configs, relics
	)

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

func _trait_rule(trait_id: StringName, thresholds: Array) -> BattleTraitRule:
	var rule := BattleTraitRule.new()
	rule.trait_id = trait_id
	rule.trait_kind = &"faction"
	rule.member_rule = &"unit"
	for pair: Array in thresholds:
		var threshold := BattleTraitThresholdRule.new()
		threshold.required_count = int(pair[0])
		var typed_ids: Array[StringName] = []
		for value in (pair[1] as Array):
			typed_ids.append(value as StringName)
		threshold.effect_ids = typed_ids
		rule.thresholds.append(threshold)
	return rule

func _equipment_rule(equipment_id: StringName, effect_ids: Array) -> BattleEquipmentRule:
	var rule := BattleEquipmentRule.new()
	rule.equipment_id = equipment_id
	var typed_ids: Array[StringName] = []
	for value in effect_ids:
		typed_ids.append(value as StringName)
	rule.effect_ids = typed_ids
	return rule

func _relic_rule(relic_id: StringName, effect_ids: Array) -> BattleRelicRule:
	var rule := BattleRelicRule.new()
	rule.relic_id = relic_id
	var typed_ids: Array[StringName] = []
	for value in effect_ids:
		typed_ids.append(value as StringName)
	rule.battle_effect_ids = typed_ids
	return rule

func _effect_rule(effect_id: StringName) -> BattleEffectRule:
	var rule := BattleEffectRule.new()
	rule.effect_id = effect_id
	rule.content_role = &"general"
	rule.trigger = &"battle_start"
	rule.stacking = &"replace"
	rule.max_stacks = 1
	rule.duration_ticks = 1
	return rule

func _placement(logical_y: int, logical_x: int, unit_instance_id: String) -> BoardPlacementState:
	return BoardPlacementState.new(logical_y, logical_x, unit_instance_id)

func _unit_instance(instance_id: String, def_id: StringName) -> UnitInstance:
	var empty_equipment: Array[String] = []
	return UnitInstance.new(instance_id, def_id, 1, empty_equipment, U64Bits.zero())

func _unit_instance_equipped(
	instance_id: String, def_id: StringName, equipment_instance_ids: Array
) -> UnitInstance:
	var typed_ids: Array[String] = []
	for value in equipment_instance_ids:
		typed_ids.append(value as String)
	return UnitInstance.new(instance_id, def_id, 1, typed_ids, U64Bits.zero())

func _item(instance_id: String, def_id: StringName, bound_unit_instance_id: String) -> ItemInstanceState:
	return ItemInstanceState.new(
		instance_id, def_id, OptionalStringValue.new(bound_unit_instance_id), U64Bits.zero()
	)

func _empty_relic_slots() -> Array[RelicSlotState]:
	var slots: Array[RelicSlotState] = []
	for index: int in range(5):
		slots.append(RelicSlotState.new(index, null))
	return slots

func _roster(
	placements: Array,
	bench_unit_instance_ids: Array,
	unit_instances: Array,
	item_instances: Array,
	inventory_item_instance_ids: Array,
	relic_slots: Array[RelicSlotState]
) -> RosterState:
	var typed_placements: Array[BoardPlacementState] = []
	for value in placements:
		typed_placements.append(value as BoardPlacementState)
	var typed_bench: Array[String] = []
	for value in bench_unit_instance_ids:
		typed_bench.append(value as String)
	var typed_units: Array[UnitInstance] = []
	for value in unit_instances:
		typed_units.append(value as UnitInstance)
	var typed_items: Array[ItemInstanceState] = []
	for value in item_instances:
		typed_items.append(value as ItemInstanceState)
	var typed_inventory: Array[String] = []
	for value in inventory_item_instance_ids:
		typed_inventory.append(value as String)
	var pending_overflow: Array[String] = []
	return RosterState.new(
		BoardState.new(typed_placements), typed_bench, typed_units, typed_items,
		typed_inventory, pending_overflow, relic_slots
	)

func _find_trait(bundle: BattleSetupSourceBundle, trait_id: StringName) -> TraitBattleSnapshot:
	for snapshot: TraitBattleSnapshot in bundle.player_active_traits:
		if snapshot != null and snapshot.trait_id == trait_id:
			return snapshot
	return null

func _members_as_strings(snapshot: TraitBattleSnapshot) -> Array:
	var result: Array = []
	for member: StringName in snapshot.member_instance_ids:
		result.append(String(member))
	result.sort()
	return result

func _combat_ready_fixture(equipment_specs: Array = []) -> Dictionary:
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
	# equipment_specs（可空）：每項 {item_id, equipment_id, effect_id}，綁定至上場棋。
	var equipment_ids: Array[String] = []
	var items: Array[ItemInstanceState] = []
	var equipment: Array[BattleEquipmentRule] = []
	var effects: Array[BattleEffectRule] = []
	for spec: Dictionary in equipment_specs:
		equipment_ids.append(spec["item_id"] as String)
		items.append(_item(spec["item_id"] as String, spec["equipment_id"] as StringName, "u_0000000000000001"))
		equipment.append(_equipment_rule(spec["equipment_id"] as StringName, [spec["effect_id"]]))
		effects.append(_effect_rule(spec["effect_id"] as StringName))
	var units: Array[UnitInstance] = [UnitInstance.new(
		"u_0000000000000001", &"unit.hero", 1, equipment_ids, U64Bits.zero()
	)]
	var empty_strings: Array[String] = []
	run.roster_state = RosterState.new(
		BoardState.new(placements), empty_strings, units, items,
		empty_strings, empty_strings, _empty_relic_slots()
	)
	var battle_units: Array[BattleUnitRule] = [
		_unit_rule(&"unit.foe", []), _unit_rule(&"unit.hero", []),
	]
	var configs: Array[BattleCombatConfigRule] = [_combat_config()]
	var traits: Array[BattleTraitRule] = []
	var abilities: Array[BattleAbilityRule] = []
	var encounters: Array[BattleEncounterRule] = []
	var relics: Array[BattleRelicRule] = []
	var catalog := BattleRuleCatalog.new(
		SaveRootFixture.MANIFEST_DIGEST,
		battle_units, traits, abilities, effects, encounters, equipment, configs, relics
	)
	return {"run": run, "catalog": catalog}

func _combat_config() -> BattleCombatConfigRule:
	var config := BattleCombatConfigRule.new()
	config.config_id = &"config.combat_default"
	var defaults := BattleRulesSnapshot.new()
	for property: StringName in BattleCombatConfigRule._integer_properties():
		config.set(property, defaults.get(property))
	return config

func _apply_error(result: CommandApplyResult) -> String:
	if result == null or result.error == null:
		return "unknown apply failure"
	return "%s at %s" % [String(result.error.code), String(result.error.field_path)]
