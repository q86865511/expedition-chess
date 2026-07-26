extends GutTest

## T10 (specs/meta-progression) — S5-AC-004 局外成長禁提基礎戰力：
##   (a) 同一 content manifest 下，UnitDef 的 compiled 基礎 stats 不因局外解鎖（購買）
##       前後而改變；
##   (b) 新增 ContentValidator 規則 CONTENT_META_FORBIDDEN_GROWTH：unlock 的
##       unlocked_content_refs／modifier_refs 不得宣告永久基礎生命/攻防提升、商店
##       免費刷新（reroll_cost 歸零）、固定起始人口。
## Covers：S5-AC-004；design.md §7.2；requirements.md S5-AC-004；tasks.md T10
## 驗收「CONTENT_META_FORBIDDEN_GROWTH...非零退出＋具名 issue；...解鎖前後同
## UnitDef compiled stats 逐欄相等測試」。對齊 design.md §12 測試策略表 004 列
## test_meta_growth_forbids_base_power_and_validator_rejects（本檔含 (a)(b) 兩面向
## 的多個 func test_*，同一 AC 的多個場景拆成獨立測試方便個別除錯，非設計文件要求
## 逐字一個 func）。
##
## ============================== 假設聲明（design.md 未釘死處） ==============================
## 1. 「compiled 基礎 stats」讀法：沿用 tests/fixtures/content/content_verification_suite.gd
##    的既有慣例（_case_registry_pinning:154-193 已驗證的 schema 佈局，_view_health:628-629
##    讀 view.payload.children[5].children[0].int_value，且該案例經
##    tests/unit/content_registry/test_content_registry.gd:11 實際執行、現行為綠）——
##    ContentDefinitionView.payload 對 UnitDef 的 children[5] 是 base_stats 記錄，其內
##    children[0..3] 依 UnitStatsDef 欄位宣告順序（health/attack/armor/magic_resist，見
##    content/definitions/unit_stats_def.gd:4-7）依序對應。本檔比較這 4 欄（"基礎生命/
##    攻防"）在「局外解鎖動作前後」是否逐欄相等；讀取方式與既有 _view_health 完全一致，非
##    本檔發明的新機制。
## 2. 「解鎖前後」的操作定義：design.md §4.3 明訂 PurchaseUnlockCommand/UnlockPurchaseService
##    的簽章是 (profile: ProfileState, unlock_def: UnlockDef) -> 具名 result，不接受、也不
##    接觸任何 ContentRegistryService/ContentDefinition 物件——「解鎖」在這個架構下純粹是
##    ProfileState.unlocked_content_ids 的集合運算。本檔因此實際執行一次真正的
##    PurchaseUnlockCommand.apply_to()（而非只是把同一個 digest resolve 兩次這種平凡恆真
##    檢查），驗證這個真實指令執行前後、同一 ContentRegistryService/同一 manifest_digest 下
##    解析同一 UnitDef 得到的 4 個基礎欄位位元組完全相同。
## 3. 【核心判斷，務必在派工回報中轉達】CONTENT_META_FORBIDDEN_GROWTH 的具體觸發形狀完全
##    未被 design.md／tasks.md 釘死（兩者只有敘述性文字「不得宣告永久基礎生命/攻防提升、
##    商店免費刷新、固定起始人口」，未給欄位/型別層級的具體判準）。現行 schema 沒有任何
##    「永久修改 UnitDef.base_stats」的 operation 型別（ModifyStatOperationDef 是
##    BattleOperationDef，只在戰鬥內臨時生效、duration_ticks 上限 1800 tick，戰鬥結束即
##    重置，不影響 UnitDef 本身），故三個禁項在目前 schema 下不可能透過「正常」的
##    unlocked_content_refs/modifier_refs 消費機制真正產生永久基礎戰力提升——這條規則本質
##    上是內容著作期的「防禦性」結構檢查，攔阻明顯不合理/會被誤用的引用形狀，而非攔阻某個
##    目前真的可執行的 exploit。本檔採用以下三個具體、可機械判別、且完全不影響
##    SyntheticContentFixture.build_valid() 既有合規基準的觸發形狀（逐一在對應測試前重述）：
##      a. 免費刷新：unlocked_content_refs／modifier_refs 中任一 id 解析為 EconomyConfigDef
##         且其 reroll_cost <= 0（直接對應設計文字括號內「reroll_cost 歸零」的字面判準）。
##      b. 固定起始人口：unlocked_content_refs／modifier_refs 中任一 id 解析為 EffectDef，
##         其 run_operations 含至少一個 PopulationSourceOperationDef（現有 schema 中唯一
##         代表「授予起始人口」語意的 operation 型別）。注意：EffectDef.run_operations 在
##         _validate_operations 既有規則下本就一律 allow_capacity=false（不論是否被 unlock
##         引用），所以這個形狀在現行驗證器下已經會產生 CONTENT_RUN_INTENT_FORBIDDEN——本
##         規則的新增價值是在「被 unlock 引用」這個更精確的情境下額外標記具名的
##         CONTENT_META_FORBIDDEN_GROWTH，兩個 issue 共存於同一份 report 是預期行為，本檔
##         只斷言 CONTENT_META_FORBIDDEN_GROWTH 存在，不斷言它是唯一 issue。
##      c. 永久基礎生命/攻防提升：modifier_refs（不含 unlocked_content_refs——後者本就是
##         「解鎖新棋子」的正常管道，SyntheticContentFixture 的 unlock.base_profile 即以此
##         方式合法引用 UnitDef，不可誤傷）中任一 id 直接解析為 UnitDef。modifier_refs 的
##         語意是「效果/修飾器引用」（challenge 鏈既有用法皆指向 EffectDef），讓它直接指向
##         一個 UnitDef 沒有任何合理解讀，唯一合理的解讀是內容作者試圖把「這個棋子」當成
##         可被永久修飾的目標——這是本檔對「宣告永久基礎生命/攻防提升」給出的具體、可機械
##         判別的形狀。
##    以上三點是測試作者（本檔）在 design 留白處的裁決，不是 design 原文逐字規定；實作代理
##    若認為應有不同的具體判準，屬測試爭議範疇，需與本檔假設對齊或回報調整。
## ================================================================================================

const _HEALTH_INDEX := 0
const _ATTACK_INDEX := 1
const _ARMOR_INDEX := 2
const _MAGIC_RESIST_INDEX := 3


func test_compiled_unit_stats_unchanged_before_and_after_unlock_purchase() -> void:
	var fixture := SyntheticContentFixture.build_valid()
	var registry := ContentRegistryService.new()
	add_child_autofree(registry)
	var installed := registry.install_validated(fixture, "fixture.meta_growth.stats", [&"pack.core"])
	assert_true(installed.ok, "SyntheticContentFixture.build_valid() 必須通過安裝")
	if not installed.ok:
		return
	var digest := installed.handle.manifest_digest
	var ref := ContentRef.new(digest, &"unit.player_00")
	var before_result := registry.resolve(ref)
	assert_true(before_result.ok)
	if not before_result.ok:
		return
	var before_stats := _read_base_stats(before_result.value)

	var profile := PurchaseUnlockTestFixture.base_profile(100, [])
	var unlock_def := PurchaseUnlockTestFixture.make_unlock_def(
		&"unlock.test_new_unit_access", 10, [], [&"unit.player_05"]
	)
	var purchase_result := PurchaseUnlockCommand.new(unlock_def).apply_to(profile)
	assert_true(purchase_result.ok, "解鎖購買必須成功，才談得上比較「解鎖前後」")
	if not purchase_result.ok:
		return

	var after_result := registry.resolve(ref)
	assert_true(after_result.ok)
	if not after_result.ok:
		return
	var after_stats := _read_base_stats(after_result.value)
	assert_eq(
		after_stats, before_stats,
		"unit.player_00 的基礎生命/攻擊/護甲/魔抗必須在解鎖動作前後逐欄相等"
	)


func test_unlock_referencing_zero_reroll_cost_economy_config_is_forbidden_growth() -> void:
	var input := SyntheticContentFixture.build_valid()
	var base_economy := _find(input, &"economy.default") as EconomyConfigDef
	assert_not_null(base_economy)
	if base_economy == null:
		return
	var free_reroll_economy := base_economy.duplicate(true) as EconomyConfigDef
	free_reroll_economy.id = &"economy.test_free_reroll"
	free_reroll_economy.reroll_cost = 0
	input.definitions.append(free_reroll_economy)
	var unlock := UnlockDef.new()
	unlock.id = &"unlock.test_forbidden_free_reroll"
	unlock.display_name_key = &"loc.unlock_test_forbidden_free_reroll"
	unlock.unlock_kind = &"purchase"
	unlock.unlocked_content_refs = [&"economy.test_free_reroll"]
	input.definitions.append(unlock)

	var report := ContentValidator.new().validate(input)

	assert_true(
		_has_issue(report, &"CONTENT_META_FORBIDDEN_GROWTH"),
		"reroll_cost=0 的 EconomyConfigDef 被 unlock 引用必須被拒絕: %s" % _issue_text(report)
	)


func test_unlock_referencing_population_source_effect_is_forbidden_growth() -> void:
	var input := SyntheticContentFixture.build_valid()
	var effect := EffectDef.new()
	effect.id = &"effect.test_forbidden_population"
	effect.display_name_key = &"loc.effect_test_forbidden_population"
	effect.content_role = &"general"
	effect.trigger = &"battle_start"
	effect.stacking = &"replace"
	effect.max_stacks = 1
	effect.duration_ticks = 1
	var population := PopulationSourceOperationDef.new()
	population.operation_index = 0
	population.source_id = &"source.test_forbidden_population"
	population.amount = 1
	effect.run_operations = [population]
	input.definitions.append(effect)
	var unlock := UnlockDef.new()
	unlock.id = &"unlock.test_forbidden_population"
	unlock.display_name_key = &"loc.unlock_test_forbidden_population"
	unlock.unlock_kind = &"purchase"
	unlock.modifier_refs = [&"effect.test_forbidden_population"]
	input.definitions.append(unlock)

	var report := ContentValidator.new().validate(input)

	assert_true(
		_has_issue(report, &"CONTENT_META_FORBIDDEN_GROWTH"),
		"引用 PopulationSourceOperationDef 效果的 unlock 必須被拒絕: %s" % _issue_text(report)
	)


func test_unlock_modifier_refs_pointing_directly_to_unit_def_is_forbidden_growth() -> void:
	var input := SyntheticContentFixture.build_valid()
	var unlock := UnlockDef.new()
	unlock.id = &"unlock.test_forbidden_stat_boost"
	unlock.display_name_key = &"loc.unlock_test_forbidden_stat_boost"
	unlock.unlock_kind = &"purchase"
	unlock.modifier_refs = [&"unit.player_00"]
	input.definitions.append(unlock)

	var report := ContentValidator.new().validate(input)

	assert_true(
		_has_issue(report, &"CONTENT_META_FORBIDDEN_GROWTH"),
		"modifier_refs 直接指向 UnitDef 必須被拒絕: %s" % _issue_text(report)
	)


func test_unmodified_baseline_has_no_forbidden_growth_issue() -> void:
	var input := SyntheticContentFixture.build_valid()

	var report := ContentValidator.new().validate(input)

	assert_true(report.valid, _issue_text(report))
	assert_false(_has_issue(report, &"CONTENT_META_FORBIDDEN_GROWTH"))


func _read_base_stats(view: ContentDefinitionView) -> Array:
	var base_stats := view.payload.children[5]
	return [
		base_stats.children[_HEALTH_INDEX].int_value,
		base_stats.children[_ATTACK_INDEX].int_value,
		base_stats.children[_ARMOR_INDEX].int_value,
		base_stats.children[_MAGIC_RESIST_INDEX].int_value,
	]


func _find(input: ContentValidationInput, content_id: StringName) -> ContentDefinition:
	for definition: ContentDefinition in input.definitions:
		if definition.id == content_id:
			return definition
	return null


func _has_issue(report: ContentValidationReport, code: StringName) -> bool:
	for issue: ContentValidationIssue in report.issues:
		if issue.code == code:
			return true
	return false


func _issue_text(report: ContentValidationReport) -> String:
	var values: Array[String] = []
	for issue: ContentValidationIssue in report.issues:
		values.append("%s:%s:%s" % [issue.code, issue.source_id, issue.field_path])
	return ", ".join(values)
