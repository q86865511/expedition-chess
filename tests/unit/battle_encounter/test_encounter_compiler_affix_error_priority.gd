extends GutTest

## W4 雙審修正（F8，2026-07-25）——_compile_affixes 的錯誤碼優先序。
## S5 為了合併 challenge 詞綴，把「相鄰重複」掃描整段前移到規則查表之前，使
## `affix_ids = [A, A]` 且 A 不在 catalog 時的錯誤碼由 RULE_MISSING 靜默變成 RULE_INVALID
## （既有 S2/S4 行為是逐筆交錯：index 0 先查表就已回 RULE_MISSING）。缺失（世代/內容缺件）
## 應優先於重複（內容編排錯誤），呼叫端若以錯誤碼分流會誤判。本檔把兩種優先序都釘住。

const DIGEST := "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"
const NODE_ID: StringName = &"node_fixture_0000000000000000000000000000000000000000000000000000"

var _compiler := EncounterCompiler.new()

func test_duplicate_affix_id_that_is_also_missing_reports_rule_missing_first() -> void:
	var result := _compiler.compile(
		_request(), _catalog([&"effect.dup_affix", &"effect.dup_affix"], [])
	)
	assert_false(result.ok, "重複且缺失的 affix 必須讓 compile 失敗")
	if result.ok:
		return
	assert_eq(
		result.error.code,
		EncounterCompiler.RULE_MISSING,
		"缺失優先於重複：catalog 沒有這條規則時要回 RULE_MISSING（既有 S2/S4 行為）"
	)
	assert_eq(result.error.source_id, &"effect.dup_affix")

func test_duplicate_affix_id_present_in_catalog_still_reports_rule_invalid() -> void:
	var result := _compiler.compile(
		_request(), _catalog([&"effect.dup_affix", &"effect.dup_affix"], [&"effect.dup_affix"])
	)
	assert_false(result.ok, "encounter 自身 affix_ids 內部重複仍是內容錯誤")
	if result.ok:
		return
	assert_eq(result.error.code, EncounterCompiler.RULE_INVALID)
	assert_eq(result.error.source_id, &"effect.dup_affix")

func _request() -> EncounterCompileRequest:
	var request := EncounterCompileRequest.new()
	request.manifest_digest = DIGEST
	request.encounter_id = &"encounter.fixture"
	request.node_id = NODE_ID
	request.act_index = 1
	request.depth = 0
	request.challenge_level = 0
	return request

## 最小敵方 encounter（沿用 test_encounter_compiler_challenge_affixes.gd 的 fixture 形狀）：
## `affix_ids` 直接寫進 encounter 規則、`known_effect_ids` 決定哪些 effect 進 catalog，
## 讓「重複」與「缺失」可獨立組合。
func _catalog(
	affix_ids: Array[StringName], known_effect_ids: Array[StringName]
) -> BattleRuleCatalog:
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
	encounter.encounter_id = &"encounter.fixture"
	encounter.encounter_kind = &"normal"
	encounter.preview_schema_version = 1
	encounter.enemy_spawns = [spawn]
	encounter.affix_ids = affix_ids
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
		DIGEST, units, traits, abilities, effects, encounters, equipment, configs
	)
