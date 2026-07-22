extends GutTest

## T04 / specs/build-systems/design.md §5: run_state_validator.gd 新增
## 「綁定物必為 EquipmentDef（零件不可綁定）」不變式.
##
## Contract under test (test-author decision): RunStateValidator.validate_run
## gains a 4th optional parameter `battle_catalog: BattleRuleCatalog = null`.
## When non-null, every bound ItemInstanceState's def_id must resolve via
## `battle_catalog.try_equipment_rule(def_id) != null` (i.e. be a real
## EquipmentDef, not an ItemComponentDef/other content). The parameter
## defaults to null so every pre-existing `validate_run(run, 1, 1)` call site
## across the test suite keeps compiling and passing unchanged.

func test_validate_run_accepts_bound_equipment_item_when_catalog_confirms_equipment_kind() -> void:
	var run := _valid_run_with_bound_item(&"equipment.plain_a")
	var catalog := EquipDismantleTestFixture.battle_catalog()
	var result := RunStateValidator.new().validate_run(run, 1, 1, catalog)
	assert_true(result.ok, String(result.error.field_path) if result.error != null else "none")

func test_validate_run_rejects_component_bound_as_equipment_when_catalog_provided() -> void:
	var run := _valid_run_with_bound_item(&"item_component.gem")
	var catalog := EquipDismantleTestFixture.battle_catalog()
	var result := RunStateValidator.new().validate_run(run, 1, 1, catalog)
	assert_false(result.ok)
	assert_eq(result.error.field_path, &"run.roster_state.item_instances.def_id")

func test_validate_run_without_catalog_argument_stays_backward_compatible() -> void:
	# A component bound as if it were equipment is a real invariant violation,
	# but only once a battle_catalog is supplied. Every existing call site in
	# this codebase invokes validate_run(run) / validate_run(run, 1, 1) with no
	# 4th argument, and must keep passing unchanged after this invariant lands.
	var run := _valid_run_with_bound_item(&"item_component.gem")
	var result := RunStateValidator.new().validate_run(run, 1, 1)
	assert_true(result.ok, String(result.error.field_path) if result.error != null else "none")

func _valid_run_with_bound_item(def_id: StringName) -> RunState:
	var run := SaveRootFixture.create_valid_root().run
	var item_id := "it_0000000000000001"
	var unit_id := "u_0000000000000001"
	var item := ItemInstanceState.new(
		item_id, def_id, OptionalStringValue.new(unit_id), U64Bits.one()
	)
	var equipped_ids: Array[String] = [item_id]
	var unit := UnitInstance.new(unit_id, &"unit.fixture", 1, equipped_ids, U64Bits.one())
	var placements: Array[BoardPlacementState] = [BoardPlacementState.new(0, 0, unit_id)]
	var no_bench: Array[String] = []
	run.roster_state.unit_instances = [unit]
	run.roster_state.board = BoardState.new(placements)
	run.roster_state.bench_unit_instance_ids = no_bench
	run.roster_state.item_instances = [item]
	var no_ids: Array[String] = []
	run.roster_state.inventory_item_instance_ids = no_ids
	run.roster_state.pending_item_overflow = no_ids
	var entries: Array[UnitPoolEntryState] = [
		UnitPoolEntryState.new(&"unit.fixture", 1, 0, 0, 1),
	]
	run.unit_pool_state = UnitPoolState.new(entries)
	return run
