extends GutTest

## T04 / S4-AC-006 (EquipItemCommand): 3 件上限、unique_group 衝突、裝零件皆拒,
## 且拒絕時狀態不變、回具名 error;成功路徑裝備搬移全程恰一實例(無複製).
##
## Contract under test (test-author decision, see
## tests/fixtures/build_items/equip_dismantle_test_fixture.gd header for why):
##   EquipItemCommand.new(unit_instance_id: String, item_instance_id: String,
##     catalog: BattleRuleCatalog) -> RunCommand
##   .apply_to(draft: RunState) -> CommandApplyResult
## Named error codes are carried as the existing "source_code" diagnostic
## string (see commit_board_layout_command.gd's `_rejected` helper), read via
## EquipDismantleTestFixture.error_source_code().

func test_equip_moves_exactly_one_item_instance_from_inventory_to_unit() -> void:
	var run := EquipDismantleTestFixture.base_run(1)
	var catalog := EquipDismantleTestFixture.battle_catalog()
	var target_id := EquipDismantleTestFixture.unit_id(1)
	var item_id := EquipDismantleTestFixture.item_id(1)
	var equip_item := EquipDismantleTestFixture.item(item_id, &"equipment.plain_a")
	run.roster_state.item_instances = [equip_item]
	run.roster_state.inventory_item_instance_ids = [item_id]
	var before_item_count := run.roster_state.item_instances.size()

	var command := EquipItemCommand.new(target_id, item_id, catalog)
	assert_true(command.is_concrete())
	var result := command.apply_to(run)
	assert_true(result.ok, EquipDismantleTestFixture.error_source_code(result))
	if not result.ok: return

	assert_eq(result.draft.roster_state.item_instances.size(), before_item_count)
	var equipped_item := EquipDismantleTestFixture.find_item(result.draft, item_id)
	assert_not_null(equipped_item)
	assert_not_null(equipped_item.bound_unit_instance_id)
	assert_eq(equipped_item.bound_unit_instance_id.value, target_id)
	var unit := EquipDismantleTestFixture.find_unit(result.draft, target_id)
	assert_eq(unit.equipment_instance_ids, [item_id])
	assert_false(result.draft.roster_state.inventory_item_instance_ids.has(item_id))

func test_equip_rejects_fourth_item_and_leaves_state_unchanged() -> void:
	var run := EquipDismantleTestFixture.base_run(1)
	var catalog := EquipDismantleTestFixture.battle_catalog()
	var target_id := EquipDismantleTestFixture.unit_id(1)
	var equipped_ids: Array[String] = [
		EquipDismantleTestFixture.item_id(1),
		EquipDismantleTestFixture.item_id(2),
		EquipDismantleTestFixture.item_id(3),
	]
	var equipped_defs: Array[StringName] = [
		&"equipment.plain_a", &"equipment.plain_b", &"equipment.plain_c",
	]
	var items: Array[ItemInstanceState] = []
	for index: int in range(3):
		items.append(EquipDismantleTestFixture.item(
			equipped_ids[index], equipped_defs[index], target_id
		))
	var fourth_id := EquipDismantleTestFixture.item_id(4)
	items.append(EquipDismantleTestFixture.item(fourth_id, &"equipment.plain_d"))
	run.roster_state.item_instances = items
	run.roster_state.inventory_item_instance_ids = [fourth_id]
	var unit := EquipDismantleTestFixture.find_unit(run, target_id)
	unit.equipment_instance_ids = equipped_ids.duplicate()
	var before_equipment := unit.equipment_instance_ids.duplicate()
	var before_item_count := run.roster_state.item_instances.size()

	var result := EquipItemCommand.new(target_id, fourth_id, catalog).apply_to(run)
	assert_false(result.ok)
	assert_eq(EquipDismantleTestFixture.error_source_code(result), "EQUIP_ITEM_SLOTS_FULL")
	# state unchanged: original draft object must be untouched by the rejected command.
	assert_eq(unit.equipment_instance_ids, before_equipment)
	assert_eq(run.roster_state.item_instances.size(), before_item_count)
	var fourth_item := EquipDismantleTestFixture.find_item(run, fourth_id)
	assert_null(fourth_item.bound_unit_instance_id)
	assert_true(run.roster_state.inventory_item_instance_ids.has(fourth_id))

func test_equip_rejects_unique_group_conflict_and_leaves_state_unchanged() -> void:
	var run := EquipDismantleTestFixture.base_run(1)
	var catalog := EquipDismantleTestFixture.battle_catalog()
	var target_id := EquipDismantleTestFixture.unit_id(1)
	var equipped_id := EquipDismantleTestFixture.item_id(1)
	var challenger_id := EquipDismantleTestFixture.item_id(2)
	var items: Array[ItemInstanceState] = [
		EquipDismantleTestFixture.item(equipped_id, &"equipment.unique_a", target_id),
		EquipDismantleTestFixture.item(challenger_id, &"equipment.unique_b"),
	]
	run.roster_state.item_instances = items
	run.roster_state.inventory_item_instance_ids = [challenger_id]
	var unit := EquipDismantleTestFixture.find_unit(run, target_id)
	unit.equipment_instance_ids = [equipped_id]
	var before_equipment := unit.equipment_instance_ids.duplicate()

	var result := EquipItemCommand.new(target_id, challenger_id, catalog).apply_to(run)
	assert_false(result.ok)
	assert_eq(
		EquipDismantleTestFixture.error_source_code(result),
		"EQUIP_ITEM_UNIQUE_GROUP_CONFLICT"
	)
	assert_eq(unit.equipment_instance_ids, before_equipment)
	var challenger := EquipDismantleTestFixture.find_item(run, challenger_id)
	assert_null(challenger.bound_unit_instance_id)
	assert_true(run.roster_state.inventory_item_instance_ids.has(challenger_id))

func test_equip_rejects_stale_catalog_generation_and_leaves_state_unchanged() -> void:
	# F3 regression: a catalog pinned to a different manifest generation than the
	# draft's content_snapshot must be rejected before any binding, mirroring
	# commit_board_layout_command.gd:35-40.
	var run := EquipDismantleTestFixture.base_run(1)
	var stale_catalog := EquipDismantleTestFixture.battle_catalog(
		"9999999999999999999999999999999999999999999999999999999999999999"
	)
	var target_id := EquipDismantleTestFixture.unit_id(1)
	var item_id := EquipDismantleTestFixture.item_id(1)
	run.roster_state.item_instances = [
		EquipDismantleTestFixture.item(item_id, &"equipment.plain_a"),
	]
	run.roster_state.inventory_item_instance_ids = [item_id]

	var result := EquipItemCommand.new(target_id, item_id, stale_catalog).apply_to(run)
	assert_false(result.ok)
	assert_eq(
		EquipDismantleTestFixture.error_source_code(result),
		"EQUIP_ITEM_CATALOG_GENERATION_MISMATCH"
	)
	var unit := EquipDismantleTestFixture.find_unit(run, target_id)
	var no_equipment: Array[String] = []
	assert_eq(unit.equipment_instance_ids, no_equipment)
	var untouched := EquipDismantleTestFixture.find_item(run, item_id)
	assert_null(untouched.bound_unit_instance_id)
	assert_true(run.roster_state.inventory_item_instance_ids.has(item_id))

func test_equip_rejects_component_item_and_leaves_state_unchanged() -> void:
	var run := EquipDismantleTestFixture.base_run(1)
	var catalog := EquipDismantleTestFixture.battle_catalog()
	var target_id := EquipDismantleTestFixture.unit_id(1)
	var component_id := EquipDismantleTestFixture.item_id(1)
	var component := EquipDismantleTestFixture.item(component_id, &"item_component.gem")
	run.roster_state.item_instances = [component]
	run.roster_state.inventory_item_instance_ids = [component_id]

	var result := EquipItemCommand.new(target_id, component_id, catalog).apply_to(run)
	assert_false(result.ok)
	assert_eq(EquipDismantleTestFixture.error_source_code(result), "EQUIP_ITEM_NOT_EQUIPMENT")
	var unit := EquipDismantleTestFixture.find_unit(run, target_id)
	var no_equipment: Array[String] = []
	assert_eq(unit.equipment_instance_ids, no_equipment)
	var reloaded := EquipDismantleTestFixture.find_item(run, component_id)
	assert_null(reloaded.bound_unit_instance_id)
	assert_true(run.roster_state.inventory_item_instance_ids.has(component_id))
