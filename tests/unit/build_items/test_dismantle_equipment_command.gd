extends GutTest

## T04 / S4-AC-007 (DismantleEquipmentCommand): 消耗一個拆卸道具、同一交易解綁回
## inventory(滿則 overflow);任何驗證失敗不消耗道具;裝備搬移全程恰一實例.
##
## Contract under test (test-author decision -- see
## tests/fixtures/build_items/equip_dismantle_test_fixture.gd header: a
## "拆卸道具" is modeled as an ordinary unbound ItemInstanceState in inventory,
## reusing the existing schema per design.md §1's "no new persisted fields"
## commitment) whose def_id must resolve to a genuine dismantle ConsumableDef
## via a pinned ConsumableRuleTable:
##   DismantleEquipmentCommand.new(equipment_item_instance_id: String,
##     consumable_item_instance_id: String,
##     consumable_rules: ConsumableRuleTable) -> RunCommand
##   .apply_to(draft: RunState) -> CommandApplyResult

func test_dismantle_unbinds_equipment_and_consumes_exactly_one_consumable_instance() -> void:
	var run := EquipDismantleTestFixture.base_run(1)
	var target_unit_id := EquipDismantleTestFixture.unit_id(1)
	var equipment_id := EquipDismantleTestFixture.item_id(1)
	var consumable_id := EquipDismantleTestFixture.item_id(2)
	var equipment_item := EquipDismantleTestFixture.item(
		equipment_id, &"equipment.plain_a", target_unit_id
	)
	var consumable_item := EquipDismantleTestFixture.item(
		consumable_id, &"consumable.dismantle_kit"
	)
	run.roster_state.item_instances = [equipment_item, consumable_item]
	run.roster_state.inventory_item_instance_ids = [consumable_id]
	var unit := EquipDismantleTestFixture.find_unit(run, target_unit_id)
	unit.equipment_instance_ids = [equipment_id]

	var command := DismantleEquipmentCommand.new(
		equipment_id, consumable_id, EquipDismantleTestFixture.consumable_rules()
	)
	assert_true(command.is_concrete())
	var result := command.apply_to(run)
	assert_true(result.ok, EquipDismantleTestFixture.error_source_code(result))
	if not result.ok: return

	var resolved_unit := EquipDismantleTestFixture.find_unit(result.draft, target_unit_id)
	var no_equipment: Array[String] = []
	assert_eq(resolved_unit.equipment_instance_ids, no_equipment)
	var resolved_equipment := EquipDismantleTestFixture.find_item(result.draft, equipment_id)
	assert_not_null(resolved_equipment)
	assert_null(resolved_equipment.bound_unit_instance_id)
	assert_true(result.draft.roster_state.inventory_item_instance_ids.has(equipment_id))
	# consumable instance is fully consumed: no longer tracked anywhere.
	assert_null(EquipDismantleTestFixture.find_item(result.draft, consumable_id))
	assert_false(result.draft.roster_state.inventory_item_instance_ids.has(consumable_id))
	# exactly-once conservation: only the equipment instance survives.
	assert_eq(result.draft.roster_state.item_instances.size(), 1)

func test_dismantle_sends_recovered_equipment_to_overflow_when_inventory_is_full() -> void:
	var run := EquipDismantleTestFixture.base_run(1)
	var target_unit_id := EquipDismantleTestFixture.unit_id(1)
	var equipment_id := EquipDismantleTestFixture.item_id(1)
	var consumable_id := EquipDismantleTestFixture.item_id(2)
	var items: Array[ItemInstanceState] = [
		EquipDismantleTestFixture.item(equipment_id, &"equipment.plain_a", target_unit_id),
		EquipDismantleTestFixture.item(consumable_id, &"consumable.dismantle_kit"),
	]
	var inventory_ids: Array[String] = [consumable_id]
	for index: int in range(16):
		var filler_id := EquipDismantleTestFixture.item_id(index + 100)
		items.append(EquipDismantleTestFixture.item(filler_id, &"equipment.plain_b"))
		inventory_ids.append(filler_id)
	run.roster_state.item_instances = items
	run.roster_state.inventory_item_instance_ids = inventory_ids
	var unit := EquipDismantleTestFixture.find_unit(run, target_unit_id)
	unit.equipment_instance_ids = [equipment_id]
	var before_inventory_size := inventory_ids.size()

	var result := DismantleEquipmentCommand.new(
		equipment_id, consumable_id, EquipDismantleTestFixture.consumable_rules()
	).apply_to(run)
	assert_true(result.ok, EquipDismantleTestFixture.error_source_code(result))
	if not result.ok: return

	assert_true(result.draft.roster_state.pending_item_overflow.has(equipment_id))
	assert_false(result.draft.roster_state.inventory_item_instance_ids.has(equipment_id))
	# the 16 pre-existing inventory slots are untouched aside from the
	# consumed consumable instance being removed.
	assert_eq(result.draft.roster_state.inventory_item_instance_ids.size(), before_inventory_size - 1)
	assert_null(EquipDismantleTestFixture.find_item(result.draft, consumable_id))

func test_dismantle_rejects_unbound_target_and_does_not_consume_consumable() -> void:
	var run := EquipDismantleTestFixture.base_run(1)
	var loose_id := EquipDismantleTestFixture.item_id(1)
	var consumable_id := EquipDismantleTestFixture.item_id(2)
	var loose_item := EquipDismantleTestFixture.item(loose_id, &"equipment.plain_a")
	var consumable_item := EquipDismantleTestFixture.item(
		consumable_id, &"consumable.dismantle_kit"
	)
	run.roster_state.item_instances = [loose_item, consumable_item]
	run.roster_state.inventory_item_instance_ids = [loose_id, consumable_id]

	var result := DismantleEquipmentCommand.new(
		loose_id, consumable_id, EquipDismantleTestFixture.consumable_rules()
	).apply_to(run)
	assert_false(result.ok)
	assert_eq(
		EquipDismantleTestFixture.error_source_code(result),
		"DISMANTLE_EQUIPMENT_TARGET_NOT_BOUND"
	)
	# nothing consumed or mutated on the original draft.
	assert_true(run.roster_state.inventory_item_instance_ids.has(consumable_id))
	assert_not_null(EquipDismantleTestFixture.find_item(run, consumable_id))
	assert_eq(run.roster_state.item_instances.size(), 2)

func test_dismantle_rejects_missing_consumable_and_does_not_unbind_target() -> void:
	var run := EquipDismantleTestFixture.base_run(1)
	var target_unit_id := EquipDismantleTestFixture.unit_id(1)
	var equipment_id := EquipDismantleTestFixture.item_id(1)
	var missing_consumable_id := EquipDismantleTestFixture.item_id(2)
	var equipment_item := EquipDismantleTestFixture.item(
		equipment_id, &"equipment.plain_a", target_unit_id
	)
	run.roster_state.item_instances = [equipment_item]
	var unit := EquipDismantleTestFixture.find_unit(run, target_unit_id)
	unit.equipment_instance_ids = [equipment_id]
	var before_equipment := unit.equipment_instance_ids.duplicate()

	var result := DismantleEquipmentCommand.new(
		equipment_id, missing_consumable_id, EquipDismantleTestFixture.consumable_rules()
	).apply_to(run)
	assert_false(result.ok)
	assert_eq(
		EquipDismantleTestFixture.error_source_code(result),
		"DISMANTLE_EQUIPMENT_CONSUMABLE_UNAVAILABLE"
	)
	assert_eq(unit.equipment_instance_ids, before_equipment)
	var reloaded := EquipDismantleTestFixture.find_item(run, equipment_id)
	assert_not_null(reloaded.bound_unit_instance_id)
	assert_eq(reloaded.bound_unit_instance_id.value, target_unit_id)
	assert_eq(run.roster_state.item_instances.size(), 1)

func test_dismantle_rejects_non_dismantle_consumable_and_destroys_nothing() -> void:
	# F2 regression: an arbitrary unbound inventory item (here a non-dismantle
	# consumable) must never be accepted as the dismantle cost. The command must
	# reject on def_id kind and leave both the equipment binding and the passed
	# item fully intact.
	var run := EquipDismantleTestFixture.base_run(1)
	var target_unit_id := EquipDismantleTestFixture.unit_id(1)
	var equipment_id := EquipDismantleTestFixture.item_id(1)
	var impostor_id := EquipDismantleTestFixture.item_id(2)
	run.roster_state.item_instances = [
		EquipDismantleTestFixture.item(equipment_id, &"equipment.plain_a", target_unit_id),
		EquipDismantleTestFixture.item(impostor_id, &"consumable.non_dismantle"),
	]
	run.roster_state.inventory_item_instance_ids = [impostor_id]
	var unit := EquipDismantleTestFixture.find_unit(run, target_unit_id)
	unit.equipment_instance_ids = [equipment_id]
	var before_item_count := run.roster_state.item_instances.size()

	var result := DismantleEquipmentCommand.new(
		equipment_id, impostor_id, EquipDismantleTestFixture.consumable_rules()
	).apply_to(run)
	assert_false(result.ok)
	assert_eq(
		EquipDismantleTestFixture.error_source_code(result),
		"DISMANTLE_EQUIPMENT_CONSUMABLE_KIND"
	)
	# the impostor item is not consumed and the equipment stays bound.
	assert_eq(run.roster_state.item_instances.size(), before_item_count)
	assert_not_null(EquipDismantleTestFixture.find_item(run, impostor_id))
	assert_true(run.roster_state.inventory_item_instance_ids.has(impostor_id))
	assert_eq(unit.equipment_instance_ids, [equipment_id])
	var still_bound := EquipDismantleTestFixture.find_item(run, equipment_id)
	assert_not_null(still_bound.bound_unit_instance_id)
	assert_eq(still_bound.bound_unit_instance_id.value, target_unit_id)

func test_equip_then_dismantle_then_equip_again_preserves_single_item_instance() -> void:
	var run := EquipDismantleTestFixture.base_run(1)
	var catalog := EquipDismantleTestFixture.battle_catalog()
	var target_unit_id := EquipDismantleTestFixture.unit_id(1)
	var equipment_id := EquipDismantleTestFixture.item_id(1)
	var consumable_a_id := EquipDismantleTestFixture.item_id(2)
	var consumable_b_id := EquipDismantleTestFixture.item_id(3)
	run.roster_state.item_instances = [
		EquipDismantleTestFixture.item(equipment_id, &"equipment.plain_a"),
		EquipDismantleTestFixture.item(consumable_a_id, &"consumable.dismantle_kit"),
		EquipDismantleTestFixture.item(consumable_b_id, &"consumable.dismantle_kit"),
	]
	run.roster_state.inventory_item_instance_ids = [equipment_id, consumable_a_id, consumable_b_id]

	var equipped := EquipItemCommand.new(target_unit_id, equipment_id, catalog).apply_to(run)
	assert_true(equipped.ok, EquipDismantleTestFixture.error_source_code(equipped))
	if not equipped.ok: return
	var after_equip := equipped.draft

	var dismantled := DismantleEquipmentCommand.new(
		equipment_id, consumable_a_id, EquipDismantleTestFixture.consumable_rules()
	).apply_to(after_equip)
	assert_true(dismantled.ok, EquipDismantleTestFixture.error_source_code(dismantled))
	if not dismantled.ok: return
	var after_dismantle := dismantled.draft
	# exactly-once conservation across a full equip -> dismantle round trip:
	# only the original equipment instance and the still-unused consumable remain.
	assert_eq(after_dismantle.roster_state.item_instances.size(), 2)
	assert_not_null(EquipDismantleTestFixture.find_item(after_dismantle, equipment_id))

	var re_equipped := EquipItemCommand.new(
		target_unit_id, equipment_id, catalog
	).apply_to(after_dismantle)
	assert_true(re_equipped.ok, EquipDismantleTestFixture.error_source_code(re_equipped))
	if not re_equipped.ok: return
	assert_eq(re_equipped.draft.roster_state.item_instances.size(), 2)
	var final_item := EquipDismantleTestFixture.find_item(re_equipped.draft, equipment_id)
	assert_eq(final_item.instance_id, equipment_id)
	assert_eq(final_item.bound_unit_instance_id.value, target_unit_id)
