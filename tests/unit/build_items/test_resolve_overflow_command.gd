extends GutTest

## T05 / S4-AC-008 (ResolveOverflowCommand): tray 一次性、逐件明確處置(裝備/
## 鍛造/明確放棄),無靜默丟棄;每種處置的拒絕路徑(裝備上限、unique_group、
## 查無配方)回具名 error 且 tray 不變.
##
## Contract under test (test-author decision, see
## tests/fixtures/build_items/resolve_overflow_test_fixture.gd header for why):
##   ResolveOverflowCommand.equip(overflow_item_instance_id: String,
##     target_unit_instance_id: String, catalog: BattleRuleCatalog) -> RunCommand
##   ResolveOverflowCommand.forge(overflow_item_instance_id: String,
##     other_component_instance_id: String, forge_table: ForgeRecipeTable) -> RunCommand
##   ResolveOverflowCommand.abandon(overflow_item_instance_id: String) -> RunCommand
##   .apply_to(draft: RunState) -> CommandApplyResult
## Named error codes are carried as the existing "source_code" diagnostic
## string (see commit_board_layout_command.gd's `_rejected` helper), read via
## EquipDismantleTestFixture.error_source_code().

func test_equip_disposition_binds_overflow_item_and_clears_it_from_tray() -> void:
	var run := ResolveOverflowTestFixture.base_run(1)
	var catalog := ResolveOverflowTestFixture.battle_catalog()
	var target_id := ResolveOverflowTestFixture.unit_id(1)
	var overflow_id := ResolveOverflowTestFixture.item_id(1)
	var overflow_item := ResolveOverflowTestFixture.item(
		overflow_id, ResolveOverflowTestFixture.EQUIPMENT_PLAIN
	)
	run.roster_state.item_instances = [overflow_item]
	run.roster_state.pending_item_overflow = [overflow_id]

	var command := ResolveOverflowCommand.equip(overflow_id, target_id, catalog)
	assert_true(command.is_concrete())
	var result := command.apply_to(run)
	assert_true(result.ok, EquipDismantleTestFixture.error_source_code(result))
	if not result.ok: return

	assert_false(result.draft.roster_state.pending_item_overflow.has(overflow_id))
	var bound_item := ResolveOverflowTestFixture.find_item(result.draft, overflow_id)
	assert_not_null(bound_item)
	assert_not_null(bound_item.bound_unit_instance_id)
	assert_eq(bound_item.bound_unit_instance_id.value, target_id)
	var unit := ResolveOverflowTestFixture.find_unit(result.draft, target_id)
	assert_eq(unit.equipment_instance_ids, [overflow_id])
	# no silent duplication: exactly one item instance survives.
	assert_eq(result.draft.roster_state.item_instances.size(), 1)

func test_equip_disposition_rejects_when_unit_already_at_equipment_cap() -> void:
	var run := ResolveOverflowTestFixture.base_run(1)
	var catalog := ResolveOverflowTestFixture.battle_catalog()
	var target_id := ResolveOverflowTestFixture.unit_id(1)
	var equipped_ids: Array[String] = [
		ResolveOverflowTestFixture.item_id(1),
		ResolveOverflowTestFixture.item_id(2),
		ResolveOverflowTestFixture.item_id(3),
	]
	var items: Array[ItemInstanceState] = []
	for index: int in range(3):
		items.append(ResolveOverflowTestFixture.item(
			equipped_ids[index], ResolveOverflowTestFixture.EQUIPMENT_PLAIN, target_id
		))
	var overflow_id := ResolveOverflowTestFixture.item_id(4)
	items.append(ResolveOverflowTestFixture.item(
		overflow_id, ResolveOverflowTestFixture.EQUIPMENT_PLAIN
	))
	run.roster_state.item_instances = items
	run.roster_state.pending_item_overflow = [overflow_id]
	var unit := ResolveOverflowTestFixture.find_unit(run, target_id)
	unit.equipment_instance_ids = equipped_ids.duplicate()
	var before_tray := run.roster_state.pending_item_overflow.duplicate()

	var result := ResolveOverflowCommand.equip(overflow_id, target_id, catalog).apply_to(run)
	assert_false(result.ok)
	assert_eq(EquipDismantleTestFixture.error_source_code(result), "RESOLVE_OVERFLOW_SLOTS_FULL")
	# tray and binding state must be untouched by a rejected disposition.
	assert_eq(run.roster_state.pending_item_overflow, before_tray)
	var untouched := ResolveOverflowTestFixture.find_item(run, overflow_id)
	assert_null(untouched.bound_unit_instance_id)

func test_equip_disposition_rejects_unique_group_conflict_and_leaves_tray_unchanged() -> void:
	var run := ResolveOverflowTestFixture.base_run(1)
	var catalog := ResolveOverflowTestFixture.battle_catalog()
	var target_id := ResolveOverflowTestFixture.unit_id(1)
	var equipped_id := ResolveOverflowTestFixture.item_id(1)
	var overflow_id := ResolveOverflowTestFixture.item_id(2)
	run.roster_state.item_instances = [
		ResolveOverflowTestFixture.item(
			equipped_id, ResolveOverflowTestFixture.EQUIPMENT_UNIQUE_A, target_id
		),
		ResolveOverflowTestFixture.item(
			overflow_id, ResolveOverflowTestFixture.EQUIPMENT_UNIQUE_B
		),
	]
	run.roster_state.pending_item_overflow = [overflow_id]
	var unit := ResolveOverflowTestFixture.find_unit(run, target_id)
	unit.equipment_instance_ids = [equipped_id]
	var before_tray := run.roster_state.pending_item_overflow.duplicate()

	var result := ResolveOverflowCommand.equip(overflow_id, target_id, catalog).apply_to(run)
	assert_false(result.ok)
	assert_eq(
		EquipDismantleTestFixture.error_source_code(result),
		"RESOLVE_OVERFLOW_UNIQUE_GROUP_CONFLICT"
	)
	assert_eq(run.roster_state.pending_item_overflow, before_tray)
	var challenger := ResolveOverflowTestFixture.find_item(run, overflow_id)
	assert_null(challenger.bound_unit_instance_id)

func test_forge_disposition_consumes_overflow_component_and_inventory_component() -> void:
	var run := ResolveOverflowTestFixture.base_run(1)
	var forge_table := ResolveOverflowTestFixture.forge_table()
	var overflow_id := ResolveOverflowTestFixture.item_id(1)
	var inventory_component_id := ResolveOverflowTestFixture.item_id(2)
	run.roster_state.item_instances = [
		ResolveOverflowTestFixture.item(overflow_id, ResolveOverflowTestFixture.COMPONENT_ALPHA),
		ResolveOverflowTestFixture.item(
			inventory_component_id, ResolveOverflowTestFixture.COMPONENT_BETA
		),
	]
	run.roster_state.pending_item_overflow = [overflow_id]
	run.roster_state.inventory_item_instance_ids = [inventory_component_id]
	run.next_item_serial = U64Bits.from_u32(0, 5).value

	var result := ResolveOverflowCommand.forge(
		overflow_id, inventory_component_id, forge_table
	).apply_to(run)
	assert_true(result.ok, EquipDismantleTestFixture.error_source_code(result))
	if not result.ok: return

	assert_false(result.draft.roster_state.pending_item_overflow.has(overflow_id))
	assert_null(ResolveOverflowTestFixture.find_item(result.draft, overflow_id))
	assert_null(ResolveOverflowTestFixture.find_item(result.draft, inventory_component_id))
	assert_false(
		result.draft.roster_state.inventory_item_instance_ids.has(inventory_component_id)
	)
	# exactly one forged equipment instance replaces the two consumed components.
	assert_eq(result.draft.roster_state.item_instances.size(), 1)
	var forged := result.draft.roster_state.item_instances[0]
	assert_eq(forged.def_id, ResolveOverflowTestFixture.EQUIPMENT_FORGED)
	assert_true(result.draft.roster_state.inventory_item_instance_ids.has(forged.instance_id))

func test_forge_disposition_rejects_unregistered_pair_and_leaves_tray_unchanged() -> void:
	var run := ResolveOverflowTestFixture.base_run(1)
	var forge_table := ResolveOverflowTestFixture.forge_table()
	var overflow_id := ResolveOverflowTestFixture.item_id(1)
	var inventory_component_id := ResolveOverflowTestFixture.item_id(2)
	# alpha+alpha has no registered recipe in the fixture's forge_table().
	run.roster_state.item_instances = [
		ResolveOverflowTestFixture.item(overflow_id, ResolveOverflowTestFixture.COMPONENT_ALPHA),
		ResolveOverflowTestFixture.item(
			inventory_component_id, ResolveOverflowTestFixture.COMPONENT_ALPHA
		),
	]
	run.roster_state.pending_item_overflow = [overflow_id]
	run.roster_state.inventory_item_instance_ids = [inventory_component_id]
	var before_tray := run.roster_state.pending_item_overflow.duplicate()
	var before_item_count := run.roster_state.item_instances.size()

	var result := ResolveOverflowCommand.forge(
		overflow_id, inventory_component_id, forge_table
	).apply_to(run)
	assert_false(result.ok)
	assert_eq(
		EquipDismantleTestFixture.error_source_code(result),
		"RESOLVE_OVERFLOW_RECIPE_NOT_FOUND"
	)
	assert_eq(run.roster_state.pending_item_overflow, before_tray)
	assert_eq(run.roster_state.item_instances.size(), before_item_count)
	assert_true(run.roster_state.inventory_item_instance_ids.has(inventory_component_id))

func test_abandon_disposition_removes_the_instance_without_a_trace() -> void:
	var run := ResolveOverflowTestFixture.base_run(1)
	var overflow_id := ResolveOverflowTestFixture.item_id(1)
	run.roster_state.item_instances = [
		ResolveOverflowTestFixture.item(overflow_id, ResolveOverflowTestFixture.EQUIPMENT_PLAIN),
	]
	run.roster_state.pending_item_overflow = [overflow_id]

	var result := ResolveOverflowCommand.abandon(overflow_id).apply_to(run)
	assert_true(result.ok, EquipDismantleTestFixture.error_source_code(result))
	if not result.ok: return

	assert_false(result.draft.roster_state.pending_item_overflow.has(overflow_id))
	assert_null(ResolveOverflowTestFixture.find_item(result.draft, overflow_id))
	assert_false(
		result.draft.roster_state.inventory_item_instance_ids.has(overflow_id)
	)
	# explicit abandonment is a true discard: nothing survives it anywhere.
	var no_items: Array[ItemInstanceState] = []
	assert_eq(result.draft.roster_state.item_instances, no_items)

func test_forge_disposition_consumes_tray_partner_and_leaves_no_residual_tray_id() -> void:
	# W3-F1 regression (Opus review): the forge partner may itself be sourced
	# from the tray (§5.4), not just inventory -- both consumed instances must
	# be erased from pending_item_overflow with no residual id surviving.
	var run := ResolveOverflowTestFixture.base_run(1)
	var forge_table := ResolveOverflowTestFixture.forge_table()
	var overflow_id := ResolveOverflowTestFixture.item_id(1)
	var tray_partner_id := ResolveOverflowTestFixture.item_id(2)
	run.roster_state.item_instances = [
		ResolveOverflowTestFixture.item(overflow_id, ResolveOverflowTestFixture.COMPONENT_ALPHA),
		ResolveOverflowTestFixture.item(tray_partner_id, ResolveOverflowTestFixture.COMPONENT_BETA),
	]
	run.roster_state.pending_item_overflow = [overflow_id, tray_partner_id]
	run.next_item_serial = U64Bits.from_u32(0, 5).value

	var result := ResolveOverflowCommand.forge(
		overflow_id, tray_partner_id, forge_table
	).apply_to(run)
	assert_true(result.ok, EquipDismantleTestFixture.error_source_code(result))
	if not result.ok: return

	# no residual id of either consumed component anywhere in the tray.
	assert_false(result.draft.roster_state.pending_item_overflow.has(overflow_id))
	assert_false(result.draft.roster_state.pending_item_overflow.has(tray_partner_id))
	assert_null(ResolveOverflowTestFixture.find_item(result.draft, overflow_id))
	assert_null(ResolveOverflowTestFixture.find_item(result.draft, tray_partner_id))
	assert_eq(result.draft.roster_state.item_instances.size(), 1)
	var forged := result.draft.roster_state.item_instances[0]
	assert_eq(forged.def_id, ResolveOverflowTestFixture.EQUIPMENT_FORGED)
	assert_true(result.draft.roster_state.inventory_item_instance_ids.has(forged.instance_id))

func test_equip_disposition_rejects_stale_catalog_generation_and_leaves_state_unchanged() -> void:
	# W3-F2: a catalog pinned to a different manifest generation than the
	# draft's content_snapshot is rejected before any binding (mirrors
	# equip_item_command.gd:39-43).
	var run := ResolveOverflowTestFixture.base_run(1)
	var stale_catalog := ResolveOverflowTestFixture.battle_catalog(
		"9999999999999999999999999999999999999999999999999999999999999999"
	)
	var target_id := ResolveOverflowTestFixture.unit_id(1)
	var overflow_id := ResolveOverflowTestFixture.item_id(1)
	run.roster_state.item_instances = [
		ResolveOverflowTestFixture.item(overflow_id, ResolveOverflowTestFixture.EQUIPMENT_PLAIN),
	]
	run.roster_state.pending_item_overflow = [overflow_id]
	var before_tray := run.roster_state.pending_item_overflow.duplicate()

	var result := ResolveOverflowCommand.equip(overflow_id, target_id, stale_catalog).apply_to(run)
	assert_false(result.ok)
	assert_eq(result.error.field_path, &"run.content_snapshot.manifest_digest")
	assert_eq(
		EquipDismantleTestFixture.error_source_code(result),
		"RESOLVE_OVERFLOW_CATALOG_GENERATION_MISMATCH"
	)
	assert_eq(run.roster_state.pending_item_overflow, before_tray)
	var untouched := ResolveOverflowTestFixture.find_item(run, overflow_id)
	assert_null(untouched.bound_unit_instance_id)

func test_forge_disposition_rejects_stale_forge_table_generation_and_leaves_state_unchanged() -> void:
	# W3-F2: a forge table pinned to a different manifest generation than the
	# draft's content_snapshot is rejected before any consumption (mirrors
	# forge_equipment_command.gd:44-48).
	var run := ResolveOverflowTestFixture.base_run(1)
	var stale_table := ResolveOverflowTestFixture.forge_table(
		"9999999999999999999999999999999999999999999999999999999999999999"
	)
	var overflow_id := ResolveOverflowTestFixture.item_id(1)
	var inventory_component_id := ResolveOverflowTestFixture.item_id(2)
	run.roster_state.item_instances = [
		ResolveOverflowTestFixture.item(overflow_id, ResolveOverflowTestFixture.COMPONENT_ALPHA),
		ResolveOverflowTestFixture.item(
			inventory_component_id, ResolveOverflowTestFixture.COMPONENT_BETA
		),
	]
	run.roster_state.pending_item_overflow = [overflow_id]
	run.roster_state.inventory_item_instance_ids = [inventory_component_id]
	var before_tray := run.roster_state.pending_item_overflow.duplicate()
	var before_item_count := run.roster_state.item_instances.size()

	var result := ResolveOverflowCommand.forge(
		overflow_id, inventory_component_id, stale_table
	).apply_to(run)
	assert_false(result.ok)
	assert_eq(result.error.field_path, &"run.content_snapshot.manifest_digest")
	assert_eq(
		EquipDismantleTestFixture.error_source_code(result),
		"RESOLVE_OVERFLOW_CATALOG_GENERATION_MISMATCH"
	)
	assert_eq(run.roster_state.pending_item_overflow, before_tray)
	assert_eq(run.roster_state.item_instances.size(), before_item_count)
	assert_true(run.roster_state.inventory_item_instance_ids.has(inventory_component_id))

func test_forge_disposition_rejects_when_partner_component_is_not_available() -> void:
	# W3-F2: a partner id absent from both the tray and inventory (never a
	# forge-eligible instance) is rejected by name, tray/state untouched.
	var run := ResolveOverflowTestFixture.base_run(1)
	var forge_table := ResolveOverflowTestFixture.forge_table()
	var overflow_id := ResolveOverflowTestFixture.item_id(1)
	var missing_partner_id := ResolveOverflowTestFixture.item_id(2)
	run.roster_state.item_instances = [
		ResolveOverflowTestFixture.item(overflow_id, ResolveOverflowTestFixture.COMPONENT_ALPHA),
	]
	run.roster_state.pending_item_overflow = [overflow_id]
	var before_tray := run.roster_state.pending_item_overflow.duplicate()
	var before_item_count := run.roster_state.item_instances.size()

	var result := ResolveOverflowCommand.forge(
		overflow_id, missing_partner_id, forge_table
	).apply_to(run)
	assert_false(result.ok)
	assert_eq(
		EquipDismantleTestFixture.error_source_code(result),
		"RESOLVE_OVERFLOW_COMPONENT_NOT_AVAILABLE"
	)
	assert_eq(run.roster_state.pending_item_overflow, before_tray)
	assert_eq(run.roster_state.item_instances.size(), before_item_count)

func test_forge_disposition_rejects_when_item_serial_is_exhausted_and_leaves_state_unchanged() -> void:
	# W3-F2: next_item_serial pinned at U64Bits.max_value() (the
	# InstanceIdFactory sentinel) must reject before any consumption -- no
	# forged instance can ever be minted past the id space.
	var run := ResolveOverflowTestFixture.base_run(1)
	var forge_table := ResolveOverflowTestFixture.forge_table()
	var overflow_id := ResolveOverflowTestFixture.item_id(1)
	var inventory_component_id := ResolveOverflowTestFixture.item_id(2)
	run.roster_state.item_instances = [
		ResolveOverflowTestFixture.item(overflow_id, ResolveOverflowTestFixture.COMPONENT_ALPHA),
		ResolveOverflowTestFixture.item(
			inventory_component_id, ResolveOverflowTestFixture.COMPONENT_BETA
		),
	]
	run.roster_state.pending_item_overflow = [overflow_id]
	run.roster_state.inventory_item_instance_ids = [inventory_component_id]
	run.next_item_serial = U64Bits.max_value()
	var before_tray := run.roster_state.pending_item_overflow.duplicate()
	var before_item_count := run.roster_state.item_instances.size()

	var result := ResolveOverflowCommand.forge(
		overflow_id, inventory_component_id, forge_table
	).apply_to(run)
	assert_false(result.ok)
	assert_eq(result.error.field_path, &"run.next_item_serial")
	assert_eq(
		EquipDismantleTestFixture.error_source_code(result),
		"RESOLVE_OVERFLOW_SERIAL_EXHAUSTED"
	)
	assert_eq(run.roster_state.pending_item_overflow, before_tray)
	assert_eq(run.roster_state.item_instances.size(), before_item_count)
	assert_true(run.roster_state.inventory_item_instance_ids.has(inventory_component_id))
	assert_eq(run.next_item_serial.to_hex(), U64Bits.max_value().to_hex())

func test_any_disposition_rejects_an_item_that_is_not_in_the_tray() -> void:
	var run := ResolveOverflowTestFixture.base_run(1)
	var not_overflowing_id := ResolveOverflowTestFixture.item_id(1)
	run.roster_state.item_instances = [
		ResolveOverflowTestFixture.item(
			not_overflowing_id, ResolveOverflowTestFixture.EQUIPMENT_PLAIN
		),
	]
	run.roster_state.inventory_item_instance_ids = [not_overflowing_id]
	var no_overflow: Array[String] = []
	run.roster_state.pending_item_overflow = no_overflow

	var result := ResolveOverflowCommand.abandon(not_overflowing_id).apply_to(run)
	assert_false(result.ok)
	assert_eq(
		EquipDismantleTestFixture.error_source_code(result),
		"RESOLVE_OVERFLOW_ITEM_NOT_IN_TRAY"
	)
	assert_not_null(ResolveOverflowTestFixture.find_item(run, not_overflowing_id))
	assert_true(run.roster_state.inventory_item_instance_ids.has(not_overflowing_id))
# W3-F1/F2 coverage 2026-07-23
