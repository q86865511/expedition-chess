extends GutTest

## T10 / S4-AC-013 (specs/build-systems/design.md §8, HANDOFF.md §2) --
## ForgeViewModel (presentation/viewmodels/forge_view_model.gd, currently does
## not exist).
##
## Expected contract (test-author decision -- see
## tests/fixtures/build_systems/view_model_test_fixture.gd header):
##   class_name ForgeViewModel extends RefCounted
##   func _init(controller: RunController, forge_table: ForgeRecipeTable) -> void
##   func inventory_components() -> Array[ItemInstanceState]
##   func recipe_preview(component_id: StringName) -> Array[ForgeRecipeRule]
##   func forge(component_instance_id_a: String, component_instance_id_b: String) -> CommandResult
## `forge()` must dispatch a real `ForgeEquipmentCommand` through
## `RunController.dispatch()` (design §8: "寫端一律經 command"), not call
## `apply_to()` directly, so a commit/storage failure is proven to leave the
## canonical inventory untouched too (mirrors
## tests/integration/build_items/test_forge_equipment_command_transaction.gd).
##
## Reuses ForgeEquipmentTestFixture (tests/fixtures/build_items/) verbatim for
## its already-pinned catalog/receipt/recipe table instead of duplicating a
## second forge fixture.

func test_inventory_components_reflects_roster_snapshot_and_is_isolated_from_domain() -> void:
	var run := ForgeEquipmentTestFixture.base_run()
	var component_a := ForgeEquipmentTestFixture.item_id(1)
	var component_b := ForgeEquipmentTestFixture.item_id(2)
	run.roster_state.item_instances = [
		ForgeEquipmentTestFixture.item(component_a, ForgeEquipmentTestFixture.COMPONENT_ALPHA),
		ForgeEquipmentTestFixture.item(component_b, ForgeEquipmentTestFixture.COMPONENT_BETA),
	]
	run.roster_state.inventory_item_instance_ids = [component_a, component_b]
	var controller := _controller_for(run)
	var table := ForgeEquipmentTestFixture.forge_table()
	var view_model := ForgeViewModel.new(controller, table)

	var components := view_model.inventory_components()
	assert_eq(components.size(), 2, "只應回傳 inventory 中的零件,不含板凳/未在庫存中的物品")
	var ids: Array = []
	for item: ItemInstanceState in components:
		ids.append(item.instance_id)
	assert_true(ids.has(component_a))
	assert_true(ids.has(component_b))

	# 契約測試（design §8）：改動回傳陣列中的物件不得影響 domain 或之後的讀取。
	components[0].def_id = &"item_component.mutated"
	var again := view_model.inventory_components()
	for item: ItemInstanceState in again:
		assert_ne(item.def_id, &"item_component.mutated")
	var roster_after := controller.roster_snapshot()
	for item: ItemInstanceState in roster_after.item_instances:
		assert_ne(item.def_id, &"item_component.mutated")

func test_recipe_preview_returns_recipes_containing_component() -> void:
	var run := ForgeEquipmentTestFixture.base_run()
	var controller := _controller_for(run)
	var table := ForgeEquipmentTestFixture.forge_table()
	var view_model := ForgeViewModel.new(controller, table)

	var previews := view_model.recipe_preview(ForgeEquipmentTestFixture.COMPONENT_ALPHA)
	assert_eq(previews.size(), 2, "alpha 同時出現在自配(alpha+alpha)與交叉配方(alpha+beta)中")
	var equipment_ids: Array = []
	for rule: ForgeRecipeRule in previews:
		equipment_ids.append(rule.equipment_id)
	assert_true(equipment_ids.has(ForgeEquipmentTestFixture.EQUIPMENT_ALPHA_ALPHA))
	assert_true(equipment_ids.has(ForgeEquipmentTestFixture.EQUIPMENT_ALPHA_BETA))

func test_forge_success_dispatches_command_and_commits_forged_equipment() -> void:
	var run := ForgeEquipmentTestFixture.base_run()
	var component_a := ForgeEquipmentTestFixture.item_id(1)
	var component_b := ForgeEquipmentTestFixture.item_id(2)
	run.roster_state.item_instances = [
		ForgeEquipmentTestFixture.item(component_a, ForgeEquipmentTestFixture.COMPONENT_ALPHA),
		ForgeEquipmentTestFixture.item(component_b, ForgeEquipmentTestFixture.COMPONENT_BETA),
	]
	run.roster_state.inventory_item_instance_ids = [component_a, component_b]
	var controller := _controller_for(run)
	var table := ForgeEquipmentTestFixture.forge_table()
	var view_model := ForgeViewModel.new(controller, table)

	var result := view_model.forge(component_a, component_b)
	assert_true(result.ok, ViewModelTestFixture.command_error_source_code(result))
	if not result.ok:
		return
	assert_eq(result.view_state.roster.inventory_item_instance_ids.size(), 1)
	assert_false(result.view_state.roster.inventory_item_instance_ids.has(component_a))
	assert_false(result.view_state.roster.inventory_item_instance_ids.has(component_b))
	# 交易確實走完整 RunController.dispatch() 管線(非僅 apply_to()) -- 讀端也應反映。
	var components_after := view_model.inventory_components()
	assert_eq(components_after.size(), 1)
	assert_eq(components_after[0].def_id, ForgeEquipmentTestFixture.EQUIPMENT_ALPHA_BETA)

func test_forge_missing_recipe_returns_named_error_and_leaves_inventory_unchanged() -> void:
	var run := ForgeEquipmentTestFixture.base_run()
	var component_a := ForgeEquipmentTestFixture.item_id(1)
	var component_b := ForgeEquipmentTestFixture.item_id(2)
	run.roster_state.item_instances = [
		ForgeEquipmentTestFixture.item(component_a, ForgeEquipmentTestFixture.COMPONENT_BETA),
		ForgeEquipmentTestFixture.item(component_b, ForgeEquipmentTestFixture.COMPONENT_BETA),
	]
	run.roster_state.inventory_item_instance_ids = [component_a, component_b]
	var controller := _controller_for(run)
	var table := ForgeEquipmentTestFixture.forge_table()
	var view_model := ForgeViewModel.new(controller, table)

	# beta+beta 無註冊配方 -- 必須回具名 error,且不消耗任何零件。
	var result := view_model.forge(component_a, component_b)
	assert_false(result.ok)
	assert_eq(
		ViewModelTestFixture.command_error_source_code(result),
		"FORGE_EQUIPMENT_RECIPE_NOT_FOUND"
	)
	var components_after := view_model.inventory_components()
	assert_eq(components_after.size(), 2)

func _controller_for(run: RunState) -> RunController:
	var storage := FakeSaveStorage.new()
	var repository := ForgeEquipmentTestFixture.repository_for(storage)
	add_child_autofree(repository)
	var battle_catalog := EquipDismantleTestFixture.battle_catalog(
		run.content_snapshot.manifest_digest_value()
	)
	return ViewModelTestFixture.controller_for(run, battle_catalog, repository)
