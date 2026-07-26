extends GutTest

## T07 (specs/meta-progression) — 軌 A：ChallengeAffixResolver 解出的敵方 affix effect ids
## 經 EncounterCompileRequest 新欄位 challenge_affix_effect_ids 進 EncounterCompiler
## ._compile_affixes，與 encounter 自帶的 affix_ids 合併（同一敵方管線、決定性 sort、去重）。
## Covers：S5-AC-010（軌 A：敵方 affix 進 encounter）；design.md §6.3:127-129；tasks.md T07
## 驗收「軌 A 經 EncounterCompileRequest.challenge_affix_effect_ids 進 _compile_affixes 合併
## 去重」；tasks.md T07「菁英詞綴/map nodes 不動、Ch0 無詞綴」對應本檔的 baseline 迴歸測試。
##
## 假設聲明（design.md 未釘死處，本檔測試作者決定，逐條列出；實作代理請照此實作）：
## 1. EncounterCompileRequest 新增 `challenge_affix_effect_ids: Array[StringName] = []`
##    （sorted/dedup 由 ChallengeAffixResolver 保證，本檔仍各別測試無序輸入的情形，因為
##    EncounterCompiler 自身也要對「encounter 自帶 affix_ids ∪ challenge_affix_effect_ids」
##    的聯集做決定性排序，不能只信任呼叫端已排序）；`deep_clone()` 一併複製本欄位。
## 2. `_compile_affixes` 的合併語意：對「encounter.affix_ids」與
##    「request.challenge_affix_effect_ids」兩個來源取「聯集」（同一 effect_id 出現在兩個
##    來源時只保留一份、不視為錯誤）——design 原文「去重」實指跨來源去重。encounter 自身
##    affix_ids 內部若本已重複（同一來源內部重複），現行 _compile_affixes（encounter_compiler.gd
##    :317-343）以「排序後相鄰比對」回 RULE_INVALID——這是既有(S2/S4)行為，本檔不對它重新斷言
##    （不確定既有測試套件是否已有專門覆蓋此分支的測試，未查證不宣稱），只確保「跨來源」重複走
##    去重而非報錯這一 S5 新語意；若實作採用「兩來源合併成單一陣列後仍用相鄰比對去重」的寫法，
##    同時滿足兩種語意，天然相容，不需特別分流處理。
## 3. 合併後的 affix_effects 不區分來源——來源為 challenge 的 affix 與 encounter 原生 affix
##    在 preview 裡輸出格式完全相同（source_category=&"encounter_affix"、source_side=&"enemy"）
##    ，對齊 design「同一敵方管線」的字面意思：不新增分流欄位標記詞綴來源。
## 4. 找不到的 challenge affix effect id（catalog 未定義）視為與既有 encounter.affix_ids
##    找不到時相同的失敗：RULE_MISSING（field_path 不強求與原生來源完全一致，只斷言 error
##    code）。
##
## GUT 陷阱處理：EncounterCompileRequest 是既有類別（可靜態參照），但
## `challenge_affix_effect_ids` 是尚不存在的新欄位——對靜態型別為 EncounterCompileRequest
## 的變數直接寫 `request.challenge_affix_effect_ids = [...]` 會在腳本載入當下被 GDScript
## 靜態分析當成「屬性不存在」的 Parse/Analysis Error，导致整檔被 GUT 靜默排除（同
## tests/unit/meta_progression/test_run_discovery_log.gd 說明的 class_name 陷阱，但這裡是
## 「既有型別 + 不存在的欄位」的同類陷阱）。本檔一律用 Object.set()/Object.get() 動態存取
## 此一欄位，其餘既有欄位（manifest_digest/encounter_id/...）與既有 EncounterCompiler／
## BattleRuleCatalog 型別維持一般靜態寫法（無風險，因為它們早已存在）。

const DIGEST := "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"
const FIELD_NAME := "challenge_affix_effect_ids"

var _compiler := EncounterCompiler.new()

func test_challenge_affix_effect_ids_field_survives_deep_clone() -> void:
	var request := _request([&"effect.challenge_a"])
	var copied: EncounterCompileRequest = request.deep_clone()
	assert_eq(
		copied.get(FIELD_NAME), [&"effect.challenge_a"],
		"deep_clone() must copy the new challenge_affix_effect_ids field"
	)

func test_empty_challenge_affix_ids_behaves_identically_to_pre_s5_baseline() -> void:
	var request := _request([])
	var result := _compiler.compile(request, _catalog([&"effect.native_affix"]))
	assert_true(result.ok, _error_text(result))
	if not result.ok:
		return
	var ids := _affix_ids(result)
	assert_eq(ids, [&"effect.native_affix"], "Ch0／未提供詞綴時，行為必須與既有(S4)一致，不受影響")

func test_challenge_affix_ids_merge_with_native_affix_ids_sorted() -> void:
	var request := _request([&"effect.challenge_b", &"effect.challenge_a"])
	var result := _compiler.compile(
		request,
		_catalog([&"effect.native_affix"], [&"effect.challenge_a", &"effect.challenge_b"])
	)
	assert_true(result.ok, _error_text(result))
	if not result.ok:
		return
	var ids := _affix_ids(result)
	assert_eq(
		ids,
		[&"effect.challenge_a", &"effect.challenge_b", &"effect.native_affix"],
		"encounter 自帶 affix 與 challenge affix 合併後必須決定性排序（字典序）"
	)
	for assignment: BattleEffectSourceAssignmentSnapshot in result.preview.affix_effects:
		assert_eq(assignment.source_category, &"encounter_affix", "同一敵方管線，來源不分流")
		assert_eq(assignment.source_side, &"enemy")

func test_challenge_affix_id_duplicating_a_native_affix_id_is_deduplicated_not_rejected() -> void:
	var request := _request([&"effect.native_affix"])
	var result := _compiler.compile(request, _catalog([&"effect.native_affix"]))
	assert_true(
		result.ok,
		"跨來源重複（challenge 詞綴與 encounter 原生 affix 撞同一 id）必須去重、不得回傳 RULE_INVALID: %s" % _error_text(result)
	)
	if not result.ok:
		return
	assert_eq(_affix_ids(result), [&"effect.native_affix"], "去重後只留一筆")

func test_unresolvable_challenge_affix_id_is_rejected_as_rule_missing() -> void:
	var request := _request([&"effect.does_not_exist"])
	var result := _compiler.compile(request, _catalog([&"effect.native_affix"]))
	assert_false(result.ok, "catalog 未定義的 challenge affix effect id 必須讓 compile 失敗")
	if result.ok:
		return
	assert_eq(result.error.code, EncounterCompiler.RULE_MISSING)
	assert_eq(result.error.source_id, &"effect.does_not_exist")

func test_compile_with_challenge_affixes_is_deterministic_across_calls() -> void:
	var request := _request([&"effect.challenge_a"])
	var catalog := _catalog([&"effect.native_affix"], [&"effect.challenge_a"])
	var first := _compiler.compile(request, catalog)
	var second := _compiler.compile(request, catalog)
	assert_true(first.ok, _error_text(first))
	assert_true(second.ok, _error_text(second))
	if not first.ok or not second.ok:
		return
	assert_eq(_affix_ids(first), _affix_ids(second), "同輸入兩次 compile 必須得到相同的詞綴清單")

func test_elite_affix_only_scenario_is_unaffected_by_absent_challenge_field() -> void:
	# 迴歸守則（tasks.md T07：「菁英詞綴/map nodes 不動」）：菁英節點的既有 affix 編譯路徑
	# （只用 encounter.affix_ids，從不涉及 challenge_affix_effect_ids）必須維持完全不變。
	var request := _request([])
	var result := _compiler.compile(request, _catalog([&"effect.elite_affix_0"]))
	assert_true(result.ok, _error_text(result))
	if not result.ok:
		return
	assert_eq(_affix_ids(result), [&"effect.elite_affix_0"])

func _request(challenge_affix_ids: Array[StringName]) -> EncounterCompileRequest:
	var request := EncounterCompileRequest.new()
	request.manifest_digest = DIGEST
	request.encounter_id = &"encounter.fixture"
	request.node_id = &"node_fixture_0000000000000000000000000000000000000000000000000000"
	request.act_index = 1
	request.depth = 0
	request.challenge_level = 1
	request.set(FIELD_NAME, challenge_affix_ids)
	return request

func _affix_ids(result: EncounterCompileResult) -> Array[StringName]:
	var ids: Array[StringName] = []
	for assignment: BattleEffectSourceAssignmentSnapshot in result.preview.affix_effects:
		ids.append(assignment.effect_id)
	return ids

## 最小敵方 encounter：一個合法 spawn（滿足 logical_y 4..7／logical_x 0..7／star 1..3）。
## `native_affix_ids` 同時成為 encounter.affix_ids 與 catalog 已知 effect；
## `additional_known_effect_ids` 只登記進 catalog（代表 challenge_affix_effect_ids 會引用、
## 但不屬於 encounter 自身 affix_ids 的 effect），讓「challenge id 找不到」與
## 「native id 找不到」兩種情形可被獨立測試。
func _catalog(
	native_affix_ids: Array[StringName], additional_known_effect_ids: Array[StringName] = []
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
	encounter.affix_ids = native_affix_ids
	var known_effect_ids: Array[StringName] = native_affix_ids.duplicate()
	for effect_id: StringName in additional_known_effect_ids:
		if not known_effect_ids.has(effect_id):
			known_effect_ids.append(effect_id)
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

func _error_text(result: EncounterCompileResult) -> String:
	if result.ok or result.error == null:
		return ""
	return "%s:%s:%s" % [
		String(result.error.code),
		String(result.error.field_path),
		String(result.error.source_id),
	]
