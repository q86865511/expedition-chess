extends GutTest

## T07 (specs/meta-progression) — ChallengeAffixResolver：解 challenge unlock 鏈 1..N 的
## modifier_refs，累積（sorted/dedup）並依效果內容分軌（軌 A 敵方 battle affix／軌 B run 層
## operation）。Covers：S5-AC-010（「詞綴 1..N 累積」「Challenge 0 無詞綴」）；design.md
## §6.3:127-129；tasks.md T07 驗收「ChallengeAffixResolver 1..N 累積（sorted/dedup/分軌）」。
##
## 假設聲明（design.md §6.3/§3 只給了呼叫形狀「ChallengeAffixResolver(challenge_level) →
## 敵方 affix effect ids (→EncounterCompiler)」與模組圖描述，未釘死完整簽名/回傳型別/分軌
## 判準；以下為本檔測試作者決定，實作代理請照此實作）：
## 1. 簽名比照既有 RunModifierTableBuilder.build(registry, manifest_digest, ...) 的既定風格
##    （resolver 也需 registry+digest 才能解出 challenge unlock 鏈內容）：
##      class_name ChallengeAffixResolver extends RefCounted
##      func resolve(registry: ContentRegistryService, manifest_digest: String,
##        challenge_level: int) -> ChallengeAffixResolveResult
## 2. ChallengeAffixResolveResult（新型別，RefCounted）：
##      var ok: bool; var error: RunRelicTableError（重用既有錯誤型別/字彙，不另造一套同構
##      Error 類——RESOLVE_FAILED／CATEGORY_MISMATCH／PAYLOAD_INVALID 語意與
##      RunModifierTableBuilder._append_challenge_rules 完全對齊，因為兩者解析同一個
##      unlock.slice_challenge_N 鏈）；var entries: Array[ChallengeAffixEntryState]。
##      static success(entries) / static failure(code, field_path, source_id="")。
## 3. ChallengeAffixEntryState（新型別，RefCounted）：
##      var effect_id: StringName; var challenge_level: int（該效果所屬的解鎖階級）；
##      var track: StringName（&"battle_affix" 或 &"run_modifier"）。
## 4. 分軌判準（純結構性，不解碼 operation 種類——kind 的解碼/是否受支援消費端支援集合是
##    RunModifierTableBuilder 既有職責，resolver 不重複該邏輯）：一個 modifier 效果只要
##    battle_operations 非空 → 產生一筆 track=&"battle_affix" 的 entry；只要 run_operations
##    非空 → 另產生一筆 track=&"run_modifier" 的 entry（兩者非互斥；同一效果理論上可以同時
##    落在兩軌，各自一筆）。battle_operations／run_operations 皆空的效果不產生任何 entry。
## 5. 累積範圍：level in 1..challenge_level（含），與 RunModifierTableBuilder 完全一致；
##    challenge_level=0 → entries 為空陣列，ok=true（不視為錯誤）。
## 6. 去重：同一 effect_id 只產生一筆 entry，保留其首次出現（最低）階級的一筆——同一
##    challenge_level 內 modifier_refs 本就不可能重複（canonical set，見
##    test_duplicate_effect_id_within_the_same_level_is_rejected_at_the_content_boundary）；
##    跨 level 重複列出同一 effect_id 時亦去重，只保留最低階級那筆（W4-F7 修正 2026-07-25，
##    對齊 design §6.3「sorted, dedup」字面契約，見
##    test_duplicate_effect_id_across_different_levels_is_deduplicated_to_the_lowest_level）。
## 7. 決定性排序：entries 依 (challenge_level 升序, effect_id 字典序, track 字典序) 排序。
## 8. unlock id 命名慣例、走訪方式與 RunModifierTableBuilder._append_challenge_rules 完全
##    相同（unlock.slice_challenge_%d、逐一 resolve，見該檔案假設聲明的完整論證，此處不重複）。
##
## GUT 陷阱處理：ChallengeAffixResolver / ChallengeAffixResolveResult / ChallengeAffixEntryState
## 皆為尚不存在的新型別。本檔一律用 load()+GDScript.new()+Object.call()/Object.get() 動態存取
## （比照 tests/unit/meta_progression/test_collection_view_model.gd 的既定慣例：中介變數宣告為
## Object／Array，不宣告為任何新 class_name，杜絕整檔 parse error 靜默排除)。

const SCRIPT_PATH := "res://domain/run/build/challenge_affix_resolver.gd"


func test_challenge_level_zero_returns_no_entries() -> void:
	var fixture := _fixture_with_renamed_challenge_chain()
	var registry := ContentRegistryService.new()
	add_child_autofree(registry)
	var installed := registry.install_validated(fixture, "fixture.challenge_affix_resolver.1", [&"pack.core"])
	assert_true(installed.ok)
	if not installed.ok:
		return
	var result := _resolve(registry, installed.handle.manifest_digest, 0)
	if result == null:
		return
	assert_true(bool(result.get("ok")), _error_text(result))
	if not bool(result.get("ok")):
		return
	assert_eq(_entry_strings(result.get("entries")), [], "Challenge 0 無詞綴")


func test_battle_operation_only_effect_is_classified_into_battle_affix_track() -> void:
	var fixture := _fixture_with_renamed_challenge_chain()
	var effect_id := &"effect.challenge_battle_only"
	_append_battle_only_effect(fixture, effect_id)
	_set_modifier_refs(fixture, 1, [effect_id])
	var registry := ContentRegistryService.new()
	add_child_autofree(registry)
	var installed := registry.install_validated(fixture, "fixture.challenge_affix_resolver.2", [&"pack.core"])
	assert_true(installed.ok)
	if not installed.ok:
		return
	var result := _resolve(registry, installed.handle.manifest_digest, 1)
	if result == null:
		return
	assert_true(bool(result.get("ok")), _error_text(result))
	if not bool(result.get("ok")):
		return
	assert_eq(
		_entry_strings(result.get("entries")),
		["effect.challenge_battle_only|1|battle_affix"]
	)


func test_run_operation_only_effect_is_classified_into_run_modifier_track() -> void:
	var fixture := _fixture_with_renamed_challenge_chain()
	var effect_id := &"effect.challenge_run_only"
	_append_run_only_effect(fixture, effect_id)
	_set_modifier_refs(fixture, 1, [effect_id])
	var registry := ContentRegistryService.new()
	add_child_autofree(registry)
	var installed := registry.install_validated(fixture, "fixture.challenge_affix_resolver.3", [&"pack.core"])
	assert_true(installed.ok)
	if not installed.ok:
		return
	var result := _resolve(registry, installed.handle.manifest_digest, 1)
	if result == null:
		return
	assert_true(bool(result.get("ok")), _error_text(result))
	if not bool(result.get("ok")):
		return
	assert_eq(
		_entry_strings(result.get("entries")),
		["effect.challenge_run_only|1|run_modifier"]
	)


func test_entries_accumulate_across_levels_one_to_n() -> void:
	var fixture := _fixture_with_renamed_challenge_chain()
	var battle_id := &"effect.challenge_battle_l1"
	var run_id := &"effect.challenge_run_l2"
	_append_battle_only_effect(fixture, battle_id)
	_append_run_only_effect(fixture, run_id)
	_set_modifier_refs(fixture, 1, [battle_id])
	_set_modifier_refs(fixture, 2, [run_id])
	var registry := ContentRegistryService.new()
	add_child_autofree(registry)
	var installed := registry.install_validated(fixture, "fixture.challenge_affix_resolver.4", [&"pack.core"])
	assert_true(installed.ok)
	if not installed.ok:
		return
	var level1 := _resolve(registry, installed.handle.manifest_digest, 1)
	var level2 := _resolve(registry, installed.handle.manifest_digest, 2)
	if level1 == null or level2 == null:
		return
	assert_true(bool(level1.get("ok")), _error_text(level1))
	assert_true(bool(level2.get("ok")), _error_text(level2))
	if not bool(level1.get("ok")) or not bool(level2.get("ok")):
		return
	assert_eq(
		_entry_strings(level1.get("entries")),
		["effect.challenge_battle_l1|1|battle_affix"],
		"level 1 只累積 slice_challenge_1"
	)
	assert_eq(
		_entry_strings(level2.get("entries")),
		["effect.challenge_battle_l1|1|battle_affix", "effect.challenge_run_l2|2|run_modifier"],
		"level 2 累積 slice_challenge_1(戰)+slice_challenge_2(經)，對齊「詞綴 1..N 累積」"
	)


## w4 仲裁（2026-07-25）：原案以 modifier_refs=[id, id] 測 resolver 去重，但 modifier_refs 是
## canonical set（content_canonical_codec_v1._is_canonical_set 要求元素嚴格遞增），重複 stable id
## 在 install_validated 的編碼階段即被拒（CONTENT_CODEC_INVALID:payload.codec），永遠到不了
## resolver。改為釘住這個更早、更強的不變量：重複 ref 在內容邊界就被拒載，故 resolver 看得到的
## 輸入必然已去重。
func test_duplicate_effect_id_within_the_same_level_is_rejected_at_the_content_boundary() -> void:
	var fixture := _fixture_with_renamed_challenge_chain()
	var effect_id := &"effect.challenge_dup"
	_append_battle_only_effect(fixture, effect_id)
	_set_modifier_refs(fixture, 1, [effect_id, effect_id])
	var registry := ContentRegistryService.new()
	add_child_autofree(registry)
	var installed := registry.install_validated(fixture, "fixture.challenge_affix_resolver.5", [&"pack.core"])
	assert_false(
		installed.ok,
		"modifier_refs 為 canonical set，重複 stable id 必須在內容邊界拒載，不得進入 registry"
	)


## W4-F7 修正（2026-07-25）：同一 effect_id 被兩個不同階級的 modifier_refs 各自引用時，
## Challenge 3 只產生一筆 entry（保留最低階級 level1），不得重複列出——修正前 seen 只在單一
## level 迴圈內宣告，跨階級不去重，會產生兩筆重複 entry（ViewModel 重複顯示、若下游依此清單
## 計數則雙倍計）。level 2 刻意不覆寫，保留 fixture 預設的 effect.challenge_affix_1
## （battle_affix track）：一併證明 dedup 只影響真正重複的 effect_id，不會誤刪其他階級的
## 獨立內容（呼應「詞綴 1..N 累積」語意，不是把整個清單清空重算）。
func test_duplicate_effect_id_across_different_levels_is_deduplicated_to_the_lowest_level() -> void:
	var fixture := _fixture_with_renamed_challenge_chain()
	var effect_id := &"effect.challenge_cross_level_dup"
	_append_run_only_effect(fixture, effect_id)
	_set_modifier_refs(fixture, 1, [effect_id])
	_set_modifier_refs(fixture, 3, [effect_id])
	var registry := ContentRegistryService.new()
	add_child_autofree(registry)
	var installed := registry.install_validated(fixture, "fixture.challenge_affix_resolver.8", [&"pack.core"])
	assert_true(installed.ok)
	if not installed.ok:
		return
	var result := _resolve(registry, installed.handle.manifest_digest, 3)
	if result == null:
		return
	assert_true(bool(result.get("ok")), _error_text(result))
	if not bool(result.get("ok")):
		return
	assert_eq(
		_entry_strings(result.get("entries")),
		[
			"effect.challenge_cross_level_dup|1|run_modifier",
			"effect.challenge_affix_1|2|battle_affix",
		],
		"level1/level3 的重複 effect 只保留 level1 一筆；level2 的獨立 fixture 預設內容不受影響，軌 B 不得雙倍計"
	)

func test_resolve_is_deterministic_for_identical_inputs() -> void:
	var fixture := _fixture_with_renamed_challenge_chain()
	var battle_id := &"effect.challenge_battle_det"
	var run_id := &"effect.challenge_run_det"
	_append_battle_only_effect(fixture, battle_id)
	_append_run_only_effect(fixture, run_id)
	_set_modifier_refs(fixture, 1, [battle_id])
	_set_modifier_refs(fixture, 2, [run_id])
	var registry := ContentRegistryService.new()
	add_child_autofree(registry)
	var installed := registry.install_validated(fixture, "fixture.challenge_affix_resolver.6", [&"pack.core"])
	assert_true(installed.ok)
	if not installed.ok:
		return
	var first := _resolve(registry, installed.handle.manifest_digest, 2)
	var second := _resolve(registry, installed.handle.manifest_digest, 2)
	if first == null or second == null:
		return
	assert_true(bool(first.get("ok")), _error_text(first))
	assert_true(bool(second.get("ok")), _error_text(second))
	if not bool(first.get("ok")) or not bool(second.get("ok")):
		return
	assert_eq(_entry_strings(first.get("entries")), _entry_strings(second.get("entries")))


func test_unknown_manifest_digest_returns_named_failure() -> void:
	# UnlockDef.modifier_refs 若指向內容中不存在的 effect id，install_validated() 會在
	# _validate_dependencies 階段就以 CONTENT_REFERENCE_MISSING 拒絕安裝——不可能建構出
	# 「已安裝成功但 resolver 解析時才發現 effect 缺失」的情境。改驗 resolver 對「digest
	# 在 registry 中根本沒有對應世代」的具名失敗路徑，等價覆蓋同一個「解析失敗必須具名拒絕、
	# 不得靜默回空結果」契約（呼應 RunModifierTableBuilder._append_challenge_rules 對
	# resolve() 失敗的既有處理）。
	var fixture := _fixture_with_renamed_challenge_chain()
	var registry := ContentRegistryService.new()
	add_child_autofree(registry)
	var installed := registry.install_validated(fixture, "fixture.challenge_affix_resolver.7", [&"pack.core"])
	assert_true(installed.ok)
	if not installed.ok:
		return
	var result := _resolve(registry, "f".repeat(64), 1)
	if result == null:
		return
	assert_false(bool(result.get("ok")), "無效/不存在的 manifest_digest 必須讓 resolve 具名失敗，不得靜默回空結果")
	assert_not_null(result.get("error"))


func _resolve(registry: ContentRegistryService, manifest_digest: String, challenge_level: int) -> Object:
	var script := _load_script()
	if script == null:
		return null
	var resolver: Object = script.new()
	return resolver.call("resolve", registry, manifest_digest, challenge_level)


func _entry_strings(entries: Array) -> Array[String]:
	var result: Array[String] = []
	for entry: Object in entries:
		result.append("%s|%d|%s" % [
			String(entry.get("effect_id")),
			int(entry.get("challenge_level")),
			String(entry.get("track")),
		])
	return result


func _error_text(result: Object) -> String:
	if result == null:
		return "resolve() returned null"
	if bool(result.get("ok")):
		return ""
	var error: Object = result.get("error")
	if error == null:
		return "ok=false but error=null"
	return "%s:%s" % [String(error.get("code")), String(error.get("field_path"))]


## SyntheticContentFixture 的預設 challenge 鏈 id 為 unlock.challenge_N；改名為
## unlock.slice_challenge_N 以對齊真實內容命名慣例（同 test_run_modifier_table_builder.gd
## 的假設 3：ContentRegistryService 沒有列舉能力，resolver 必須用已知命名逐一 resolve）。
func _fixture_with_renamed_challenge_chain() -> ContentValidationInput:
	var fixture := SyntheticContentFixture.build_valid()
	for level in range(6):
		var unlock := _find(fixture, StringName("unlock.challenge_%d" % level)) as UnlockDef
		assert_not_null(unlock, "SyntheticContentFixture 應含 unlock.challenge_%d" % level)
		unlock.id = StringName("unlock.slice_challenge_%d" % level)
	for level in range(1, 6):
		var unlock := _find(fixture, StringName("unlock.slice_challenge_%d" % level)) as UnlockDef
		unlock.prerequisite_refs = [StringName("unlock.slice_challenge_%d" % (level - 1))]
	return fixture


func _set_modifier_refs(fixture: ContentValidationInput, level: int, effect_ids: Array[StringName]) -> void:
	var unlock := _find(fixture, StringName("unlock.slice_challenge_%d" % level)) as UnlockDef
	assert_not_null(unlock)
	unlock.modifier_refs = effect_ids


## 純軌 A 探針效果：只有 battle_operations，run_operations 保持空陣列。
## T10：這兩個探針效果全部透過 _set_modifier_refs 掛進 challenge 鏈，CONTENT_CHALLENGE_AFFIX_ROLE
## 收緊為「必須恰為 challenge_affix」後不可再用預設的 &"general"。
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
	effect.schema_version = 1
	effect.display_name_key = StringName("loc.%s" % String(effect_id))
	effect.content_role = &"challenge_affix"
	effect.trigger = &"battle_start"
	effect.stacking = &"replace"
	effect.max_stacks = 1
	effect.duration_ticks = 20
	effect.battle_operations = [operation]
	fixture.definitions.append(effect)


## 純軌 B 探針效果：只有 run_operations（add_gold，既有 always-active 支援集合成員），
## battle_operations 保持空陣列。
func _append_run_only_effect(fixture: ContentValidationInput, effect_id: StringName) -> void:
	var operation := AddGoldOperationDef.new()
	operation.operation_index = 0
	operation.amount = 1
	operation.claim_scope = &"always"
	var effect := EffectDef.new()
	effect.id = effect_id
	effect.schema_version = 1
	effect.display_name_key = StringName("loc.%s" % String(effect_id))
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


## Loads domain/run/build/challenge_affix_resolver.gd dynamically so a not-yet-existing
## class produces a normal, GUT-countable failing assertion (load() -> null at runtime)
## instead of a script-load Parse Error that silently excludes the whole file from the run.
func _load_script() -> GDScript:
	var script := load(SCRIPT_PATH) as GDScript
	assert_not_null(
		script,
		"ChallengeAffixResolver (%s) must exist and expose resolve(registry, manifest_digest, challenge_level)" % SCRIPT_PATH
	)
	return script
