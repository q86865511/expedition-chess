extends GutTest

## T03 / S4-AC-004/005 (ForgeEquipmentCommand, specs/build-systems/design.md
## §5.1): two inventory component instance ids (including a self-pair of the
## same def_id) are consumed by an unordered ForgeRecipeTable lookup to produce
## exactly one new equipment instance (serial drawn from next_item_serial,
## incrementing it); a pair with no registered recipe is rejected by name;
## a full inventory routes the new instance to pending_item_overflow; any
## rejection leaves item_instances/inventory/next_item_serial untouched.
##
## Contract under test (test-author decision, see
## tests/fixtures/build_items/forge_equipment_test_fixture.gd header):
##   ForgeEquipmentCommand.new(component_instance_id_a: String,
##     component_instance_id_b: String, forge_table: ForgeRecipeTable) -> RunCommand
##   .apply_to(draft: RunState) -> CommandApplyResult
## Named error codes are carried as the existing "source_code" diagnostic
## string (see commit_board_layout_command.gd's `_rejected` helper), read via
## EquipDismantleTestFixture.error_source_code() (shared across build_items
## command tests, not duplicated per fixture).

func test_forge_consumes_two_distinct_components_and_produces_exactly_one_equipment_instance() -> void:
	var run := ForgeEquipmentTestFixture.base_run()
	var table := ForgeEquipmentTestFixture.forge_table()
	var component_a := ForgeEquipmentTestFixture.item_id(1)
	var component_b := ForgeEquipmentTestFixture.item_id(2)
	run.roster_state.item_instances = [
		ForgeEquipmentTestFixture.item(component_a, ForgeEquipmentTestFixture.COMPONENT_ALPHA),
		ForgeEquipmentTestFixture.item(component_b, ForgeEquipmentTestFixture.COMPONENT_BETA),
	]
	run.roster_state.inventory_item_instance_ids = [component_a, component_b]
	var starting_serial := run.next_item_serial.deep_clone()

	var command := ForgeEquipmentCommand.new(component_a, component_b, table)
	assert_true(command.is_concrete())
	var result := command.apply_to(run)
	assert_true(result.ok, EquipDismantleTestFixture.error_source_code(result))
	if not result.ok: return

	# exactly-once conservation: the two components are gone, replaced by exactly
	# one new equipment instance.
	assert_eq(result.draft.roster_state.item_instances.size(), 1)
	assert_null(ForgeEquipmentTestFixture.find_item(result.draft, component_a))
	assert_null(ForgeEquipmentTestFixture.find_item(result.draft, component_b))
	assert_false(result.draft.roster_state.inventory_item_instance_ids.has(component_a))
	assert_false(result.draft.roster_state.inventory_item_instance_ids.has(component_b))

	var forged := result.draft.roster_state.item_instances[0]
	assert_eq(forged.def_id, ForgeEquipmentTestFixture.EQUIPMENT_ALPHA_BETA)
	assert_null(forged.bound_unit_instance_id)
	assert_true(result.draft.roster_state.inventory_item_instance_ids.has(forged.instance_id))
	assert_false(result.draft.roster_state.pending_item_overflow.has(forged.instance_id))

	# serial rendezvous: the forged instance is stamped with the pre-forge
	# next_item_serial, and the draft's next_item_serial has advanced by one.
	assert_eq(forged.acquired_serial.to_hex(), starting_serial.to_hex())
	assert_eq(result.draft.next_item_serial.to_hex(), starting_serial.add(U64Bits.one()).to_hex())

func test_forge_self_pair_consumes_two_same_def_id_instances_and_produces_equipment() -> void:
	var run := ForgeEquipmentTestFixture.base_run()
	var table := ForgeEquipmentTestFixture.forge_table()
	var component_a := ForgeEquipmentTestFixture.item_id(1)
	var component_b := ForgeEquipmentTestFixture.item_id(2)
	run.roster_state.item_instances = [
		ForgeEquipmentTestFixture.item(component_a, ForgeEquipmentTestFixture.COMPONENT_ALPHA),
		ForgeEquipmentTestFixture.item(component_b, ForgeEquipmentTestFixture.COMPONENT_ALPHA),
	]
	run.roster_state.inventory_item_instance_ids = [component_a, component_b]

	var result := ForgeEquipmentCommand.new(component_a, component_b, table).apply_to(run)
	assert_true(result.ok, EquipDismantleTestFixture.error_source_code(result))
	if not result.ok: return

	assert_eq(result.draft.roster_state.item_instances.size(), 1)
	var forged := result.draft.roster_state.item_instances[0]
	assert_eq(forged.def_id, ForgeEquipmentTestFixture.EQUIPMENT_ALPHA_ALPHA)
	assert_null(ForgeEquipmentTestFixture.find_item(result.draft, component_a))
	assert_null(ForgeEquipmentTestFixture.find_item(result.draft, component_b))
	assert_true(result.draft.roster_state.inventory_item_instance_ids.has(forged.instance_id))

func test_forge_rejects_missing_recipe_and_leaves_inventory_unchanged() -> void:
	var run := ForgeEquipmentTestFixture.base_run()
	var table := ForgeEquipmentTestFixture.forge_table()
	var component_a := ForgeEquipmentTestFixture.item_id(1)
	var component_b := ForgeEquipmentTestFixture.item_id(2)
	run.roster_state.item_instances = [
		ForgeEquipmentTestFixture.item(component_a, ForgeEquipmentTestFixture.COMPONENT_BETA),
		ForgeEquipmentTestFixture.item(component_b, ForgeEquipmentTestFixture.COMPONENT_BETA),
	]
	run.roster_state.inventory_item_instance_ids = [component_a, component_b]
	var before_item_count := run.roster_state.item_instances.size()
	var before_serial := run.next_item_serial.deep_clone()

	# beta+beta has no registered recipe in forge_table() (only alpha+alpha and
	# alpha+beta are registered) -- must be rejected, not silently no-op crafted.
	var result := ForgeEquipmentCommand.new(component_a, component_b, table).apply_to(run)
	assert_false(result.ok)
	assert_eq(
		EquipDismantleTestFixture.error_source_code(result), "FORGE_EQUIPMENT_RECIPE_NOT_FOUND"
	)
	assert_eq(run.roster_state.item_instances.size(), before_item_count)
	assert_not_null(ForgeEquipmentTestFixture.find_item(run, component_a))
	assert_not_null(ForgeEquipmentTestFixture.find_item(run, component_b))
	assert_true(run.roster_state.inventory_item_instance_ids.has(component_a))
	assert_true(run.roster_state.inventory_item_instance_ids.has(component_b))
	assert_eq(run.next_item_serial.to_hex(), before_serial.to_hex())

func test_forge_rejects_component_not_in_inventory_and_leaves_state_unchanged() -> void:
	var run := ForgeEquipmentTestFixture.base_run()
	var table := ForgeEquipmentTestFixture.forge_table()
	var component_a := ForgeEquipmentTestFixture.item_id(1)
	var bound_elsewhere := ForgeEquipmentTestFixture.item_id(2)
	run.roster_state.item_instances = [
		ForgeEquipmentTestFixture.item(component_a, ForgeEquipmentTestFixture.COMPONENT_ALPHA),
		# present in item_instances but bound elsewhere (not sitting in inventory) --
		# must never be treated as an available forge input.
		ForgeEquipmentTestFixture.item(
			bound_elsewhere, ForgeEquipmentTestFixture.COMPONENT_ALPHA, "u_0000000000000001"
		),
	]
	run.roster_state.inventory_item_instance_ids = [component_a]
	var before_item_count := run.roster_state.item_instances.size()

	var missing_id := ForgeEquipmentTestFixture.item_id(99)
	var result_missing := ForgeEquipmentCommand.new(component_a, missing_id, table).apply_to(run)
	assert_false(result_missing.ok)
	assert_eq(
		EquipDismantleTestFixture.error_source_code(result_missing),
		"FORGE_EQUIPMENT_COMPONENT_NOT_IN_INVENTORY"
	)
	assert_eq(run.roster_state.item_instances.size(), before_item_count)
	assert_true(run.roster_state.inventory_item_instance_ids.has(component_a))

	var result_bound := ForgeEquipmentCommand.new(
		component_a, bound_elsewhere, table
	).apply_to(run)
	assert_false(result_bound.ok)
	assert_eq(
		EquipDismantleTestFixture.error_source_code(result_bound),
		"FORGE_EQUIPMENT_COMPONENT_NOT_IN_INVENTORY"
	)
	assert_eq(run.roster_state.item_instances.size(), before_item_count)
	assert_not_null(ForgeEquipmentTestFixture.find_item(run, bound_elsewhere))
	assert_not_null(ForgeEquipmentTestFixture.find_item(run, bound_elsewhere).bound_unit_instance_id)
	assert_true(run.roster_state.inventory_item_instance_ids.has(component_a))

func test_forge_rejects_duplicate_instance_id_for_both_slots_and_leaves_state_unchanged() -> void:
	# Passing the same instance id for both slots must never be treated as "two
	# components" -- a single inventory item cannot be consumed twice, even
	# when its def_id would otherwise satisfy a self-pair recipe.
	var run := ForgeEquipmentTestFixture.base_run()
	var table := ForgeEquipmentTestFixture.forge_table()
	var component_a := ForgeEquipmentTestFixture.item_id(1)
	run.roster_state.item_instances = [
		ForgeEquipmentTestFixture.item(component_a, ForgeEquipmentTestFixture.COMPONENT_ALPHA),
	]
	run.roster_state.inventory_item_instance_ids = [component_a]

	var result := ForgeEquipmentCommand.new(component_a, component_a, table).apply_to(run)
	assert_false(result.ok)
	assert_eq(
		EquipDismantleTestFixture.error_source_code(result), "FORGE_EQUIPMENT_DUPLICATE_INSTANCE"
	)
	assert_eq(run.roster_state.item_instances.size(), 1)
	assert_not_null(ForgeEquipmentTestFixture.find_item(run, component_a))
	assert_true(run.roster_state.inventory_item_instance_ids.has(component_a))

func test_forge_sends_new_equipment_to_overflow_when_inventory_is_full() -> void:
	var run := ForgeEquipmentTestFixture.base_run()
	var table := ForgeEquipmentTestFixture.forge_table()
	var component_a := ForgeEquipmentTestFixture.item_id(1)
	var component_b := ForgeEquipmentTestFixture.item_id(2)
	var items: Array[ItemInstanceState] = [
		ForgeEquipmentTestFixture.item(component_a, ForgeEquipmentTestFixture.COMPONENT_ALPHA),
		ForgeEquipmentTestFixture.item(component_b, ForgeEquipmentTestFixture.COMPONENT_BETA),
	]
	var inventory_ids: Array[String] = [component_a, component_b]
	for index: int in range(16):
		var filler_id := ForgeEquipmentTestFixture.item_id(index + 100)
		items.append(ForgeEquipmentTestFixture.item(filler_id, ForgeEquipmentTestFixture.EQUIPMENT_ALPHA_ALPHA))
		inventory_ids.append(filler_id)
	run.roster_state.item_instances = items
	run.roster_state.inventory_item_instance_ids = inventory_ids

	var result := ForgeEquipmentCommand.new(component_a, component_b, table).apply_to(run)
	assert_true(result.ok, EquipDismantleTestFixture.error_source_code(result))
	if not result.ok: return

	# the 16 pre-existing filler instances are untouched aside from the two
	# consumed components being removed; the forged instance overflows instead
	# of silently displacing an existing inventory slot.
	assert_eq(result.draft.roster_state.inventory_item_instance_ids.size(), 16)
	assert_eq(result.draft.roster_state.pending_item_overflow.size(), 1)
	var forged_id: String = result.draft.roster_state.pending_item_overflow[0]
	assert_false(result.draft.roster_state.inventory_item_instance_ids.has(forged_id))
	var forged := ForgeEquipmentTestFixture.find_item(result.draft, forged_id)
	assert_not_null(forged)
	assert_eq(forged.def_id, ForgeEquipmentTestFixture.EQUIPMENT_ALPHA_BETA)

func test_forge_rejects_stale_catalog_generation_and_leaves_state_unchanged() -> void:
	# mirrors equip_item_command.gd's generation-mismatch guard: a
	# ForgeRecipeTable pinned to a different manifest generation than the
	# draft's content_snapshot must be rejected before any consumption.
	var run := ForgeEquipmentTestFixture.base_run()
	var stale_table := ForgeEquipmentTestFixture.forge_table(
		"9999999999999999999999999999999999999999999999999999999999999999"
	)
	var component_a := ForgeEquipmentTestFixture.item_id(1)
	var component_b := ForgeEquipmentTestFixture.item_id(2)
	run.roster_state.item_instances = [
		ForgeEquipmentTestFixture.item(component_a, ForgeEquipmentTestFixture.COMPONENT_ALPHA),
		ForgeEquipmentTestFixture.item(component_b, ForgeEquipmentTestFixture.COMPONENT_BETA),
	]
	run.roster_state.inventory_item_instance_ids = [component_a, component_b]
	var before_serial := run.next_item_serial.deep_clone()

	var result := ForgeEquipmentCommand.new(component_a, component_b, stale_table).apply_to(run)
	assert_false(result.ok)
	assert_eq(
		EquipDismantleTestFixture.error_source_code(result),
		"FORGE_EQUIPMENT_CATALOG_GENERATION_MISMATCH"
	)
	assert_eq(run.roster_state.item_instances.size(), 2)
	assert_not_null(ForgeEquipmentTestFixture.find_item(run, component_a))
	assert_not_null(ForgeEquipmentTestFixture.find_item(run, component_b))
	assert_true(run.roster_state.inventory_item_instance_ids.has(component_a))
	assert_true(run.roster_state.inventory_item_instance_ids.has(component_b))
	assert_eq(run.next_item_serial.to_hex(), before_serial.to_hex())
