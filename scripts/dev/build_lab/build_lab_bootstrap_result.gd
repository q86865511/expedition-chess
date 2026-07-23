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
var player_unit_ids: Array[StringName] = []
var equipment_ids: Array[StringName] = []
var item_component_ids: Array[StringName] = []
var battle_relic_ids: Array[StringName] = []
var run_relic_ids: Array[StringName] = []
var map_node_ids: Array[StringName] = []
var reward_table_ids: Array[StringName] = []
var dismantle_consumable_id: StringName = &""

static func failure(message: String) -> BuildLabBootstrapResult:
	var result := BuildLabBootstrapResult.new()
	result.ok = false
	result.error_message = message
	return result

static func success() -> BuildLabBootstrapResult:
	var result := BuildLabBootstrapResult.new()
	result.ok = true
	return result
