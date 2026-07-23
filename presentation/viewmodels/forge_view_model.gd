class_name ForgeViewModel
extends RefCounted

## T10 / S4-AC-013 (specs/build-systems/design.md §8) -- 鍛造介面 ViewModel:
## 讀 inventory 零件清單與 ForgeRecipeTable 成品/效果/限制預覽,寫端一律經
## RunController.dispatch(ForgeEquipmentCommand)(design §8),不呼叫
## apply_to() 直接繞過交易。只持 clone/snapshot,不跨操作快取可變 domain
## 物件。

var _controller: RunController
var _forge_table: ForgeRecipeTable

func _init(controller: RunController, forge_table: ForgeRecipeTable) -> void:
	_controller = controller
	_forge_table = forge_table.deep_clone() if forge_table != null else null

## 目前 inventory_item_instance_ids 中的零件/物品快照(不含板凳、已裝備、
## overflow tray 中的物品)。
func inventory_components() -> Array[ItemInstanceState]:
	var roster := _controller.roster_snapshot()
	var result: Array[ItemInstanceState] = []
	for item_instance_id: String in roster.inventory_item_instance_ids:
		var item := _find_item(roster, item_instance_id)
		if item != null:
			result.append(item)
	return result

## 含有指定零件 def_id 的所有已註冊配方(自配＋交叉配方皆列出)。
func recipe_preview(component_id: StringName) -> Array[ForgeRecipeRule]:
	return _forge_table.recipes_containing(component_id)

## 分派真正的 ForgeEquipmentCommand 經 RunController.dispatch(),使拒絕/
## commit 失敗時 canonical inventory 一併維持不變。
func forge(component_instance_id_a: String, component_instance_id_b: String) -> CommandResult:
	var command := ForgeEquipmentCommand.new(
		component_instance_id_a, component_instance_id_b, _forge_table
	)
	return _controller.dispatch(command)

func _find_item(roster: RosterState, item_instance_id: String) -> ItemInstanceState:
	for item: ItemInstanceState in roster.item_instances:
		if item.instance_id == item_instance_id:
			return item
	return null
