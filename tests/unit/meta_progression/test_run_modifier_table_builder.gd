extends GutTest

## T06(specs/meta-progression) — RunModifierTableBuilder：relic(沿用既有解析)＋
## commander(passive_effect_refs → always-active)＋challenge(unlock 鏈 1..N → always-active
## 通道，本波僅建通道與參數，wave4 才有內容)。
## Covers：S5-AC-003；tasks.md T06 驗收：「新 RunModifierTableBuilder.build(registry,digest,
## relic_ids,commander_id,challenge_level)（內部沿用既有 RunRelicTableBuilder 解析 relic，
## 另解 commander.passive_effect_refs 為 always-active 規則；challenge 規則本波僅建通道與
## 參數（wave4 才有內容），以空/合成清單的測試覆蓋)」。
## 依據 design.md §6.1:112-117。
##
## 假設聲明(design.md 未給精確簽名/內部機制，本檔依既有慣例與可推導事實釘定，逐條列出)：
## 1. build() 為實例方法(RunModifierTableBuilder.new().build(...))，回傳型別重用既有
##    RunRelicTableBuildResult(專案慣例：新 builder 產出同一個 RunRelicTable，理應共用同一個
##    typed result，不另造一個同構的新型別)。
## 2. commander_id 解析失敗(找不到/非 commander 分類)回傳具名失敗(built.ok==false)——
##    比照 RunRelicTableBuilder 對 relic_ids 解析失敗的既有慣例；本檔只斷言 ok==false 與
##    error!=null，錯誤碼是否重用 RunRelicTableError.RESOLVE_FAILED 為次要斷言(標註於該測試)。
## 3. 【關鍵假設，逐項證據列出】challenge unlock 鏈的走訪方式：ContentRegistryService 目前只有
##    resolve(單一 content_ref)一種查詢管道(已通篇檢視 content_registry_service.gd 的公開
##    方法：install_validated/resolve/try_resolve/validate_all/latest_catalog_handle/
##    catalog_handle/acquire_catalog_lease/release_catalog_lease/rebuild_from_probe/
##    compile_pinned_generation/register_legacy_v1_generation/legacy_v1_generation，
##    沒有任何一個能「列出某分類全部 id」)，故 builder 必須以「已知 id」逐一 resolve，
##    不可能靠列舉推導 challenge_level(int) 對應哪些 unlock。真實內容(見
##    content/packs/vertical_slice/unlocks/slice_challenge_{0..5}.tres 的 id 皆為
##    unlock.slice_challenge_{N})已固定此命名慣例，且本專案僅有 vertical_slice 一個內容包
##    (非通用多包插件系統)，design.md §2 版本策略表也未列出對 ContentRegistryService 新增
##    列舉能力——三者合證，本檔假設 builder 以 StringName("unlock.slice_challenge_%d" % level)
##    對 level in 1..challenge_level(含)逐一 resolve、累積其 modifier_refs 中可解碼為
##    run_operations 的部分。content_validator._validate_challenge_chain(:276-293)已確認
##    「level/prerequisite_refs/modifier_refs 是否符合鏈完整性」只依內容物的欄位值判斷，
##    不依賴任何 id 字面樣式，故本檔可安全地把 SyntheticContentFixture 內建的
##    unlock.challenge_{N} 重新命名為 unlock.slice_challenge_{N}(連同 prerequisite_refs
##    同步改名)而不影響驗證通過。若實作採用不同機制(例如改由呼叫端傳入已解析的 unlock id
##    清單)，屬合理的替代設計——測試爭議由實作代理依既定協議回報。
##
## 範圍聲明：本檔不驗證「決定性順序(slot 升序→commander→challenge 字典序)」的內部陣列
## 排序細節——sum_always_active/always_active_count 為無條件加總，整數加總滿足交換律，
## 排序不影響其數值結果，設計文字對此描述屬實作可讀性/未來擴充考量而非可觀察契約；
## 「同輸入兩次呼叫得到相同結果」的決定性已由本檔與 test_run_relic_table_always_active.gd
## 覆蓋。population_bonus 屬 T05,不在本任務。三名被動非同一效果數值階級屬內容驗證(T10)，
## 不在本任務。

func test_relic_only_resolution_matches_standalone_run_relic_table_builder() -> void:
	var registry := ContentRegistryService.new()
	add_child_autofree(registry)
	var fixture := SyntheticContentFixture.build_valid()
	var installed := registry.install_validated(fixture, "fixture.run_modifier.1", [&"pack.core"])
	assert_true(installed.ok)
	if not installed.ok:
		return
	var relic_ids: Array[StringName] = [&"relic.r4"]
	var standalone := RunRelicTableBuilder.new().build(registry, installed.handle.manifest_digest, relic_ids)
	assert_true(standalone.ok)
	if not standalone.ok:
		return
	var built := RunModifierTableBuilder.new().build(
		registry, installed.handle.manifest_digest, relic_ids, &"commander.c0", 0
	)
	assert_true(built.ok, "commander.c0(passive=effect.general,空 run_operations)+challenge_level=0 不應讓 build 失敗")
	if not built.ok:
		return
	var relic_rule := built.table.try_relic_rule(&"relic.r4")
	var standalone_rule := standalone.table.try_relic_rule(&"relic.r4")
	assert_not_null(relic_rule)
	assert_not_null(standalone_rule)
	if relic_rule == null or standalone_rule == null:
		return
	assert_eq(relic_rule.category, standalone_rule.category)
	assert_eq(relic_rule.run_operations.size(), standalone_rule.run_operations.size())
	assert_eq(relic_rule.source, &"relic", "relic 規則經 RunModifierTableBuilder 仍須標記 source=relic")
	assert_eq(
		built.table.sum_operation_amount(relic_ids, &"economy", &"add_gold"),
		standalone.table.sum_operation_amount(relic_ids, &"economy", &"add_gold"),
		"relic 部分的 slot-gated 加總必須與獨立呼叫 RunRelicTableBuilder 完全一致"
	)

func test_commander_with_no_run_operations_does_not_fail_build_and_contributes_nothing() -> void:
	var registry := ContentRegistryService.new()
	add_child_autofree(registry)
	var fixture := SyntheticContentFixture.build_valid()
	var installed := registry.install_validated(fixture, "fixture.run_modifier.2", [&"pack.core"])
	assert_true(installed.ok)
	if not installed.ok:
		return
	var no_relics: Array[StringName] = []
	var built := RunModifierTableBuilder.new().build(
		registry, installed.handle.manifest_digest, no_relics, &"commander.c0", 0
	)
	assert_true(built.ok, "commander 的 passive 目前不帶任何 run_operations(本波僅建通道)不應讓 build 失敗")
	if not built.ok:
		return
	assert_eq(built.table.sum_always_active(&"economy", &"add_gold"), 0)
	assert_eq(built.table.always_active_count(&"economy"), 0)
	assert_eq(built.table.always_active_count(&"route"), 0)

func test_commander_passive_run_operations_become_always_active_contribution() -> void:
	var registry := ContentRegistryService.new()
	add_child_autofree(registry)
	var fixture := SyntheticContentFixture.build_valid()
	# effect.operation_matrix 為既有 fixture 內容,帶 add_gold=1/add_xp=1/heal_expedition_hp=1
	# (皆 claim_scope=always)。add_xp 無 always-active 消費端、builder 會具名拒絕(見
	# test_commander_passive_with_unconsumed_run_kind_returns_named_failure),此處先剔除,
	# 以剩餘兩筆驗證「非 battle 遺物已支援的 run intent 解碼機制」同樣套用在 commander 來源上。
	_strip_add_xp_from_operation_matrix(fixture)
	(_find(fixture, &"commander.c0") as CommanderDef).passive_effect_refs = [&"effect.operation_matrix"]
	var installed := registry.install_validated(fixture, "fixture.run_modifier.3", [&"pack.core"])
	assert_true(installed.ok)
	if not installed.ok:
		return
	var no_relics: Array[StringName] = []
	var built := RunModifierTableBuilder.new().build(
		registry, installed.handle.manifest_digest, no_relics, &"commander.c0", 0
	)
	assert_true(built.ok)
	if not built.ok:
		return
	assert_eq(
		built.table.sum_always_active(&"economy", &"add_gold"), 1,
		"commander.c0 被動的 add_gold=1 應成為 economy 類 always-active 貢獻"
	)
	assert_eq(
		built.table.sum_always_active(&"rule", &"heal_expedition_hp"), 1,
		"同一效果的 heal_expedition_hp=1 應成為 rule 類 always-active 貢獻"
	)
	assert_eq(built.table.always_active_count(&"economy"), 1)

func test_commander_always_active_contribution_stacks_with_slot_gated_relic_end_to_end_via_income_service() -> void:
	var registry := ContentRegistryService.new()
	add_child_autofree(registry)
	var fixture := SyntheticContentFixture.build_valid()
	_strip_add_xp_from_operation_matrix(fixture)
	(_find(fixture, &"commander.c0") as CommanderDef).passive_effect_refs = [&"effect.operation_matrix"]
	var installed := registry.install_validated(fixture, "fixture.run_modifier.4", [&"pack.core"])
	assert_true(installed.ok)
	if not installed.ok:
		return
	# relic.r4 為 economy 類、effect_refs=[effect.operation_matrix](同一份 add_gold=1 定義)。
	var relic_ids: Array[StringName] = [&"relic.r4"]
	var built := RunModifierTableBuilder.new().build(
		registry, installed.handle.manifest_digest, relic_ids, &"commander.c0", 0
	)
	assert_true(built.ok)
	if not built.ok:
		return
	var catalog := EconomyTestFixture.catalog(installed.handle.manifest_digest)
	var result := IncomeService.new().quote(IncomeQuoteRequest.new(
		&"run_fixture", &"node_fixture", 0,
		EconomyState.new(47, 3, 0, 5, 0, 0, []), U64Bits.zero(),
		catalog, built.table, relic_ids
	))
	assert_true(result.ok)
	if not result.ok:
		return
	# baseline(見 test_income_service_relics.gd)= 58；+1 slot-gated relic.r4 的 add_gold
	# ＋1 commander always-active 的 add_gold(同一 effect.operation_matrix,兩來源分別計入)。
	assert_eq(
		result.transaction.economy_state.gold, 60,
		"58 baseline + 1 slot-gated(relic.r4) + 1 commander always-active,經完整" +
		"registry→RunModifierTableBuilder→IncomeService 管線"
	)

func test_challenge_level_zero_yields_no_challenge_contribution_even_when_higher_levels_have_content() -> void:
	var l1_effect_id := &"effect.challenge_l1_bonus"
	var fixture := _fixture_with_renamed_challenge_chain()
	_append_add_gold_effect(fixture, l1_effect_id, 1)
	(_find(fixture, &"unlock.slice_challenge_1") as UnlockDef).modifier_refs = [l1_effect_id]
	var registry := ContentRegistryService.new()
	add_child_autofree(registry)
	var installed := registry.install_validated(fixture, "fixture.run_modifier.5", [&"pack.core"])
	assert_true(installed.ok)
	if not installed.ok:
		return
	var no_relics: Array[StringName] = []
	var built := RunModifierTableBuilder.new().build(
		registry, installed.handle.manifest_digest, no_relics, &"commander.c0", 0
	)
	assert_true(built.ok)
	if not built.ok:
		return
	assert_eq(
		built.table.sum_always_active(&"economy", &"add_gold"), 0,
		"challenge_level=0 時,即使 slice_challenge_1 已著作 add_gold 內容,也不應被計入" +
		"(Challenge 0 無詞綴)"
	)

func test_challenge_chain_at_requested_level_contributes_its_modifiers() -> void:
	var l1_effect_id := &"effect.challenge_l1_bonus"
	var fixture := _fixture_with_renamed_challenge_chain()
	_append_add_gold_effect(fixture, l1_effect_id, 1)
	(_find(fixture, &"unlock.slice_challenge_1") as UnlockDef).modifier_refs = [l1_effect_id]
	var registry := ContentRegistryService.new()
	add_child_autofree(registry)
	var installed := registry.install_validated(fixture, "fixture.run_modifier.6", [&"pack.core"])
	assert_true(installed.ok)
	if not installed.ok:
		return
	var no_relics: Array[StringName] = []
	var built := RunModifierTableBuilder.new().build(
		registry, installed.handle.manifest_digest, no_relics, &"commander.c0", 1
	)
	assert_true(built.ok)
	if not built.ok:
		return
	assert_eq(built.table.sum_always_active(&"economy", &"add_gold"), 1)

func test_challenge_chain_accumulates_contributions_across_multiple_levels() -> void:
	var l1_effect_id := &"effect.challenge_l1_bonus"
	var l2_effect_id := &"effect.challenge_l2_bonus"
	var fixture := _fixture_with_renamed_challenge_chain()
	_append_add_gold_effect(fixture, l1_effect_id, 1)
	_append_add_gold_effect(fixture, l2_effect_id, 2)
	(_find(fixture, &"unlock.slice_challenge_1") as UnlockDef).modifier_refs = [l1_effect_id]
	(_find(fixture, &"unlock.slice_challenge_2") as UnlockDef).modifier_refs = [l2_effect_id]
	var registry := ContentRegistryService.new()
	add_child_autofree(registry)
	var installed := registry.install_validated(fixture, "fixture.run_modifier.7", [&"pack.core"])
	assert_true(installed.ok)
	if not installed.ok:
		return
	var no_relics: Array[StringName] = []
	var built_level_1 := RunModifierTableBuilder.new().build(
		registry, installed.handle.manifest_digest, no_relics, &"commander.c0", 1
	)
	var built_level_2 := RunModifierTableBuilder.new().build(
		registry, installed.handle.manifest_digest, no_relics, &"commander.c0", 2
	)
	assert_true(built_level_1.ok)
	assert_true(built_level_2.ok)
	if not built_level_1.ok or not built_level_2.ok:
		return
	assert_eq(built_level_1.table.sum_always_active(&"economy", &"add_gold"), 1, "level 1 只累積 slice_challenge_1")
	assert_eq(
		built_level_2.table.sum_always_active(&"economy", &"add_gold"), 3,
		"level 2 累積 slice_challenge_1(1)+slice_challenge_2(2)=3,對齊「詞綴 1..N 累積」"
	)

func test_invalid_commander_id_returns_named_failure() -> void:
	var registry := ContentRegistryService.new()
	add_child_autofree(registry)
	var fixture := SyntheticContentFixture.build_valid()
	var installed := registry.install_validated(fixture, "fixture.run_modifier.8", [&"pack.core"])
	assert_true(installed.ok)
	if not installed.ok:
		return
	var no_relics: Array[StringName] = []
	var built := RunModifierTableBuilder.new().build(
		registry, installed.handle.manifest_digest, no_relics, &"commander.does_not_exist", 0
	)
	assert_false(built.ok, "不存在的 commander_id 必須回傳具名失敗,不得產出部分表")
	assert_not_null(built.error)
	if built.error == null:
		return
	# 次要斷言(較弱信心)：比照 RunRelicTableBuilder 對無法解析 id 的既有慣例重用
	# RunRelicTableError.RESOLVE_FAILED；若實作選擇不同但同樣具名的錯誤碼,此斷言可能需要
	# 依測試爭議協議調整,不影響上面「ok==false 且 error 非空」這個核心契約。
	assert_eq(built.error.code, RunRelicTableError.RESOLVE_FAILED)

## commander/challenge 的 run operation kind 必須落在 always-active 消費端支援集合
## ({add_gold, shop_discount, heal_expedition_hp}),否則 build 具名拒絕——杜絕
## 「建表成功但無任何消費端讀取、效果靜默歸零」(RunModifierTableBuilder 把關契約)。
func test_commander_passive_with_unconsumed_run_kind_returns_named_failure() -> void:
	var registry := ContentRegistryService.new()
	add_child_autofree(registry)
	var fixture := SyntheticContentFixture.build_valid()
	# operation_matrix 原樣含 add_xp(無 always-active 消費端)——期望被具名拒絕。
	(_find(fixture, &"commander.c0") as CommanderDef).passive_effect_refs = [&"effect.operation_matrix"]
	var installed := registry.install_validated(fixture, "fixture.run_modifier.9", [&"pack.core"])
	assert_true(installed.ok)
	if not installed.ok:
		return
	var no_relics: Array[StringName] = []
	var built := RunModifierTableBuilder.new().build(
		registry, installed.handle.manifest_digest, no_relics, &"commander.c0", 0
	)
	assert_false(built.ok, "含 add_xp 的被動必須 build 失敗,不得靜默產出無消費端的規則")
	assert_not_null(built.error)
	if built.error == null:
		return
	assert_eq(built.error.code, RunRelicTableError.UNSUPPORTED_ALWAYS_ACTIVE_KIND)

## 把 effect.operation_matrix 中無 always-active 消費端的 add_xp 剔除(operation_index 重編為
## 連續),讓既有「解碼機制沿用」測試聚焦於受支援的 kind。
func _strip_add_xp_from_operation_matrix(fixture: ContentValidationInput) -> void:
	var matrix := _find(fixture, &"effect.operation_matrix") as EffectDef
	var supported: Array[RunOperationDef] = []
	for operation: RunOperationDef in matrix.run_operations:
		if operation is AddXpOperationDef:
			continue
		supported.append(operation)
	for index in supported.size():
		supported[index].operation_index = index
	matrix.run_operations = supported

## W4-F7（2026-07-25）：同一 effect_id 掛在兩個挑戰階級時，run 層貢獻只能計一次——否則
## sum_always_active 會把同一份詞綴加總兩次（與 ChallengeAffixResolver 的清單去重同語意）。
func test_same_effect_on_two_challenge_levels_contributes_only_once() -> void:
	var effect_id := &"effect.challenge_shared_bonus"
	var fixture := _fixture_with_renamed_challenge_chain()
	_append_add_gold_effect(fixture, effect_id, 3)
	(_find(fixture, &"unlock.slice_challenge_1") as UnlockDef).modifier_refs = [effect_id]
	(_find(fixture, &"unlock.slice_challenge_2") as UnlockDef).modifier_refs = [effect_id]
	var registry := ContentRegistryService.new()
	add_child_autofree(registry)
	var installed := registry.install_validated(fixture, "fixture.run_modifier.10", [&"pack.core"])
	assert_true(installed.ok)
	if not installed.ok:
		return
	var no_relics: Array[StringName] = []
	var built := RunModifierTableBuilder.new().build(
		registry, installed.handle.manifest_digest, no_relics, &"commander.c0", 2
	)
	assert_true(built.ok)
	if not built.ok:
		return
	assert_eq(
		built.table.sum_always_active(&"economy", &"add_gold"), 3,
		"同一 effect 被 level1 與 level2 引用時只計一次（3），不得雙倍計（6）"
	)

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

func _append_add_gold_effect(fixture: ContentValidationInput, effect_id: StringName, amount: int) -> void:
	var operation := AddGoldOperationDef.new()
	operation.operation_index = 0
	operation.amount = amount
	operation.claim_scope = &"always"
	var effect := EffectDef.new()
	effect.id = effect_id
	effect.schema_version = 1
	effect.display_name_key = StringName("loc.%s" % String(effect_id))
	effect.content_role = &"general"
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
