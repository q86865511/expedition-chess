extends GutTest

## T07 (specs/meta-progression) — ExpeditionGateViewModel：遠征門 ViewModel，開局前(建立遠征
## 前)呈現「最近選擇」「各指揮官最高通關」與「(指揮官/挑戰組合的)生效詞綴清單」，只持
## ProfileState clone 與唯讀內容查詢(registry)，不持可變 domain 物件引用。
## Covers：S5-AC-001（單一狀態源，遠征門為五設施之一）、S5-AC-010（「開局前 ViewModel 可完整
## 列出生效詞綴清單」）；design.md §3、§4.4、§6.3；tasks.md T07 驗收「ExpeditionGate 開局前
## 完整列出」。
##
## ============================== 假設聲明（design.md 未釘死處） ==============================
## design.md §3 只給了「ExpeditionGateViewModel(指揮官/挑戰/生效詞綴列表)」這樣的模組圖標註，
## 未釘死簽名。本檔測試作者依既有 ViewModel 慣例（trait_preview_view_model.gd 的
## "_init(controller, catalog, ...)" 混合 domain 狀態＋唯讀內容依賴的既有模式；
## collection_view_model.gd 的「只持需要的欄位 clone，不持整個 profile 引用」慣例）決定：
##
##   class_name ExpeditionGateViewModel
##   extends RefCounted
##   func _init(profile: ProfileState, registry: ContentRegistryService, manifest_digest: String,
##     resolver: ChallengeAffixResolver = null) -> void
##     -- 只保留 profile.last_selection／profile.commander_challenge_records 的 deep_clone
##        （比照 CollectionViewModel 只保留用得到的兩個欄位，profile==null 時視為兩者皆空/
##        null，不崩潰）；registry/manifest_digest 為唯讀內容依賴（比照
##        TraitPreviewViewModel 持 catalog 的既有慣例，內容查詢非「可變 domain 狀態」，不受
##        「只持 clone」限制的精神約束——ContentRegistryService 本身即唯讀查詢介面）；
##        resolver 預設 new 一個 ChallengeAffixResolver（依賴注入慣例，供測試替換）。
##   func last_selection() -> ProfileLastSelectionState
##     -- 回傳建構時 clone 的 last_selection；profile 未曾建立過遠征（null）時回傳 null。
##   func highest_cleared_level(commander_id: StringName) -> int
##     -- 掃 commander_challenge_records 找該 commander_id 的 highest_cleared_level；
##        找不到回 0（比照「無紀錄視為未挑戰過」的既有慣例，見
##        CommanderChallengeRecordState header comment 的 highest_cleared_level 語意）。
##   func affix_entries(challenge_level: int) -> ChallengeAffixResolveResult
##     -- W4-F9 修正（2026-07-25）：直接回傳 ChallengeAffixResolver.resolve() 的具名結果，
##        不再吞掉失敗——ok=true/entries=[] 為 Challenge 0 真的無詞綴，ok=false 為世代不符/
##        內容缺失等結構性解析失敗，呼叫端可用 .ok/.error 區分兩者（REQ-TECH-006：可失敗
##        操作不得 silent-null；原「沉默降級」慣例會讓兩種語意不同的狀態在 UI 上無法區分）。
## ============================================================================================
##
## GUT 陷阱處理：ExpeditionGateViewModel／ChallengeAffixEntryState 皆為尚不存在的新型別。
## 本檔一律用 load()+GDScript.new()+Object.call()/Object.get() 動態存取（比照
## tests/unit/meta_progression/test_collection_view_model.gd 與本任務
## test_challenge_affix_resolver.gd 的既定慣例）。

const SCRIPT_PATH := "res://presentation/viewmodels/expedition_gate_view_model.gd"


func test_last_selection_reflects_profile_last_selection() -> void:
	var script := _load_script()
	if script == null:
		return
	var profile := _profile_with(ProfileLastSelectionState.new(&"commander.alpha", 2), [])
	var registry := ContentRegistryService.new()
	add_child_autofree(registry)
	var view_model: Object = script.new(profile, registry, "0".repeat(64))
	var selection: Object = view_model.call("last_selection")
	assert_not_null(selection)
	if selection == null:
		return
	assert_eq(selection.get("commander_id"), &"commander.alpha")
	assert_eq(int(selection.get("challenge_level")), 2)


func test_last_selection_is_null_when_profile_has_never_started_an_expedition() -> void:
	var script := _load_script()
	if script == null:
		return
	var profile := _profile_with(null, [])
	var registry := ContentRegistryService.new()
	add_child_autofree(registry)
	var view_model: Object = script.new(profile, registry, "0".repeat(64))
	assert_null(view_model.call("last_selection"))


func test_highest_cleared_level_reflects_commander_challenge_records() -> void:
	var script := _load_script()
	if script == null:
		return
	var records: Array[CommanderChallengeRecordState] = [
		CommanderChallengeRecordState.new(&"commander.alpha", 3),
		CommanderChallengeRecordState.new(&"commander.beta", 1),
	]
	var profile := _profile_with(null, records)
	var registry := ContentRegistryService.new()
	add_child_autofree(registry)
	var view_model: Object = script.new(profile, registry, "0".repeat(64))
	assert_eq(int(view_model.call("highest_cleared_level", &"commander.alpha")), 3)
	assert_eq(int(view_model.call("highest_cleared_level", &"commander.beta")), 1)


func test_highest_cleared_level_is_zero_for_a_commander_with_no_record() -> void:
	var script := _load_script()
	if script == null:
		return
	var profile := _profile_with(null, [])
	var registry := ContentRegistryService.new()
	add_child_autofree(registry)
	var view_model: Object = script.new(profile, registry, "0".repeat(64))
	assert_eq(int(view_model.call("highest_cleared_level", &"commander.never_played")), 0)


func test_view_model_holds_a_clone_not_a_live_profile_reference() -> void:
	# 比照 collection_view_model.gd／trait_preview_view_model.gd 的既定 ViewModel 慣例：
	# 只持 clone/snapshot，不跨操作保留可變 domain 物件引用。
	var script := _load_script()
	if script == null:
		return
	var records: Array[CommanderChallengeRecordState] = [
		CommanderChallengeRecordState.new(&"commander.alpha", 1),
	]
	var profile := _profile_with(null, records)
	var registry := ContentRegistryService.new()
	add_child_autofree(registry)
	var view_model: Object = script.new(profile, registry, "0".repeat(64))
	profile.commander_challenge_records.append(CommanderChallengeRecordState.new(&"commander.alpha", 9))
	assert_eq(
		int(view_model.call("highest_cleared_level", &"commander.alpha")), 1,
		"建構後修改呼叫端的 profile 不得影響已建構的 ViewModel"
	)


func test_affix_entries_for_challenge_zero_is_empty() -> void:
	var script := _load_script()
	if script == null:
		return
	var fixture := _fixture_with_renamed_challenge_chain()
	var registry := ContentRegistryService.new()
	add_child_autofree(registry)
	var installed := registry.install_validated(fixture, "fixture.expedition_gate_vm.1", [&"pack.core"])
	assert_true(installed.ok)
	if not installed.ok:
		return
	var profile := _profile_with(null, [])
	var view_model: Object = script.new(profile, registry, installed.handle.manifest_digest)
	var result: ChallengeAffixResolveResult = view_model.call("affix_entries", 0)
	assert_true(result.ok, "Challenge 0 屬合法輸入，resolve 應成功")
	assert_eq(result.entries.size(), 0, "Challenge 0 開局前應列出空詞綴清單")


func test_affix_entries_lists_generated_challenge_affixes_before_the_run_is_created() -> void:
	var script := _load_script()
	if script == null:
		return
	var fixture := _fixture_with_renamed_challenge_chain()
	var battle_id := &"effect.gate_battle"
	_append_battle_only_effect(fixture, battle_id)
	_set_modifier_refs(fixture, 1, [battle_id])
	var registry := ContentRegistryService.new()
	add_child_autofree(registry)
	var installed := registry.install_validated(fixture, "fixture.expedition_gate_vm.2", [&"pack.core"])
	assert_true(installed.ok)
	if not installed.ok:
		return
	var profile := _profile_with(null, [])
	var view_model: Object = script.new(profile, registry, installed.handle.manifest_digest)
	var result: ChallengeAffixResolveResult = view_model.call("affix_entries", 1)
	assert_true(result.ok, _error_text(result))
	if not result.ok:
		return
	assert_eq(result.entries.size(), 1, "S5-AC-010：建立遠征前必須能完整列出生效詞綴清單")
	if result.entries.size() != 1:
		return
	var entry: ChallengeAffixEntryState = result.entries[0]
	assert_eq(entry.effect_id, battle_id)
	assert_eq(entry.challenge_level, 1)
	assert_eq(entry.track, &"battle_affix", "生效詞綴清單需含分類標籤")


## W4-F9 修正（2026-07-25）：manifest_digest 與已安裝世代不符時，affix_entries() 必須具名
## 失敗（ok=false），不得偽裝成「Challenge 0 真的無詞綴」（兩者修正前都表現為空陣列，UI 上
## 無法區分——REQ-TECH-006 silent-null 契約）。challenge_level 用 1（非 0）以確保 resolver
## 真正嘗試一次 registry 查找，而不是在迴圈開始前就因 challenge_level=0 平凡成功。
func test_affix_entries_surfaces_resolver_failure_distinctly_from_no_affixes() -> void:
	var script := _load_script()
	if script == null:
		return
	var fixture := _fixture_with_renamed_challenge_chain()
	var registry := ContentRegistryService.new()
	add_child_autofree(registry)
	var installed := registry.install_validated(fixture, "fixture.expedition_gate_vm.3", [&"pack.core"])
	assert_true(installed.ok)
	if not installed.ok:
		return
	var profile := _profile_with(null, [])
	var view_model: Object = script.new(profile, registry, "f".repeat(64))
	var result: ChallengeAffixResolveResult = view_model.call("affix_entries", 1)
	assert_false(result.ok, "manifest_digest 與已安裝世代不符時必須具名失敗，不得偽裝成無詞綴")
	assert_not_null(result.error)


func _error_text(result: ChallengeAffixResolveResult) -> String:
	if result == null:
		return "affix_entries() returned null"
	if result.ok:
		return ""
	if result.error == null:
		return "ok=false but error=null"
	return "%s:%s" % [String(result.error.code), String(result.error.field_path)]


func _profile_with(
	last_selection: ProfileLastSelectionState, records: Array[CommanderChallengeRecordState]
) -> ProfileState:
	var empty_names: Array[StringName] = []
	var empty_receipts: Array[SettlementReceiptState] = []
	return ProfileState.new(
		"profile_fixture", U64Bits.zero(), 0, empty_names, empty_names, 0,
		empty_receipts, &"settings.default", last_selection, records
	)


## SyntheticContentFixture 的預設 challenge 鏈 id 為 unlock.challenge_N；改名為
## unlock.slice_challenge_N（同 test_challenge_affix_resolver.gd 的既定假設）。
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


func _find(fixture: ContentValidationInput, content_id: StringName) -> ContentDefinition:
	for definition: ContentDefinition in fixture.definitions:
		if definition.id == content_id:
			return definition
	return null


## Loads presentation/viewmodels/expedition_gate_view_model.gd dynamically so a
## not-yet-existing class produces a normal, GUT-countable failing assertion (load() -> null
## at runtime) instead of a script-load Parse Error that silently excludes the whole file.
func _load_script() -> GDScript:
	var script := load(SCRIPT_PATH) as GDScript
	assert_not_null(
		script,
		"ExpeditionGateViewModel (%s) must exist and take (profile, registry, manifest_digest)" % SCRIPT_PATH
	)
	return script
