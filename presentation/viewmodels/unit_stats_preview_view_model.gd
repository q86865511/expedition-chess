class_name UnitStatsPreviewViewModel
extends RefCounted

## T01 / IRH-REQ-016（specs/in-run-hud/design.md §7）-- 備戰期單位屬性預覽 ViewModel：
## 純預覽，讀端與實戰同源 -- 直接複用 BattleSetupSourceCompiler 對「RunController 已提交
## roster snapshot ＋ pinned BattleRuleCatalog」的星級縮放路徑，不另生一套預覽算法。
## 只持 clone/snapshot，不跨操作快取可變 domain 物件（HANDOFF §2 第 1、7 條）。
##
## 範圍限定：回傳的是套用星級後、進入戰鬥前的屬性，等同 BattleSimulation 初始化寫進
## BattleEntityState 的 base 值。裝備、羈絆與遺物在實戰是經 effect 解算成 BattleTimedState
## 後由 BattleCombatMath 疊加的，其生效與否取決於 effect 的條件與觸發時機；本 ViewModel
## 不重現 effect 解算（§10.3 禁止在呈現層複製公式），只回報配戴中的裝備 instance id
## 供面板列出來源。

var _controller: RunController
var _catalog: BattleRuleCatalog
var _compiler: BattleSetupSourceCompiler


func _init(
	controller: RunController,
	catalog: BattleRuleCatalog,
	compiler: BattleSetupSourceCompiler = null
) -> void:
	_controller = controller
	_catalog = catalog.deep_clone() if catalog != null else null
	_compiler = compiler if compiler != null else BattleSetupSourceCompiler.new()


## 指定單位（棋盤或板凳皆可）的屬性預覽；找不到該 instance id 時回傳 null
## （依 repo 的 try_ 慣例明示可空，呼叫端必須處理）。
func try_stats_for(unit_instance_id: String) -> UnitStatsPreviewSnapshot:
	var instance := _find_instance(unit_instance_id)
	if instance == null:
		return null
	return _compiler.try_compile_unit_stats(instance, _catalog)


## 目前已提交 roster 全部單位的屬性預覽，依 instance id 排序以保持呈現順序決定性。
func all_stats() -> Array[UnitStatsPreviewSnapshot]:
	var result: Array[UnitStatsPreviewSnapshot] = []
	var roster := _controller.roster_snapshot()
	if roster == null:
		return result
	var instances := roster.unit_instances.duplicate()
	instances.sort_custom(_instance_before)
	for instance: UnitInstance in instances:
		if instance == null:
			continue
		var preview := _compiler.try_compile_unit_stats(instance, _catalog)
		if preview != null:
			result.append(preview)
	return result


func _find_instance(unit_instance_id: String) -> UnitInstance:
	if unit_instance_id.is_empty():
		return null
	var roster := _controller.roster_snapshot()
	if roster == null:
		return null
	for instance: UnitInstance in roster.unit_instances:
		if instance != null and instance.instance_id == unit_instance_id:
			return instance
	return null


func _instance_before(left: UnitInstance, right: UnitInstance) -> bool:
	if left == null:
		return false
	if right == null:
		return true
	return left.instance_id < right.instance_id
