extends GutTest

## T01 (specs/build-systems) — ForgeRecipeTable。
## Covers：REQ-ITEM-001、S4-AC-004（21 配方封閉枚舉，任一零件可反查）。
## 依據 design.md §2/§3「新增 ForgeRecipeTable（component_pair -> equipment_id, 21 closed）」。
## SyntheticContentFixture.build_valid() 本身即含 6 零件 x 21 配方（無序配對含自配）的內容，
## 故直接沿用其既有配方形狀，不另造內容。
## 慣例沿用 domain/run/economy/economy_expedition_catalog_builder.gd 的
## build(registry, manifest_digest, ids...) -> XxxBuildResult{ok, table/catalog, error} 慣例。

func test_forge_recipe_table_builder_produces_21_closed_recipes_with_symmetric_lookup() -> void:
	var registry := ContentRegistryService.new()
	add_child_autofree(registry)
	var fixture := SyntheticContentFixture.build_valid()
	var installed := registry.install_validated(fixture, "fixture.forge.1", [&"pack.core"])
	assert_true(installed.ok)
	if not installed.ok:
		return
	var equipment_ids := _all_equipment_ids()
	var built := ForgeRecipeTableBuilder.new().build(registry, installed.handle.manifest_digest, equipment_ids)
	assert_true(built.ok, "forge recipe table should decode from the pinned generation")
	if not built.ok:
		return
	assert_eq(built.table.manifest_digest_value(), installed.handle.manifest_digest)
	assert_eq(built.table.recipe_count(), 21, "6 components with self-pairing must close over exactly 21 recipes")
	for left in 6:
		for right in range(left, 6):
			var expected_id := StringName("equipment.c%d_c%d" % [left, right])
			var component_a := StringName("item_component.c%d" % left)
			var component_b := StringName("item_component.c%d" % right)
			var forward := built.table.try_recipe(component_a, component_b)
			var backward := built.table.try_recipe(component_b, component_a)
			assert_not_null(forward, "pair (%s,%s) must resolve" % [component_a, component_b])
			assert_not_null(backward, "reversed query order for an unordered pair must resolve identically")
			if forward != null:
				assert_eq(forward.equipment_id, expected_id)
			if backward != null:
				assert_eq(backward.equipment_id, expected_id)

func test_forge_recipe_table_reverse_lookup_by_component_returns_all_six_recipes() -> void:
	var registry := ContentRegistryService.new()
	add_child_autofree(registry)
	var fixture := SyntheticContentFixture.build_valid()
	var installed := registry.install_validated(fixture, "fixture.forge.2", [&"pack.core"])
	assert_true(installed.ok)
	if not installed.ok:
		return
	var built := ForgeRecipeTableBuilder.new().build(
		registry, installed.handle.manifest_digest, _all_equipment_ids()
	)
	assert_true(built.ok)
	if not built.ok:
		return
	for index in 6:
		var component_id := StringName("item_component.c%d" % index)
		var recipes: Array[ForgeRecipeRule] = built.table.recipes_containing(component_id)
		assert_eq(
			recipes.size(), 6,
			"每個零件應恰參與 6 個配方（含自配）：%s" % component_id
		)
		var found_equipment_ids: Array[StringName] = []
		for recipe: ForgeRecipeRule in recipes:
			found_equipment_ids.append(recipe.equipment_id)
			assert_true(
				recipe.component_ids.has(component_id),
				"reverse lookup must only return recipes that actually contain the component"
			)
		var expected_id := StringName("equipment.c%d_c%d" % [index, index])
		assert_true(found_equipment_ids.has(expected_id), "self-pair recipe must be included in reverse lookup")

func test_forge_recipe_table_builder_rejects_non_equipment_content_id() -> void:
	var registry := ContentRegistryService.new()
	add_child_autofree(registry)
	var fixture := SyntheticContentFixture.build_valid()
	var installed := registry.install_validated(fixture, "fixture.forge.3", [&"pack.core"])
	assert_true(installed.ok)
	if not installed.ok:
		return
	var equipment_ids_with_bad_entry := _all_equipment_ids()
	equipment_ids_with_bad_entry.append(&"item_component.c0")
	var built := ForgeRecipeTableBuilder.new().build(
		registry, installed.handle.manifest_digest, equipment_ids_with_bad_entry
	)
	assert_false(built.ok, "a non-equipment content id must not silently decode into a recipe")
	assert_eq(built.error.code, ForgeRecipeTableError.CATEGORY_MISMATCH)

func test_forge_recipe_table_only_resolves_from_pinned_manifest_digest() -> void:
	var registry := ContentRegistryService.new()
	add_child_autofree(registry)
	var fixture := SyntheticContentFixture.build_valid()
	var installed := registry.install_validated(fixture, "fixture.forge.4", [&"pack.core"])
	assert_true(installed.ok)
	if not installed.ok:
		return
	var equipment_ids := _all_equipment_ids()
	var wrong_digest := "f".repeat(64)
	var built := ForgeRecipeTableBuilder.new().build(registry, wrong_digest, equipment_ids)
	assert_false(built.ok, "forge recipe table must not fall through to the latest/unpinned generation")
	assert_eq(built.error.code, ForgeRecipeTableError.RESOLVE_FAILED)

func test_forge_recipe_table_deep_clone_isolated_from_lookup_mutation() -> void:
	var registry := ContentRegistryService.new()
	add_child_autofree(registry)
	var fixture := SyntheticContentFixture.build_valid()
	var installed := registry.install_validated(fixture, "fixture.forge.5", [&"pack.core"])
	assert_true(installed.ok)
	if not installed.ok:
		return
	var built := ForgeRecipeTableBuilder.new().build(
		registry, installed.handle.manifest_digest, _all_equipment_ids()
	)
	assert_true(built.ok)
	if not built.ok:
		return
	var component_zero := StringName("item_component.c0")
	var first := built.table.try_recipe(component_zero, component_zero)
	assert_not_null(first)
	if first == null:
		return
	first.component_ids.append(&"tampered")
	var second := built.table.try_recipe(component_zero, component_zero)
	assert_not_null(second)
	if second == null:
		return
	assert_eq(second.component_ids.size(), 1, "mutating a fetched recipe must not leak into the table's stored state")

func test_forge_recipe_table_builder_rejects_component_pair_outside_one_or_two_shape() -> void:
	# component_pair 的合法形狀是 1 個零件（自配,如 c0_c0）或 2 個零件（異配）——
	# ContentValidator._validate_recipes() 對合法內容授權時強制此界線,故此處以
	# _install_authoring_unchecked() 繞過驗證,模擬「已通過舊版較寬鬆規則的 legacy 內容」
	# 混入 3 個零件的退化情境,驗證 builder 本身的縱深防禦。
	var registry := ContentRegistryService.new()
	add_child_autofree(registry)
	var fixture := SyntheticContentFixture.build_valid()
	var malformed_equipment := _find(fixture, &"equipment.c0_c1") as EquipmentDef
	malformed_equipment.component_pair = [&"item_component.c0", &"item_component.c1", &"item_component.c2"]
	var installed := registry._install_authoring_unchecked(
		fixture.definitions, "fixture.forge.6", [&"pack.core"], fixture.aliases, fixture.tombstones, fixture
	)
	assert_true(installed.ok, "unchecked install should still compile a structurally well-formed record")
	if not installed.ok:
		return
	var built := ForgeRecipeTableBuilder.new().build(
		registry, installed.handle.manifest_digest, _all_equipment_ids()
	)
	assert_false(built.ok, "a component_pair outside the 1-2 shape must not silently decode into an unresolvable recipe")
	if built.ok:
		return
	assert_eq(built.error.code, ForgeRecipeTableError.PAYLOAD_INVALID)
	assert_eq(built.error.field_path, &"equipment.component_pair")

func _find(input: ContentValidationInput, content_id: StringName) -> ContentDefinition:
	for definition in input.definitions:
		if definition.id == content_id: return definition
	return null

func _all_equipment_ids() -> Array[StringName]:
	var result: Array[StringName] = []
	for left in 6:
		for right in range(left, 6):
			result.append(StringName("equipment.c%d_c%d" % [left, right]))
	return result
