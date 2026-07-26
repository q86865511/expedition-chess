class_name RunCompositionSupport
extends RefCounted

## T11 (specs/meta-progression/design.md §4.4、§6.3 軌 A)：composition root 組裝一個
## 可玩 run 時，兩個「內容/狀態 → 命令建構參數」的決定性換算，與同目錄的
## RunSessionFactory／RunSaveRootFactory 同性質（production builder，非 domain 服務）。
##
## 兩者都是既有留白的正式收口點，不新增語意：
##
## 缺口 1（軌 A 在正式流程不生效）：BattleRuleCatalogBuilder 早已能解碼 unlock 類內容並
## 遞移 pin 其 battle_operations 非空的效果（battle_rule_catalog_builder.gd:414-441），
## 但沒有任何呼叫端把 challenge unlock 鏈餵給它的 required_ids——challenge 詞綴只透過
## unlock.slice_challenge_N 的 modifier_refs 可達，不在 unit/encounter 的遞移閉包內，
## 少了這一步 challenge>=1 的戰鬥節點會以 EncounterCompiler.RULE_MISSING 進不去。
##
## 缺口 2（指揮官 population source 未注入）：commit_board_layout_command.gd:71-76 明文
## 「extra sources are INJECTED by whoever constructs the command…Default is empty」並
## 指名 RunBootstrapService.try_commander_population_source() 為來源。本類別只把那個
## 「可能為 null」的既有靜態工具正規化成 CommitBoardLayoutCommand 期待的 Array 形狀，
## 不重新定義來源語意。

## challenge unlock 鏈的 id 命名慣例，與 challenge_affix_resolver.gd:33／
## run_modifier_table_builder.gd:90 完全相同（此處不重複硬寫字串以外的規則）。
const CHALLENGE_UNLOCK_ID_FORMAT: String = "unlock.slice_challenge_%d"


## base_ids 之後依序附加 unlock.slice_challenge_1..challenge_level，供
## BattleRuleCatalogBuilder.build(registry, digest, required_ids) 使用。
## base_ids 的相對順序不動、不去重（呼叫端負責提供已去重的 base_ids）；
## challenge_level <= 0 時回傳 base_ids 的淺層複本——絕不回傳同一個 Array 物件，
## 免得呼叫端誤改動呼叫者的資料。
static func required_battle_ids(
	base_ids: Array[StringName],
	challenge_level: int
) -> Array[StringName]:
	var required: Array[StringName] = []
	required.assign(base_ids)
	for level: int in range(1, challenge_level + 1):
		required.append(StringName(CHALLENGE_UNLOCK_ID_FORMAT % level))
	return required


## 指揮官 population_bonus 的 PopulationSourceSnapshot 陣列：無加成（<=0）＝無來源＝
## 空陣列（PopulationCalculator 只接受 amount > 0 的來源），否則恰一筆 commander 來源。
static func population_sources(
	commander_id: StringName,
	population_bonus: int
) -> Array[PopulationSourceSnapshot]:
	var sources: Array[PopulationSourceSnapshot] = []
	var source := RunBootstrapService.try_commander_population_source(
		commander_id, population_bonus
	)
	if source != null:
		sources.append(source)
	return sources
