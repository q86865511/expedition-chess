class_name BuildLabBootstrapResult
extends RefCounted

## T11 (specs/build-systems/design.md §8) -- BuildLabContentBootstrap 的產出:
## 一次真正 ContentRegistryService 雙 pack 安裝＋四個 catalog/table builder 的
## 結果快照,連同 BuildLabSession 組建初始 RunState 所需的內容 id 清單。

var ok: bool = false
var error_message: String = ""

var registry: ContentRegistryService
var manifest_digest: String = ""
var content_version: String = ""
var content_snapshot: ContentSnapshotState
## 安裝時就已知的完整 pinned receipt(BuildLabSession 以
## ContentRegistryReceiptAdapter 正常路徑消費)。
var receipt: PinnedCatalogBuildReceipt
var battle_catalog: BattleRuleCatalog
var forge_table: ForgeRecipeTable
var relic_table: RunRelicTable
var consumable_rules: ConsumableRuleTable
var economy_catalog: EconomyExpeditionCatalog

var economy_config_id: StringName
var unit_ids: Array[StringName] = []
var player_unit_ids: Array[StringName] = []
var equipment_ids: Array[StringName] = []
var item_component_ids: Array[StringName] = []
var battle_relic_ids: Array[StringName] = []
var run_relic_ids: Array[StringName] = []
var map_node_ids: Array[StringName] = []
var reward_table_ids: Array[StringName] = []
var dismantle_consumable_id: StringName = &""
## S5 T11: AppRoot composition root 額外需要的內容面向——遭遇（戰鬥節點編譯的 root，
## build lab 自己不進節點故原本未收集）與指揮官 id 清單。
##
## wave5 修正 B4（REQ-DATA-008）：此處**只**交出 id 這類純值，不再攜帶 CommanderDef 原件。
## 指揮官的 starting_pack／population_bonus／passive_effect_refs 由 CommanderContentReader
## 從 registry 的 canonical view 解出（app/content/commander_content_reader.gd），consumer
## 不再取得 authoring 定義的共享實例。
var encounter_ids: Array[StringName] = []
var commander_ids: Array[StringName] = []
## 新 profile 的起始解鎖集合（unlock_kind == base_profile 的 unlocked_content_refs，
## 排序去重）。AppRoot 首次啟動建 profile 時的唯一來源——起始內容是內容作者的決定，
## 不由 app 層自行編造（wave5 修正 A2）。
var base_profile_unlocked_content_ids: Array[StringName] = []
var meta_reward_table_id: StringName = &""
## 由 MetaRewardTableReader 從 pinned canonical payload 重建的 consumer-owned clone；
## 不得放入 authoring `.tres` 的共享 Resource。
var meta_reward_table: MetaRewardTableDef

static func failure(message: String) -> BuildLabBootstrapResult:
	var result := BuildLabBootstrapResult.new()
	result.ok = false
	result.error_message = message
	return result

static func success() -> BuildLabBootstrapResult:
	var result := BuildLabBootstrapResult.new()
	result.ok = true
	return result
