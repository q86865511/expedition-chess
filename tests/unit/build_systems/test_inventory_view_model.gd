extends GutTest

## T10 / S4-AC-013 (specs/build-systems/design.md §8, HANDOFF.md §2) --
## InventoryViewModel (presentation/viewmodels/inventory_view_model.gd,
## currently does not exist).
##
## Expected contract (test-author decision -- see
## tests/fixtures/build_systems/view_model_test_fixture.gd header):
##   class_name InventoryViewModel extends RefCounted
##   func _init(controller: RunController) -> void
##   func inventory_items() -> Array[ItemInstanceState]
##   func equipped_items(unit_instance_id: String) -> Array[ItemInstanceState]
##   func overflow_items() -> Array[ItemInstanceState]
##   func equip(item_instance_id: String, unit_instance_id: String, catalog: BattleRuleCatalog) -> CommandResult
##   func dismantle(equipment_item_instance_id: String, consumable_item_instance_id: String, consumable_rules: ConsumableRuleTable) -> CommandResult
##   func resolve_overflow(command: ResolveOverflowCommand) -> CommandResult
## `equip()`/`dismantle()` must dispatch the real EquipItemCommand /
## DismantleEquipmentCommand through `RunController.dispatch()` (design §8:
## "寫端一律經 command"). `resolve_overflow()` is a thin passthrough that
## dispatches a caller-built ResolveOverflowCommand (T05,
## domain/run/controller/commands/resolve_overflow_command.gd) the same way --
## it does not re-expose the command's three static factories
## (.equip()/.forge()/.abandon()) as separate ViewModel methods, since design
## §8 only requires the InventoryViewModel write column to route
## ResolveOverflowCommand through `RunController.dispatch()`, not to redesign
## its already-fixed construction surface.
##
## Reuses EquipDismantleTestFixture (tests/fixtures/build_items/) verbatim.
## Rejection-path tests deliberately use def_ids that are NOT registered in
## EquipDismantleTestFixture.equipment_receipt()'s active_entry_ids (e.g. an
## arbitrary "consumable.non_dismantle") -- a rejected command's apply_to()
## fails before RunController's commit/save stage is ever reached, so no
## SaveJsonCodec content-id migration/tombstone gating applies (see
## services/save/save_json_codec.gd's _migrate_required_id, only exercised by
## SaveRepository.save()'s internal readback decode on a *successful* commit).

func test_inventory_items_reflects_roster_snapshot_and_is_isolated_from_domain() -> void:
	var run := EquipDismantleTestFixture.base_run(1)
	var item_a := EquipDismantleTestFixture.item_id(1)
	var item_b := EquipDismantleTestFixture.item_id(2)
	run.roster_state.item_instances = [
		EquipDismantleTestFixture.item(item_a, &"equipment.plain_a"),
		EquipDismantleTestFixture.item(item_b, &"equipment.plain_b"),
	]
	run.roster_state.inventory_item_instance_ids = [item_a, item_b]
	var controller := _controller_for(run)
	var view_model := InventoryViewModel.new(controller)

	var items := view_model.inventory_items()
	assert_eq(items.size(), 2)
	var ids: Array = []
	for item: ItemInstanceState in items:
		ids.append(item.instance_id)
	assert_true(ids.has(item_a))
	assert_true(ids.has(item_b))

	# 契約測試（design §8）：改動回傳陣列中的物件不得影響 domain 或之後的讀取。
	items[0].bound_unit_instance_id = OptionalStringValue.new("u_injected")
	var again := view_model.inventory_items()
	for item: ItemInstanceState in again:
		assert_null(item.bound_unit_instance_id)
	var roster_after := controller.roster_snapshot()
	for item: ItemInstanceState in roster_after.item_instances:
		assert_null(item.bound_unit_instance_id)

func test_equipped_items_returns_only_items_bound_to_the_given_unit() -> void:
	var run := EquipDismantleTestFixture.base_run(2)
	var unit_a := EquipDismantleTestFixture.unit_id(1)
	var unit_b := EquipDismantleTestFixture.unit_id(2)
	var item_on_a := EquipDismantleTestFixture.item_id(1)
	var item_on_b := EquipDismantleTestFixture.item_id(2)
	run.roster_state.item_instances = [
		EquipDismantleTestFixture.item(item_on_a, &"equipment.plain_a", unit_a),
		EquipDismantleTestFixture.item(item_on_b, &"equipment.plain_b", unit_b),
	]
	EquipDismantleTestFixture.find_unit(run, unit_a).equipment_instance_ids = [item_on_a]
	EquipDismantleTestFixture.find_unit(run, unit_b).equipment_instance_ids = [item_on_b]
	var controller := _controller_for(run)
	var view_model := InventoryViewModel.new(controller)

	var equipped_a := view_model.equipped_items(unit_a)
	assert_eq(equipped_a.size(), 1)
	assert_eq(equipped_a[0].instance_id, item_on_a)

func test_overflow_items_returns_items_in_pending_item_overflow() -> void:
	var run := EquipDismantleTestFixture.base_run(1)
	var overflow_id := EquipDismantleTestFixture.item_id(1)
	run.roster_state.item_instances = [
		EquipDismantleTestFixture.item(overflow_id, &"equipment.plain_a"),
	]
	run.roster_state.pending_item_overflow = [overflow_id]
	var controller := _controller_for(run)
	var view_model := InventoryViewModel.new(controller)

	var overflow := view_model.overflow_items()
	assert_eq(overflow.size(), 1)
	assert_eq(overflow[0].instance_id, overflow_id)
	# 尚在 overflow 中的物品不應同時被視為在 inventory 中。
	assert_eq(view_model.inventory_items().size(), 0)

func test_equip_success_dispatches_command_and_removes_item_from_inventory_snapshot() -> void:
	var run := EquipDismantleTestFixture.base_run(1)
	var catalog := EquipDismantleTestFixture.battle_catalog()
	var target_id := EquipDismantleTestFixture.unit_id(1)
	var item_id := EquipDismantleTestFixture.item_id(1)
	run.roster_state.item_instances = [
		EquipDismantleTestFixture.item(item_id, &"equipment.plain_a"),
	]
	run.roster_state.inventory_item_instance_ids = [item_id]
	var controller := _controller_for(run)
	var view_model := InventoryViewModel.new(controller)

	var result := view_model.equip(item_id, target_id, catalog)
	assert_true(result.ok, ViewModelTestFixture.command_error_source_code(result))
	if not result.ok:
		return
	assert_eq(result.view_state.roster.inventory_item_instance_ids.size(), 0)
	var equipped := view_model.equipped_items(target_id)
	assert_eq(equipped.size(), 1)
	assert_eq(equipped[0].instance_id, item_id)

func test_equip_rejects_component_as_equipment_with_named_error() -> void:
	var run := EquipDismantleTestFixture.base_run(1)
	var catalog := EquipDismantleTestFixture.battle_catalog()
	var target_id := EquipDismantleTestFixture.unit_id(1)
	var component_id := EquipDismantleTestFixture.item_id(1)
	run.roster_state.item_instances = [
		EquipDismantleTestFixture.item(component_id, &"item_component.gem"),
	]
	run.roster_state.inventory_item_instance_ids = [component_id]
	var controller := _controller_for(run)
	var view_model := InventoryViewModel.new(controller)

	var result := view_model.equip(component_id, target_id, catalog)
	assert_false(result.ok)
	assert_eq(ViewModelTestFixture.command_error_source_code(result), "EQUIP_ITEM_NOT_EQUIPMENT")
	assert_eq(view_model.inventory_items().size(), 1, "拒絕時 inventory 應維持不變")

func test_dismantle_rejects_wrong_consumable_kind_with_named_error() -> void:
	var run := EquipDismantleTestFixture.base_run(1)
	var target_unit_id := EquipDismantleTestFixture.unit_id(1)
	var equipment_id := EquipDismantleTestFixture.item_id(1)
	var wrong_kind_id := EquipDismantleTestFixture.item_id(2)
	run.roster_state.item_instances = [
		EquipDismantleTestFixture.item(equipment_id, &"equipment.plain_a", target_unit_id),
		EquipDismantleTestFixture.item(wrong_kind_id, &"consumable.non_dismantle"),
	]
	run.roster_state.inventory_item_instance_ids = [wrong_kind_id]
	EquipDismantleTestFixture.find_unit(run, target_unit_id).equipment_instance_ids = [equipment_id]
	var controller := _controller_for(run)
	var view_model := InventoryViewModel.new(controller)

	var result := view_model.dismantle(
		equipment_id, wrong_kind_id, EquipDismantleTestFixture.consumable_rules()
	)
	assert_false(result.ok)
	assert_eq(
		ViewModelTestFixture.command_error_source_code(result),
		"DISMANTLE_EQUIPMENT_CONSUMABLE_KIND"
	)
	# 拒絕時裝備仍應維持綁定狀態、消耗品仍在庫存中。
	assert_eq(view_model.equipped_items(target_unit_id).size(), 1)
	assert_eq(view_model.inventory_items().size(), 1)

func test_resolve_overflow_equip_moves_item_from_tray_to_equipped_items() -> void:
	var run := EquipDismantleTestFixture.base_run(1)
	var catalog := EquipDismantleTestFixture.battle_catalog()
	var target_id := EquipDismantleTestFixture.unit_id(1)
	var overflow_id := EquipDismantleTestFixture.item_id(1)
	run.roster_state.item_instances = [
		EquipDismantleTestFixture.item(overflow_id, &"equipment.plain_a"),
	]
	run.roster_state.pending_item_overflow = [overflow_id]
	var controller := _controller_for(run)
	var view_model := InventoryViewModel.new(controller)

	var command := ResolveOverflowCommand.equip(overflow_id, target_id, catalog)
	var result := view_model.resolve_overflow(command)
	assert_true(result.ok, ViewModelTestFixture.command_error_source_code(result))
	if not result.ok:
		return
	assert_eq(view_model.overflow_items().size(), 0)
	var equipped := view_model.equipped_items(target_id)
	assert_eq(equipped.size(), 1)
	assert_eq(equipped[0].instance_id, overflow_id)

func test_resolve_overflow_rejects_item_not_in_tray_with_named_error() -> void:
	var run := EquipDismantleTestFixture.base_run(1)
	var item_id := EquipDismantleTestFixture.item_id(1)
	run.roster_state.item_instances = [
		EquipDismantleTestFixture.item(item_id, &"equipment.plain_a"),
	]
	# 物品在 inventory、不在 tray 中 -- 任何 disposition 皆不可處置非 tray 物品。
	run.roster_state.inventory_item_instance_ids = [item_id]
	var controller := _controller_for(run)
	var view_model := InventoryViewModel.new(controller)

	var command := ResolveOverflowCommand.abandon(item_id)
	var result := view_model.resolve_overflow(command)
	assert_false(result.ok)
	assert_eq(
		ViewModelTestFixture.command_error_source_code(result),
		"RESOLVE_OVERFLOW_ITEM_NOT_IN_TRAY"
	)
	assert_eq(view_model.inventory_items().size(), 1, "拒絕時 inventory 應維持不變")

func _controller_for(run: RunState) -> RunController:
	var storage := FakeSaveStorage.new()
	var repository := EquipDismantleTestFixture.repository_for(storage)
	add_child_autofree(repository)
	var battle_catalog := EquipDismantleTestFixture.battle_catalog()
	return ViewModelTestFixture.controller_for(run, battle_catalog, repository)
