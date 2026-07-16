extends GutTest

func test_success_saves_then_swaps_and_reloads_merged_layout_once() -> void:
	var root := _root_with_units(9)
	var storage := FakeSaveStorage.new()
	var repository := SaveRootFixture.create_repository(storage)
	add_child_autofree(repository)
	var controller := _controller_for(root, repository)
	var probe := ViewPublicationProbe.new()
	controller.view_published.connect(probe.capture)

	var result := controller.dispatch(_command_for(root.run.roster_state))

	assert_true(result.ok, _command_error_text(result.error))
	if not result.ok:
		return
	assert_eq(probe.count, 1)
	assert_eq(result.view_state.publication_serial.to_hex(), "0000000000000001")
	assert_eq(result.view_state.roster.unit_instances.size(), 1)
	assert_eq(result.view_state.roster.unit_instances[0].star, 3)
	assert_eq(
		result.view_state.roster.unit_instances[0].instance_id,
		"u_0000000000000001"
	)
	var loaded := repository.load()
	assert_true(loaded.ok)
	assert_eq(loaded.run.roster_state.unit_instances.size(), 1)
	assert_eq(loaded.run.roster_state.unit_instances[0].star, 3)
	assert_eq(loaded.run.unit_pool_state.entries[0].held_copies, 9)

func test_equipment_bindings_inventory_and_overflow_survive_save_reload() -> void:
	var receipt := _equipment_receipt()
	var root := _root_with_equipment_merge(receipt)
	assert_not_null(root)
	if root == null:
		return
	var storage := FakeSaveStorage.new()
	var repository := _repository_for(storage, receipt)
	add_child_autofree(repository)
	var controller := _controller_for(root, repository)
	var command := CommitBoardLayoutCommand.new(
		root.run.roster_state.board,
		root.run.roster_state.bench_unit_instance_ids,
		_equipment_catalog(receipt.manifest_digest)
	)
	var apply_probe := command.apply_to(root.run.deep_clone())
	assert_true(apply_probe.ok)
	if not apply_probe.ok:
		return
	var factory := RunSaveRootFactory.new("0.1.0", FixedRunCommitClock.new())
	var candidate := factory.build(root.profile, apply_probe.draft)
	var codec := _codec_for(receipt)
	var encoded := codec.encode(candidate)
	assert_true(encoded.ok)
	if not encoded.ok:
		return
	var decoded := codec.decode_bytes(encoded.bytes.value)
	assert_true(
		decoded.ok,
		String(decoded.error.field_path) if decoded.error != null else "decode failed"
	)
	if not decoded.ok:
		return
	assert_not_null(decoded.root)
	if decoded.root == null:
		return

	var result := controller.dispatch(command)

	assert_true(result.ok, _command_error_text(result.error))
	if not result.ok:
		return
	var loaded := repository.load()
	assert_true(loaded.ok)
	if not loaded.ok:
		return
	var roster := loaded.run.roster_state
	assert_eq(roster.unit_instances.size(), 1)
	assert_eq(roster.unit_instances[0].equipment_instance_ids, [
		"it_0000000000000001",
		"it_0000000000000002",
		"it_0000000000000004",
	])
	assert_has(roster.inventory_item_instance_ids, "it_0000000000000003")
	assert_eq(roster.pending_item_overflow, ["it_0000000000000005"])
	assert_eq(roster.item_instances.size(), 20)
	assert_eq(
		_find_item(roster, "it_0000000000000004").bound_unit_instance_id.value,
		"u_0000000000000001"
	)
	assert_null(
		_find_item(roster, "it_0000000000000003").bound_unit_instance_id
	)
	assert_null(
		_find_item(roster, "it_0000000000000005").bound_unit_instance_id
	)

func test_board_validation_failure_has_zero_canonical_or_storage_mutation() -> void:
	var root := _root_with_units(1)
	var storage := FakeSaveStorage.new()
	var repository := SaveRootFixture.create_repository(storage)
	add_child_autofree(repository)
	var controller := _controller_for(root, repository)
	var before := controller.view_state()
	var invalid_placements: Array[BoardPlacementState] = [
		BoardPlacementState.new(5, 0, "u_0000000000000001"),
	]
	var no_bench: Array[String] = []

	var result := controller.dispatch(
		CommitBoardLayoutCommand.new(
			BoardState.new(invalid_placements),
			no_bench,
			_empty_catalog()
		)
	)

	assert_false(result.ok)
	assert_eq(result.error.code, CommandError.APPLY_FAILED)
	assert_eq(result.error.diagnostic_values.size(), 2)
	assert_eq(result.error.diagnostic_values[0].key, &"apply_code")
	assert_eq(
		result.error.diagnostic_values[0].string_value.value,
		String(CommandApplyError.APPLY_REJECTED)
	)
	assert_eq(result.error.diagnostic_values[1].key, &"source_code")
	assert_eq(
		result.error.diagnostic_values[1].string_value.value,
		String(BoardValidationIssue.WRONG_HALF)
	)
	_assert_view_unchanged(before, controller.view_state())
	assert_eq(storage.journal_snapshot().size(), 0)

func test_tmp_write_and_final_read_failures_have_zero_canonical_mutation() -> void:
	var faults: Array[StorageFaultKey] = [
		StorageFaultKey.new(StorageFaultKey.OPEN_WRITE, StorageFaultKey.TMP, 0),
		StorageFaultKey.new(StorageFaultKey.READ, StorageFaultKey.MAIN, 1),
	]
	for fault: StorageFaultKey in faults:
		var root := _root_with_units(9)
		var storage := FakeSaveStorage.new()
		var repository := SaveRootFixture.create_repository(storage)
		add_child_autofree(repository)
		var seed_result := repository.save(root)
		assert_true(seed_result.ok)
		storage.reset_journal()
		storage.inject_fault(fault)
		var controller := _controller_for(root, repository)
		var probe := ViewPublicationProbe.new()
		controller.view_published.connect(probe.capture)
		var before := controller.view_state()

		var result := controller.dispatch(_command_for(root.run.roster_state))

		assert_false(result.ok, "%s/%s" % [fault.operation_kind, fault.logical_path])
		assert_eq(result.error.code, CommandError.SAVE_FAILED)
		_assert_view_unchanged(before, controller.view_state())
		assert_eq(probe.count, 0)
		assert_true(
			_journal_contains(storage.journal_snapshot(), fault),
			"fault injection must reach %s/%s/%d" % [
				fault.operation_kind,
				fault.logical_path,
				fault.occurrence,
			]
		)
		storage.clear_faults()
		var reloaded := repository.load()
		assert_true(reloaded.ok)
		assert_eq(reloaded.run.roster_state.unit_instances.size(), 9)
		assert_eq(reloaded.run.roster_state.unit_instances[0].star, 1)

func _root_with_units(unit_count: int) -> SaveRoot:
	var root := SaveRootFixture.create_valid_root()
	root.run.run_phase = RunState.RunPhase.PREPARE
	root.run.economy_state.level = 9
	var units: Array[UnitInstance] = []
	var placements: Array[BoardPlacementState] = []
	var bench: Array[String] = []
	var no_equipment: Array[String] = []
	for index: int in range(unit_count):
		var instance_id := "u_%016x" % (index + 1)
		units.append(
			UnitInstance.new(
				instance_id,
				&"unit.fixture",
				1,
				no_equipment,
				U64Bits.from_hex("%016x" % (index + 1)).value
			)
		)
		if index < 4:
			placements.append(BoardPlacementState.new(0, index, instance_id))
		else:
			bench.append(instance_id)
	root.run.roster_state.unit_instances = units
	root.run.roster_state.board = BoardState.new(placements)
	root.run.roster_state.bench_unit_instance_ids = bench
	var pool_entries: Array[UnitPoolEntryState] = [
		UnitPoolEntryState.new(
			&"unit.fixture",
			unit_count,
			0,
			0,
			unit_count
		),
	]
	root.run.unit_pool_state = UnitPoolState.new(pool_entries)
	return root

func _root_with_equipment_merge(
	receipt: PinnedCatalogBuildReceipt
) -> SaveRoot:
	var root := _root_with_units(3)
	var snapshot_result := ContentSnapshotState.from_pinned_receipt(receipt)
	assert(
		snapshot_result.ok,
		String(snapshot_result.error.field_path) \
			if snapshot_result.error != null else "snapshot build failed"
	)
	if not snapshot_result.ok:
		return null
	root.run.content_snapshot = snapshot_result.snapshot
	root.run.economy_state.level = 1
	var units := root.run.roster_state.unit_instances
	units[0].equipment_instance_ids = [
		"it_0000000000000001",
		"it_0000000000000002",
	]
	units[1].equipment_instance_ids = [
		"it_0000000000000003",
		"it_0000000000000004",
	]
	units[2].equipment_instance_ids = ["it_0000000000000005"]
	var placements: Array[BoardPlacementState] = [
		BoardPlacementState.new(0, 0, units[0].instance_id),
	]
	root.run.roster_state.board = BoardState.new(placements)
	root.run.roster_state.bench_unit_instance_ids = [
		units[1].instance_id,
		units[2].instance_id,
	]
	var items: Array[ItemInstanceState] = [
		_item("it_0000000000000001", &"equipment.unique", units[0].instance_id, 1),
		_item("it_0000000000000002", &"equipment.plain", units[0].instance_id, 2),
		_item("it_0000000000000003", &"equipment.unique", units[1].instance_id, 3),
		_item("it_0000000000000004", &"equipment.plain", units[1].instance_id, 4),
		_item("it_0000000000000005", &"equipment.plain", units[2].instance_id, 5),
	]
	var inventory: Array[String] = []
	for serial: int in range(6, 21):
		var instance_id := "it_%016x" % serial
		items.append(_item(instance_id, &"equipment.plain", "", serial))
		items[items.size() - 1].bound_unit_instance_id = null
		inventory.append(instance_id)
	root.run.roster_state.item_instances = items
	root.run.roster_state.inventory_item_instance_ids = inventory
	var no_overflow: Array[String] = []
	root.run.roster_state.pending_item_overflow = no_overflow
	return root

func _command_for(roster: RosterState) -> CommitBoardLayoutCommand:
	return CommitBoardLayoutCommand.new(
		roster.board,
		roster.bench_unit_instance_ids,
		_empty_catalog()
	)

func _empty_catalog() -> BattleRuleCatalog:
	var no_equipment: Array[BattleEquipmentRule] = []
	return _catalog_with_equipment(
		no_equipment,
		SaveRootFixture.MANIFEST_DIGEST
	)

func _equipment_catalog(manifest_digest: String) -> BattleRuleCatalog:
	var unique := BattleEquipmentRule.new()
	unique.equipment_id = &"equipment.unique"
	unique.unique_group = OptionalStringNameValue.of(&"unique.fixture")
	var plain := BattleEquipmentRule.new()
	plain.equipment_id = &"equipment.plain"
	var equipment: Array[BattleEquipmentRule] = [unique, plain]
	return _catalog_with_equipment(equipment, manifest_digest)

func _catalog_with_equipment(
	equipment: Array[BattleEquipmentRule],
	manifest_digest: String
) -> BattleRuleCatalog:
	var units: Array[BattleUnitRule] = []
	var traits: Array[BattleTraitRule] = []
	var abilities: Array[BattleAbilityRule] = []
	var effects: Array[BattleEffectRule] = []
	var encounters: Array[BattleEncounterRule] = []
	var configs: Array[BattleCombatConfigRule] = []
	return BattleRuleCatalog.new(
		manifest_digest,
		units,
		traits,
		abilities,
		effects,
		encounters,
		equipment,
		configs
	)

func _equipment_receipt() -> PinnedCatalogBuildReceipt:
	var base := SaveRootFixture.create_receipt()
	var active_ids: Array[StringName] = base.active_entry_ids.duplicate()
	active_ids.append(&"equipment.plain")
	active_ids.append(&"equipment.unique")
	active_ids.sort_custom(func(left: StringName, right: StringName) -> bool:
		return String(left) < String(right)
	)
	return PinnedCatalogBuildReceipt.new(
		base.catalog_schema_version,
		base.content_codec_version,
		base.content_version,
		"3333333333333333333333333333333333333333333333333333333333333333",
		active_ids,
		base.economy_config_id,
		base.combat_config_id,
		base.reward_table_ids,
		base.map_node_def_ids,
		base.challenge_unlock_def_ids,
		base.meta_reward_table_id,
		"4444444444444444444444444444444444444444444444444444444444444444"
	)

func _repository_for(
	storage: SaveStoragePort,
	receipt: PinnedCatalogBuildReceipt
) -> SaveRepository:
	return SaveRepository.new(
		storage,
		FakePinnedCatalogReceiptPort.new(receipt),
		FakeContentIdMigrationPort.new(),
		RunStateValidator.new()
	)

func _codec_for(receipt: PinnedCatalogBuildReceipt) -> SaveJsonCodec:
	return SaveJsonCodec.new(
		FakePinnedCatalogReceiptPort.new(receipt),
		FakeContentIdMigrationPort.new()
	)

func _item(
	instance_id: String,
	def_id: StringName,
	owner_id: String,
	serial: int
) -> ItemInstanceState:
	var owner: OptionalStringValue = (
		OptionalStringValue.new(owner_id) if not owner_id.is_empty() else null
	)
	return ItemInstanceState.new(
		instance_id,
		def_id,
		owner,
		U64Bits.from_hex("%016x" % serial).value
	)

func _find_item(roster: RosterState, instance_id: String) -> ItemInstanceState:
	for item: ItemInstanceState in roster.item_instances:
		if item.instance_id == instance_id:
			return item
	return null

func _controller_for(root: SaveRoot, repository: SaveRepository) -> RunController:
	var lease := TestCatalogLease.new(
		root.run.content_snapshot.manifest_digest_value()
	)
	var session := RunSession.new(root.profile, root.run, lease)
	var factory := RunSaveRootFactory.new("0.1.0", FixedRunCommitClock.new())
	return RunController.new(session, repository, RunStateValidator.new(), factory)

func _assert_view_unchanged(before: RunViewState, after: RunViewState) -> void:
	assert_eq(after.publication_serial.to_hex(), before.publication_serial.to_hex())
	assert_eq(after.run_phase, before.run_phase)
	assert_eq(after.roster.unit_instances.size(), before.roster.unit_instances.size())
	assert_eq(after.roster.board.placements.size(), before.roster.board.placements.size())
	assert_eq(after.roster.bench_unit_instance_ids, before.roster.bench_unit_instance_ids)

func _command_error_text(error: CommandError) -> String:
	if error == null:
		return "missing command error"
	var values: Array[String] = []
	for diagnostic: DiagnosticValue in error.diagnostic_values:
		if diagnostic.string_value != null:
			values.append("%s=%s" % [diagnostic.key, diagnostic.string_value.value])
	return "%s:%s [%s]" % [error.code, error.field_path, ",".join(values)]

func _journal_contains(
	journal: Array[StorageFaultKey],
	target: StorageFaultKey
) -> bool:
	for key: StorageFaultKey in journal:
		if key.equals(target):
			return true
	return false
