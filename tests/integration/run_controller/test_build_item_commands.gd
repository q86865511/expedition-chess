extends GutTest

## T04 / S4-AC-006/007 end-to-end through RunController.dispatch: a rejected
## EquipItemCommand / DismantleEquipmentCommand must discard the whole draft
## (copy-validate-save-swap) -- persisted state and the live view must be
## byte-for-byte the state from before the failed command.

func test_equip_fourth_item_via_controller_discards_whole_draft() -> void:
	var root := SaveRootFixture.create_valid_root()
	root.run = _run_with_three_equipped_and_one_spare()
	var storage := FakeSaveStorage.new()
	var repository := EquipDismantleTestFixture.repository_for(storage)
	add_child_autofree(repository)
	var seed_result := repository.save(root)
	assert_true(seed_result.ok)
	var controller := _controller_for(root, repository)
	var catalog := EquipDismantleTestFixture.battle_catalog()
	var unit_id := EquipDismantleTestFixture.unit_id(1)
	var fourth_id := EquipDismantleTestFixture.item_id(4)
	var before := controller.view_state()

	var result := controller.dispatch(EquipItemCommand.new(unit_id, fourth_id, catalog))
	assert_false(result.ok)

	var after := controller.view_state()
	assert_eq(after.roster.unit_instances[0].equipment_instance_ids.size(), 3)
	assert_eq(after.publication_serial.to_hex(), before.publication_serial.to_hex())
	var reloaded := repository.load()
	assert_true(reloaded.ok)
	if not reloaded.ok: return
	assert_eq(reloaded.run.roster_state.unit_instances[0].equipment_instance_ids.size(), 3)
	assert_true(reloaded.run.roster_state.inventory_item_instance_ids.has(fourth_id))
	var spare_item := EquipDismantleTestFixture.find_item(reloaded.run, fourth_id)
	assert_null(spare_item.bound_unit_instance_id)

func test_dismantle_missing_consumable_via_controller_discards_whole_draft() -> void:
	var root := SaveRootFixture.create_valid_root()
	root.run = _run_with_bound_equipment_and_no_consumable()
	var storage := FakeSaveStorage.new()
	var repository := EquipDismantleTestFixture.repository_for(storage)
	add_child_autofree(repository)
	var seed_result := repository.save(root)
	assert_true(seed_result.ok)
	var controller := _controller_for(root, repository)
	var equipment_id := EquipDismantleTestFixture.item_id(1)
	var missing_consumable_id := EquipDismantleTestFixture.item_id(99)
	var before := controller.view_state()

	var result := controller.dispatch(
		DismantleEquipmentCommand.new(
			equipment_id, missing_consumable_id,
			EquipDismantleTestFixture.consumable_rules()
		)
	)
	assert_false(result.ok)

	var after := controller.view_state()
	assert_eq(after.publication_serial.to_hex(), before.publication_serial.to_hex())
	var reloaded := repository.load()
	assert_true(reloaded.ok)
	if not reloaded.ok: return
	var unit_id := EquipDismantleTestFixture.unit_id(1)
	var unit := EquipDismantleTestFixture.find_unit(reloaded.run, unit_id)
	assert_eq(unit.equipment_instance_ids, [equipment_id])
	var equipment_item := EquipDismantleTestFixture.find_item(reloaded.run, equipment_id)
	assert_not_null(equipment_item.bound_unit_instance_id)
	assert_eq(equipment_item.bound_unit_instance_id.value, unit_id)

func test_dispatch_rejects_component_bound_as_equipment_at_commit() -> void:
	# F1: even a command that (buggily) binds a non-equipment item as equipment
	# must be stopped by the run_state_validator equipment-kind invariant on the
	# real commit path, because RunController now holds the pinned battle catalog.
	var root := SaveRootFixture.create_valid_root()
	root.run = _run_with_unbound_component()
	var storage := FakeSaveStorage.new()
	var repository := EquipDismantleTestFixture.repository_for(storage)
	add_child_autofree(repository)
	var seed_result := repository.save(root)
	assert_true(seed_result.ok)
	var controller := _controller_for(root, repository)
	var unit_id := EquipDismantleTestFixture.unit_id(1)
	var component_id := EquipDismantleTestFixture.item_id(1)
	var before := controller.view_state()

	var result := controller.dispatch(
		BindItemAsEquipmentUnchecked.new(unit_id, component_id)
	)
	assert_false(result.ok)
	assert_eq(result.error.code, CommandError.VALIDATION_FAILED)
	assert_eq(result.error.field_path, &"run.roster_state.item_instances.def_id")

	var after := controller.view_state()
	assert_eq(after.publication_serial.to_hex(), before.publication_serial.to_hex())
	var reloaded := repository.load()
	assert_true(reloaded.ok)
	if not reloaded.ok: return
	var component := EquipDismantleTestFixture.find_item(reloaded.run, component_id)
	assert_null(component.bound_unit_instance_id)
	assert_true(reloaded.run.roster_state.inventory_item_instance_ids.has(component_id))

func _run_with_unbound_component() -> RunState:
	var run := EquipDismantleTestFixture.base_run(1)
	var component_id := EquipDismantleTestFixture.item_id(1)
	run.roster_state.item_instances = [
		EquipDismantleTestFixture.item(component_id, &"item_component.gem"),
	]
	run.roster_state.inventory_item_instance_ids = [component_id]
	return run

func _run_with_three_equipped_and_one_spare() -> RunState:
	var run := EquipDismantleTestFixture.base_run(1)
	var unit_id := EquipDismantleTestFixture.unit_id(1)
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
			equipped_ids[index], equipped_defs[index], unit_id
		))
	var fourth_id := EquipDismantleTestFixture.item_id(4)
	items.append(EquipDismantleTestFixture.item(fourth_id, &"equipment.plain_d"))
	run.roster_state.item_instances = items
	run.roster_state.inventory_item_instance_ids = [fourth_id]
	var unit := EquipDismantleTestFixture.find_unit(run, unit_id)
	unit.equipment_instance_ids = equipped_ids
	return run

func _run_with_bound_equipment_and_no_consumable() -> RunState:
	var run := EquipDismantleTestFixture.base_run(1)
	var unit_id := EquipDismantleTestFixture.unit_id(1)
	var equipment_id := EquipDismantleTestFixture.item_id(1)
	run.roster_state.item_instances = [
		EquipDismantleTestFixture.item(equipment_id, &"equipment.plain_a", unit_id),
	]
	var unit := EquipDismantleTestFixture.find_unit(run, unit_id)
	unit.equipment_instance_ids = [equipment_id]
	return run

func _controller_for(root: SaveRoot, repository: SaveRepository) -> RunController:
	var session := RunSession.new(
		root.profile, root.run,
		TestCatalogLease.new(root.run.content_snapshot.manifest_digest_value())
	)
	# Pinned battle catalog wired in so the equipment-kind invariant runs on the
	# real commit path (F1), not just when validate_run is called directly.
	return RunController.new(
		session, repository, RunStateValidator.new(),
		RunSaveRootFactory.new("0.1.0", FixedRunCommitClock.new()),
		EquipDismantleTestFixture.battle_catalog()
	)

## Test-only command that binds an item to a unit as equipment WITHOUT the
## EquipItemCommand kind check, standing in for a hypothetical buggy command so
## the commit-time equipment-kind invariant can be exercised end-to-end (F1).
class BindItemAsEquipmentUnchecked extends RunCommand:
	var _unit_id: String
	var _item_id: String

	func _init(p_unit_id: String, p_item_id: String) -> void:
		_unit_id = p_unit_id
		_item_id = p_item_id

	func is_concrete() -> bool:
		return true

	func apply_to(draft: RunState) -> CommandApplyResult:
		for unit: UnitInstance in draft.roster_state.unit_instances:
			if unit.instance_id == _unit_id:
				unit.equipment_instance_ids.append(_item_id)
		for item: ItemInstanceState in draft.roster_state.item_instances:
			if item.instance_id == _item_id:
				item.bound_unit_instance_id = OptionalStringValue.new(_unit_id)
		draft.roster_state.inventory_item_instance_ids.erase(_item_id)
		return CommandApplyResult.success(draft)
