extends GutTest

## T05 / S4-AC-009 (specs/build-systems/design.md §5.4): selling a unit that
## carries 3 bound equipment instances must be atomic end-to-end -- a crash
## mid-transaction must leave the reloaded save exactly as it was *before* the
## sale (equipment still bound, gold unchanged), and a completed transaction
## must leave the reloaded save exactly as it was *after* the sale (all 3
## equipment instances unbound into inventory exactly once, gold increased
## exactly once) -- never a partial state, a duplicated item, or lost gold.
## S4 introduces no new mechanism for this (design §5.4): it reuses S3's
## SellUnitCommand (which already unbinds equipment -- shop_service.gd:126-138)
## routed through the existing RunController copy-validate-save-swap pipeline,
## mirroring
## tests/integration/build_items/test_forge_equipment_command_transaction.gd's
## storage-fault-injection pattern (itself mirroring
## tests/integration/run_controller/test_run_controller_transactions.gd).

const _RECEIPT_SELECTION_DIGEST: String = "1234567890123456789012345678901234567890123456789012345678901234"
const _RECEIPT_MANIFEST_DIGEST: String = "5678901234567890123456789012345678901234567890123456789012345678"
const _TARGET_UNIT_ID: String = "u_0000000000000010"
const _EQUIPMENT_A: StringName = &"equipment.sell_a"
const _EQUIPMENT_B: StringName = &"equipment.sell_b"
const _EQUIPMENT_C: StringName = &"equipment.sell_c"

func test_crash_before_save_leaves_reload_at_pre_sale_state() -> void:
	var faults: Array[StorageFaultKey] = [
		StorageFaultKey.new(StorageFaultKey.DIRECTORY, StorageFaultKey.MAIN, 0),
		StorageFaultKey.new(StorageFaultKey.OPEN_WRITE, StorageFaultKey.TMP, 0),
	]
	for fault: StorageFaultKey in faults:
		var run := _base_run()
		var catalog := _catalog(run.content_snapshot.manifest_digest_value())
		var storage := FakeSaveStorage.new()
		storage.inject_fault(fault)
		var repository := _repository_for(storage)
		add_child_autofree(repository)
		var controller := _controller_for(run, repository)
		var before := controller.view_state()
		var before_equipment := _target_unit(before.roster).equipment_instance_ids.duplicate()
		var before_gold := before.economy.gold

		var result := controller.dispatch(SellUnitCommand.new(_TARGET_UNIT_ID, catalog))
		assert_false(result.ok)
		assert_eq(result.error.code, CommandError.SAVE_FAILED)
		# canonical (in-memory) view is exactly the pre-sale state -- equipment
		# still bound, gold untouched, unit still on the roster.
		var after := controller.view_state()
		assert_eq(_target_unit(after.roster).equipment_instance_ids, before_equipment)
		assert_eq(after.economy.gold, before_gold)
		assert_not_null(_target_unit(after.roster))
		# nothing was ever durably persisted -- a reload finds no save at all,
		# which is the strict form of "restored to the pre-transaction state"
		# since there was no prior successful save to fall back to either.
		var loaded := repository.load()
		assert_false(loaded.ok)

func test_completed_sale_reload_reflects_post_sale_state_exactly_once() -> void:
	var run := _base_run()
	var catalog := _catalog(run.content_snapshot.manifest_digest_value())
	var storage := FakeSaveStorage.new()
	var repository := _repository_for(storage)
	add_child_autofree(repository)
	var controller := _controller_for(run, repository)
	var before_gold := controller.view_state().economy.gold

	var result := controller.dispatch(SellUnitCommand.new(_TARGET_UNIT_ID, catalog))
	assert_true(result.ok, _apply_error(result))
	if not result.ok: return

	# in-memory canonical view: unit gone, all 3 equipment instances unbound
	# into inventory exactly once, gold increased by exactly the sale price.
	var view := controller.view_state()
	assert_null(_target_unit(view.roster))
	assert_eq(view.economy.gold, before_gold + 1)
	var view_inventory := view.roster.inventory_item_instance_ids
	for equipment_id: String in _equipment_ids():
		assert_true(view_inventory.has(equipment_id))
	assert_eq(view_inventory.size(), 3)

	# reload from storage must agree exactly -- no duplication, no loss, and
	# each equipment instance survives as precisely one ItemInstanceState.
	var loaded := repository.load()
	assert_true(loaded.ok)
	if not loaded.ok: return
	assert_null(_find_unit(loaded.run, _TARGET_UNIT_ID))
	assert_eq(loaded.run.economy_state.gold, before_gold + 1)
	var loaded_inventory := loaded.run.roster_state.inventory_item_instance_ids
	assert_eq(loaded_inventory.size(), 3)
	for equipment_id: String in _equipment_ids():
		assert_true(loaded_inventory.has(equipment_id))
		var matches: Array[ItemInstanceState] = []
		for item_instance: ItemInstanceState in loaded.run.roster_state.item_instances:
			if item_instance.instance_id == equipment_id:
				matches.append(item_instance)
		assert_eq(matches.size(), 1)
		assert_null(matches[0].bound_unit_instance_id)
	assert_true(loaded.run.roster_state.pending_item_overflow.is_empty())

func _equipment_ids() -> Array[String]:
	return ["it_0000000000000011", "it_0000000000000012", "it_0000000000000013"]

func _target_unit(roster: RosterViewState) -> UnitInstance:
	for unit: UnitInstance in roster.unit_instances:
		if unit.instance_id == _TARGET_UNIT_ID:
			return unit
	return null

func _find_unit(run: RunState, instance_id: String) -> UnitInstance:
	for unit: UnitInstance in run.roster_state.unit_instances:
		if unit.instance_id == instance_id:
			return unit
	return null

## Pinned receipt: base SaveRootFixture receipt plus this file's 3 equipment
## def_ids, so a save()/load() roundtrip never tombstones the sold unit's
## equipment (mirrors forge/equip fixtures' equipment_receipt() precedent).
func _receipt() -> PinnedCatalogBuildReceipt:
	var base := SaveRootFixture.create_receipt()
	var active_ids: Array[StringName] = base.active_entry_ids.duplicate()
	active_ids.append(_EQUIPMENT_A)
	active_ids.append(_EQUIPMENT_B)
	active_ids.append(_EQUIPMENT_C)
	active_ids.sort_custom(func(left: StringName, right: StringName) -> bool:
		return String(left) < String(right)
	)
	return PinnedCatalogBuildReceipt.new(
		base.catalog_schema_version,
		base.content_codec_version,
		base.content_version,
		_RECEIPT_SELECTION_DIGEST,
		active_ids,
		base.economy_config_id,
		base.combat_config_id,
		base.reward_table_ids,
		base.map_node_def_ids,
		base.challenge_unlock_def_ids,
		base.meta_reward_table_id,
		_RECEIPT_MANIFEST_DIGEST
	)

func _repository_for(storage: SaveStoragePort) -> SaveRepository:
	return SaveRepository.new(
		storage,
		FakePinnedCatalogReceiptPort.new(_receipt()),
		FakeContentIdMigrationPort.new(),
		RunStateValidator.new()
	)

func _catalog(manifest_digest: String) -> EconomyExpeditionCatalog:
	return EconomyTestFixture.save_fixture_catalog(manifest_digest)

## A minimal valid PREPARE-phase RunState with one benched unit carrying 3
## bound equipment instances, 10 starting gold, and room in inventory (no
## overflow interplay -- that is covered separately by
## tests/unit/build_items/test_resolve_overflow_command.gd and
## tests/integration/build_items/test_overflow_phase_gate.gd).
func _base_run() -> RunState:
	var run := SaveRootFixture.create_valid_root().run
	var snapshot_result := ContentSnapshotState.from_pinned_receipt(_receipt())
	assert(snapshot_result.ok, "_receipt() must build a valid content snapshot")
	run.content_snapshot = snapshot_result.snapshot
	run.run_phase = RunState.RunPhase.PREPARE
	run.resolution_state = IdleResolutionState.new()
	# SellUnitCommand's request needs a non-empty current node id (see
	## economy_command_support.gd's current_node_id()) even though selling
	## itself is not node-scoped -- mirrors every other PREPARE-phase fixture
	## in this suite (e.g. test_combat_transaction_commands.gd's
	## _prepare_fixture()).
	var node_key_result := RuntimeKeySchemaRegistry.new().build_node(
		StringName(run.run_id), 1, &"normal", 0, 0
	)
	assert(node_key_result.ok, "fixture must be able to build a node key")
	var node_key := node_key_result.key_state as NodeKeyState
	var nodes: Array[MapNodeState] = [MapNodeState.new(
		String(node_key.digest), node_key, &"mapnode.fixture", 1, 0, 0,
		MapNodeState.NodeKind.NORMAL,
		"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
		null, false
	)]
	var edges: Array[MapEdgeState] = []
	var completed: Array[String] = []
	run.map_state = MapState.new(
		nodes, edges, OptionalStringValue.new(String(node_key.digest)), completed
	)
	run.current_node_id = OptionalStringValue.new(String(node_key.digest))
	run.economy_state = EconomyState.new(10, 1, 0, 0, 0, 0, [])
	run.unit_pool_state = UnitPoolState.new([
		UnitPoolEntryState.new(&"unit.fixture", 1, 0, 0, 1),
	])
	var equipment_ids := _equipment_ids()
	var target := UnitInstance.new(
		_TARGET_UNIT_ID, &"unit.fixture", 1, equipment_ids, U64Bits.from_u32(0, 10).value
	)
	var items: Array[ItemInstanceState] = [
		ItemInstanceState.new(
			equipment_ids[0], _EQUIPMENT_A, OptionalStringValue.new(_TARGET_UNIT_ID),
			U64Bits.from_u32(0, 11).value
		),
		ItemInstanceState.new(
			equipment_ids[1], _EQUIPMENT_B, OptionalStringValue.new(_TARGET_UNIT_ID),
			U64Bits.from_u32(0, 12).value
		),
		ItemInstanceState.new(
			equipment_ids[2], _EQUIPMENT_C, OptionalStringValue.new(_TARGET_UNIT_ID),
			U64Bits.from_u32(0, 13).value
		),
	]
	var no_placements: Array[BoardPlacementState] = []
	var no_ids: Array[String] = []
	var relics: Array[RelicSlotState] = []
	for index: int in range(5):
		relics.append(RelicSlotState.new(index, null))
	run.roster_state = RosterState.new(
		BoardState.new(no_placements), [_TARGET_UNIT_ID], [target], items,
		no_ids, no_ids, relics
	)
	run.next_item_serial = U64Bits.from_u32(0, 14).value
	return run

func _controller_for(run: RunState, repository: SaveRepository) -> RunController:
	var session := RunSession.new(
		SaveRootFixture.create_valid_root().profile, run,
		TestCatalogLease.new(run.content_snapshot.manifest_digest_value())
	)
	return RunController.new(
		session, repository, RunStateValidator.new(),
		RunSaveRootFactory.new("0.1.0", FixedRunCommitClock.new())
	)

func _apply_error(result: Variant) -> String:
	if result == null or result.error == null:
		return "unknown apply failure"
	return "%s at %s" % [String(result.error.code), String(result.error.field_path)]
