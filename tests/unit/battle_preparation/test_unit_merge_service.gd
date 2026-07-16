extends GutTest

func test_nine_one_star_units_chain_to_one_three_star_and_conserve_copies() -> void:
	var units: Array[UnitInstance] = []
	var placements: Array[BoardPlacementState] = []
	var bench: Array[String] = []
	for index: int in range(9):
		var instance_id := "u_%016x" % (index + 1)
		units.append(_unit(instance_id, 1, 9 - index, []))
		if index < 4:
			placements.append(BoardPlacementState.new(0, index, instance_id))
		else:
			bench.append(instance_id)
	var roster := _roster(placements, bench, units, [])
	var result := UnitMergeService.new().merge_all(roster, _catalog([]))
	assert_true(result.ok)
	assert_eq(result.merge_count, 4)
	assert_eq(result.roster.unit_instances.size(), 1)
	assert_eq(result.roster.unit_instances[0].star, 3)
	assert_eq(result.roster.unit_instances[0].instance_id, "u_0000000000000001")
	assert_eq(result.roster.unit_instances[0].acquired_serial.to_hex(), "0000000000000001")
	assert_eq(result.copy_ledger.size(), 1)
	assert_eq(result.copy_ledger[0].weighted_copies, 9)
	assert_eq(roster.unit_instances.size(), 9, "service must not mutate input roster")

func test_equipment_moves_by_consumed_unit_and_slot_with_inventory_overflow() -> void:
	var unique_rule := _equipment_rule(&"equipment.unique", &"unique.test")
	var plain_rule := _equipment_rule(&"equipment.plain", &"")
	var equipment_rules: Array[BattleEquipmentRule] = [unique_rule, plain_rule]
	var primary_equipment: Array[String] = ["it_0000000000000001", "it_0000000000000002"]
	var consumed_a_equipment: Array[String] = ["it_0000000000000003", "it_0000000000000004"]
	var consumed_b_equipment: Array[String] = ["it_0000000000000005"]
	var units: Array[UnitInstance] = [
		_unit("u_0000000000000001", 1, 3, primary_equipment),
		_unit("u_0000000000000002", 1, 2, consumed_a_equipment),
		_unit("u_0000000000000003", 1, 1, consumed_b_equipment),
	]
	var placements: Array[BoardPlacementState] = [
		BoardPlacementState.new(0, 0, units[0].instance_id),
	]
	var bench: Array[String] = [units[1].instance_id, units[2].instance_id]
	var items: Array[ItemInstanceState] = [
		_item(primary_equipment[0], &"equipment.unique", units[0].instance_id, 1),
		_item(primary_equipment[1], &"equipment.plain", units[0].instance_id, 2),
		_item(consumed_a_equipment[0], &"equipment.unique", units[1].instance_id, 3),
		_item(consumed_a_equipment[1], &"equipment.plain", units[1].instance_id, 4),
		_item(consumed_b_equipment[0], &"equipment.plain", units[2].instance_id, 5),
	]
	var roster := _roster(placements, bench, units, items)
	var result := UnitMergeService.new(1).merge_all(roster, _catalog(equipment_rules))
	assert_true(result.ok)
	assert_eq(result.roster.unit_instances.size(), 1)
	var merged := result.roster.unit_instances[0]
	assert_eq(merged.star, 2)
	assert_eq(merged.acquired_serial.to_hex(), "0000000000000001")
	assert_eq(merged.equipment_instance_ids, [
		"it_0000000000000001",
		"it_0000000000000002",
		"it_0000000000000004",
	])
	assert_eq(result.roster.inventory_item_instance_ids, ["it_0000000000000003"])
	assert_eq(result.roster.pending_item_overflow, ["it_0000000000000005"])
	assert_eq(_find_item(result.roster, "it_0000000000000004").bound_unit_instance_id.value, merged.instance_id)
	assert_null(_find_item(result.roster, "it_0000000000000003").bound_unit_instance_id)
	assert_null(_find_item(result.roster, "it_0000000000000005").bound_unit_instance_id)

func test_board_presence_then_cell_order_choose_primary_before_instance_id() -> void:
	var no_equipment: Array[String] = []
	var units: Array[UnitInstance] = [
		_unit("u_0000000000000001", 1, 1, no_equipment),
		_unit("u_0000000000000002", 1, 2, no_equipment),
		_unit("u_0000000000000003", 1, 3, no_equipment),
	]
	var placements: Array[BoardPlacementState] = [
		BoardPlacementState.new(0, 1, units[1].instance_id),
		BoardPlacementState.new(0, 0, units[2].instance_id),
	]
	var bench: Array[String] = [units[0].instance_id]
	var no_items: Array[ItemInstanceState] = []
	var no_rules: Array[BattleEquipmentRule] = []
	var result := UnitMergeService.new().merge_all(
		_roster(placements, bench, units, no_items),
		_catalog(no_rules)
	)
	assert_true(result.ok)
	assert_eq(result.roster.unit_instances.size(), 1)
	assert_eq(result.roster.unit_instances[0].instance_id, units[2].instance_id)
	assert_eq(result.roster.unit_instances[0].acquired_serial.to_hex(), "0000000000000001")

func test_bench_order_chooses_primary_before_instance_id() -> void:
	var no_equipment: Array[String] = []
	var units: Array[UnitInstance] = [
		_unit("u_0000000000000001", 1, 1, no_equipment),
		_unit("u_0000000000000002", 1, 2, no_equipment),
		_unit("u_0000000000000003", 1, 3, no_equipment),
	]
	var no_placements: Array[BoardPlacementState] = []
	var bench: Array[String] = [
		units[2].instance_id,
		units[1].instance_id,
		units[0].instance_id,
	]
	var no_items: Array[ItemInstanceState] = []
	var no_rules: Array[BattleEquipmentRule] = []
	var result := UnitMergeService.new().merge_all(
		_roster(no_placements, bench, units, no_items),
		_catalog(no_rules)
	)
	assert_true(result.ok)
	assert_eq(result.roster.unit_instances[0].instance_id, units[2].instance_id)

func test_duplicate_or_unlocated_item_instances_are_rejected() -> void:
	var equipment_ids: Array[String] = ["it_0000000000000001"]
	var unit := _unit("u_0000000000000001", 1, 1, equipment_ids)
	var units: Array[UnitInstance] = [unit]
	var placements: Array[BoardPlacementState] = [
		BoardPlacementState.new(0, 0, unit.instance_id),
	]
	var no_bench: Array[String] = []
	var duplicate_items: Array[ItemInstanceState] = [
		_item(equipment_ids[0], &"equipment.plain", unit.instance_id, 1),
		_item(equipment_ids[0], &"equipment.plain", unit.instance_id, 2),
	]
	var rules: Array[BattleEquipmentRule] = [
		_equipment_rule(&"equipment.plain", &""),
	]
	var duplicate_result := UnitMergeService.new().merge_all(
		_roster(placements, no_bench, units, duplicate_items),
		_catalog(rules)
	)
	assert_false(duplicate_result.ok)
	assert_eq(duplicate_result.error.code, UnitMergeError.ITEM_CONSERVATION)

	var no_equipment: Array[String] = []
	units = [_unit("u_0000000000000001", 1, 1, no_equipment)]
	var unlocated_items: Array[ItemInstanceState] = [
		ItemInstanceState.new(
			"it_0000000000000002",
			&"equipment.plain",
			null,
			U64Bits.from_hex("0000000000000002").value
		),
	]
	var unlocated_result := UnitMergeService.new().merge_all(
		_roster(placements, no_bench, units, unlocated_items),
		_catalog(rules)
	)
	assert_false(unlocated_result.ok)
	assert_eq(unlocated_result.error.code, UnitMergeError.ITEM_CONSERVATION)

func test_malformed_null_entry_returns_typed_failure_before_clone() -> void:
	var no_placements: Array[BoardPlacementState] = []
	var no_bench: Array[String] = []
	var no_units: Array[UnitInstance] = []
	var no_items: Array[ItemInstanceState] = []
	var roster := _roster(no_placements, no_bench, no_units, no_items)
	roster.unit_instances.append(null)
	var no_rules: Array[BattleEquipmentRule] = []
	var result := UnitMergeService.new().merge_all(roster, _catalog(no_rules))
	assert_false(result.ok)
	assert_eq(result.error.code, UnitMergeError.INVALID_INPUT)

func _catalog(equipment: Array[BattleEquipmentRule]) -> BattleRuleCatalog:
	var units: Array[BattleUnitRule] = []
	var traits: Array[BattleTraitRule] = []
	var abilities: Array[BattleAbilityRule] = []
	var effects: Array[BattleEffectRule] = []
	var encounters: Array[BattleEncounterRule] = []
	var configs: Array[BattleCombatConfigRule] = []
	return BattleRuleCatalog.new(
		"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
		units, traits, abilities, effects, encounters, equipment, configs
	)

func _equipment_rule(equipment_id: StringName, unique_group: StringName) -> BattleEquipmentRule:
	var rule := BattleEquipmentRule.new()
	rule.equipment_id = equipment_id
	rule.unique_group = OptionalStringNameValue.of(unique_group) if not unique_group.is_empty() else null
	return rule

func _unit(
	instance_id: String,
	star: int,
	serial: int,
	equipment: Array[String]
) -> UnitInstance:
	return UnitInstance.new(
		instance_id,
		&"unit.fixture",
		star,
		equipment,
		U64Bits.from_hex("%016x" % serial).value
	)

func _item(
	instance_id: String,
	def_id: StringName,
	owner_id: String,
	serial: int
) -> ItemInstanceState:
	return ItemInstanceState.new(
		instance_id,
		def_id,
		OptionalStringValue.new(owner_id),
		U64Bits.from_hex("%016x" % serial).value
	)

func _roster(
	placements: Array[BoardPlacementState],
	bench: Array[String],
	units: Array[UnitInstance],
	items: Array[ItemInstanceState]
) -> RosterState:
	var inventory: Array[String] = []
	var overflow: Array[String] = []
	var relics: Array[RelicSlotState] = []
	for index: int in range(5):
		relics.append(RelicSlotState.new(index, null))
	return RosterState.new(
		BoardState.new(placements), bench, units, items, inventory, overflow, relics
	)

func _find_item(roster: RosterState, instance_id: String) -> ItemInstanceState:
	for item: ItemInstanceState in roster.item_instances:
		if item.instance_id == instance_id:
			return item
	return null
