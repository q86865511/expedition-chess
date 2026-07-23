class_name InventoryViewModel
extends RefCounted

## T10 / S4-AC-013 (specs/build-systems/design.md §8) -- 物品庫/棋子裝備/
## overflow tray ViewModel:讀 RosterState 的 items/棋裝備/16 格/overflow
## tray 快照,寫端一律經 RunController.dispatch() 分派既有
## EquipItemCommand／DismantleEquipmentCommand／ResolveOverflowCommand
## (design §8)。resolve_overflow() 為薄轉發 -- 呼叫端以 ResolveOverflowCommand
## 既有三個靜態工廠(.equip()/.forge()/.abandon())建構後傳入,本 ViewModel
## 不重新暴露那三個工廠(design §8 只要求 InventoryViewModel 寫欄位把
## ResolveOverflowCommand 送進 RunController.dispatch(),未要求重新設計其已
## 固定的建構介面)。

var _controller: RunController

func _init(controller: RunController) -> void:
	_controller = controller

## inventory_item_instance_ids 中的物品快照(不含 overflow tray、已裝備物品)。
func inventory_items() -> Array[ItemInstanceState]:
	var roster := _controller.roster_snapshot()
	return _items_for(roster, roster.inventory_item_instance_ids)

## 指定棋子目前裝備(equipment_instance_ids)的物品快照。
func equipped_items(unit_instance_id: String) -> Array[ItemInstanceState]:
	var roster := _controller.roster_snapshot()
	var unit := _find_unit(roster, unit_instance_id)
	if unit == null:
		return []
	return _items_for(roster, unit.equipment_instance_ids)

## 目前仍待處置(未清空)的 overflow tray 物品快照。
func overflow_items() -> Array[ItemInstanceState]:
	var roster := _controller.roster_snapshot()
	return _items_for(roster, roster.pending_item_overflow)

## 分派真正的 EquipItemCommand 經 RunController.dispatch()。
func equip(
	item_instance_id: String,
	unit_instance_id: String,
	catalog: BattleRuleCatalog
) -> CommandResult:
	var command := EquipItemCommand.new(unit_instance_id, item_instance_id, catalog)
	return _controller.dispatch(command)

## 分派真正的 DismantleEquipmentCommand 經 RunController.dispatch()。
func dismantle(
	equipment_item_instance_id: String,
	consumable_item_instance_id: String,
	consumable_rules: ConsumableRuleTable
) -> CommandResult:
	var command := DismantleEquipmentCommand.new(
		equipment_item_instance_id, consumable_item_instance_id, consumable_rules
	)
	return _controller.dispatch(command)

## 薄轉發:呼叫端建構的 ResolveOverflowCommand 原樣送進 RunController.dispatch()。
func resolve_overflow(command: ResolveOverflowCommand) -> CommandResult:
	return _controller.dispatch(command)

func _items_for(
	roster: RosterState,
	item_instance_ids: Array[String]
) -> Array[ItemInstanceState]:
	var result: Array[ItemInstanceState] = []
	for item_instance_id: String in item_instance_ids:
		var item := _find_item(roster, item_instance_id)
		if item != null:
			result.append(item)
	return result

func _find_item(roster: RosterState, item_instance_id: String) -> ItemInstanceState:
	for item: ItemInstanceState in roster.item_instances:
		if item.instance_id == item_instance_id:
			return item
	return null

func _find_unit(roster: RosterState, unit_instance_id: String) -> UnitInstance:
	for unit: UnitInstance in roster.unit_instances:
		if unit.instance_id == unit_instance_id:
			return unit
	return null
