extends GutTest

## T03 / S4-AC-004/005 integration coverage: routes ForgeEquipmentCommand
## through the real RunController.dispatch() copy-validate-save-swap pipeline
## (not just the command's own apply_to() draft), so a storage/commit failure
## is proven to leave the *canonical* run's inventory untouched -- mirrors
## tests/integration/run_controller/test_run_controller_transactions.gd's
## storage-fault-injection pattern.

func test_forge_dispatch_success_commits_forged_equipment_into_inventory() -> void:
	var run := ForgeEquipmentTestFixture.base_run()
	var component_a := ForgeEquipmentTestFixture.item_id(1)
	var component_b := ForgeEquipmentTestFixture.item_id(2)
	run.roster_state.item_instances = [
		ForgeEquipmentTestFixture.item(component_a, ForgeEquipmentTestFixture.COMPONENT_ALPHA),
		ForgeEquipmentTestFixture.item(component_b, ForgeEquipmentTestFixture.COMPONENT_BETA),
	]
	run.roster_state.inventory_item_instance_ids = [component_a, component_b]
	var storage := FakeSaveStorage.new()
	var repository := ForgeEquipmentTestFixture.repository_for(storage)
	add_child_autofree(repository)
	var controller := _controller_for(run, repository)
	var table := ForgeEquipmentTestFixture.forge_table()

	var result := controller.dispatch(ForgeEquipmentCommand.new(component_a, component_b, table))
	assert_true(result.ok)
	if not result.ok: return
	assert_eq(result.view_state.roster.inventory_item_instance_ids.size(), 1)
	assert_false(result.view_state.roster.inventory_item_instance_ids.has(component_a))
	assert_false(result.view_state.roster.inventory_item_instance_ids.has(component_b))
	var loaded := repository.load()
	assert_true(loaded.ok)
	assert_eq(loaded.run.roster_state.item_instances.size(), 1)

func test_forge_commit_failure_leaves_canonical_inventory_unchanged() -> void:
	var run := ForgeEquipmentTestFixture.base_run()
	var component_a := ForgeEquipmentTestFixture.item_id(1)
	var component_b := ForgeEquipmentTestFixture.item_id(2)
	run.roster_state.item_instances = [
		ForgeEquipmentTestFixture.item(component_a, ForgeEquipmentTestFixture.COMPONENT_ALPHA),
		ForgeEquipmentTestFixture.item(component_b, ForgeEquipmentTestFixture.COMPONENT_BETA),
	]
	run.roster_state.inventory_item_instance_ids = [component_a, component_b]
	var storage := FakeSaveStorage.new()
	# fail at the earliest save stage (ensure_directory), mirroring
	# test_run_controller_transactions.gd's DIRECTORY-fault precedent -- the
	# commit must never reach a partially-applied state.
	storage.inject_fault(StorageFaultKey.new(StorageFaultKey.DIRECTORY, StorageFaultKey.MAIN, 0))
	var repository := ForgeEquipmentTestFixture.repository_for(storage)
	add_child_autofree(repository)
	var controller := _controller_for(run, repository)
	var table := ForgeEquipmentTestFixture.forge_table()
	var before_inventory := run.roster_state.inventory_item_instance_ids.duplicate()

	var result := controller.dispatch(ForgeEquipmentCommand.new(component_a, component_b, table))
	assert_false(result.ok)
	assert_eq(result.error.code, CommandError.SAVE_FAILED)
	assert_eq(controller.view_state().roster.inventory_item_instance_ids, before_inventory)
	assert_eq(controller.view_state().roster.inventory_item_instance_ids.size(), 2)
	# nothing was ever persisted -- read-back must still come up empty.
	var loaded := repository.load()
	assert_false(loaded.ok)

func _controller_for(run: RunState, repository: SaveRepository) -> RunController:
	var profile := SaveRootFixture.create_valid_root().profile
	var lease := TestCatalogLease.new(run.content_snapshot.manifest_digest_value())
	var session := RunSession.new(profile, run, lease)
	var factory := RunSaveRootFactory.new("0.1.0", FixedRunCommitClock.new())
	return RunController.new(session, repository, RunStateValidator.new(), factory)
