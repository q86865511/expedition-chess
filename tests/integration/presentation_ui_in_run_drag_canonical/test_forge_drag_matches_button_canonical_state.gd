extends GutTest

const R14Support = preload(
	"res://tests/integration/presentation_ui_r14_functional_controls/"
	+ "r14_functional_controls_test_support.gd"
)
const EVIDENCE_PATH := (
	"res://specs/in-run-hud/evidence/p8-batch2/t20-forge-recipe-preview.png"
)


func test_forge_drag_matches_button_full_canonical_run_state() -> void:
	var button_fixture := _fresh_forge_fixture()
	assert_true(bool(button_fixture.get("ok", false)))
	if not bool(button_fixture.get("ok", false)):
		return
	var button_before := _run_json(
		(button_fixture["run_session"] as RunSession).run_snapshot()
	)
	var button_screen := button_fixture["screen"] as ProductionScreen
	var button_composition := button_fixture["composition"] as RunPrepareScreen
	var button_inventory := button_composition.find_child(
		"InventorySelector", true, false
	) as ItemList
	_select_inventory_pair(button_inventory)
	var begin_button := _action_button(button_screen, &"prepare.forge")
	var confirm_button := _action_button(
		button_screen, &"prepare.forge.confirm"
	)
	assert_not_null(begin_button)
	assert_not_null(confirm_button)
	if begin_button == null or confirm_button == null:
		return
	begin_button.pressed.emit()
	await wait_process_frames(2)
	assert_true(button_composition.has_pending_forge_confirmation())
	assert_eq(
		_run_json((button_fixture["run_session"] as RunSession).run_snapshot()),
		button_before,
		"prepare.forge must remain a zero-mutation confirmation draft"
	)
	confirm_button.pressed.emit()
	await wait_process_frames(3)
	var button_run := _loaded_run(button_fixture["repository"] as SaveRepository)
	assert_not_null(button_run)
	if button_run == null:
		return

	var drag_fixture := _fresh_forge_fixture()
	assert_true(bool(drag_fixture.get("ok", false)))
	if not bool(drag_fixture.get("ok", false)):
		return
	var drag_before := _run_json(
		(drag_fixture["run_session"] as RunSession).run_snapshot()
	)
	assert_eq(drag_before, button_before)
	var drag_screen := drag_fixture["screen"] as ProductionScreen
	var drag_composition := drag_fixture["composition"] as RunPrepareScreen
	var drag_inventory := drag_composition.find_child(
		"InventorySelector", true, false
	) as PrepareEquipmentDragList
	assert_not_null(drag_inventory)
	if drag_inventory == null:
		return
	var alpha_index := _item_index_for(drag_inventory, "component_alpha")
	var beta_index := _item_index_for(drag_inventory, "component_beta")
	assert_gte(alpha_index, 0)
	assert_gte(beta_index, 0)
	if alpha_index < 0 or beta_index < 0:
		return
	var payload := drag_inventory.item_drag_payload(alpha_index)
	assert_true(bool(payload.get("is_component", false)))
	assert_not_null(
		(drag_fixture["session"] as RunPresentationSession)
			.try_forge_pair_recipe("component_alpha", "component_beta")
	)
	assert_true(drag_inventory.can_drop_pair_at_index(beta_index, payload))
	var preview := drag_composition.find_child(
		"ForgeRecipePreview", true, false
	) as Label
	assert_not_null(preview)
	if preview == null:
		return
	assert_eq(preview.get_meta(&"forge_preview_state", &""), &"valid")
	assert_eq(
		preview.get_meta(&"result_equipment_id", &""),
		ForgeEquipmentTestFixture.EQUIPMENT_ALPHA_BETA
	)
	assert_true(preview.text.contains("→"))
	await wait_process_frames(2)
	var image: Image
	if DisplayServer.get_name() != "headless":
		image = get_viewport().get_texture().get_image()
	if image != null:
		assert_eq(image.save_png(
			ProjectSettings.globalize_path(EVIDENCE_PATH)
		), OK)
	drag_inventory.drop_pair_at_index(beta_index, payload)
	await wait_process_frames(2)
	assert_true(drag_composition.has_pending_forge_confirmation())
	assert_eq(
		_run_json((drag_fixture["run_session"] as RunSession).run_snapshot()),
		drag_before,
		"a valid drop must still wait for exactly one explicit confirmation"
	)
	var drag_confirm := _action_button(
		drag_screen, &"prepare.forge.confirm"
	)
	assert_not_null(drag_confirm)
	if drag_confirm == null:
		return
	drag_confirm.pressed.emit()
	await wait_process_frames(3)
	var drag_run := _loaded_run(drag_fixture["repository"] as SaveRepository)
	assert_not_null(drag_run)
	if drag_run == null:
		return

	assert_eq(
		_run_json(drag_run),
		_run_json(button_run),
		"drag and existing button paths must converge on the complete RunState"
	)
	assert_eq(
		drag_run.roster_state.inventory_item_instance_ids,
		button_run.roster_state.inventory_item_instance_ids
	)
	assert_eq(
		drag_run.roster_state.pending_item_overflow,
		button_run.roster_state.pending_item_overflow
	)
	assert_eq(drag_run.roster_state.inventory_item_instance_ids.size(), 1)
	assert_true(drag_run.roster_state.pending_item_overflow.is_empty())
	var forged := drag_run.roster_state.item_instances[0]
	assert_eq(forged.def_id, ForgeEquipmentTestFixture.EQUIPMENT_ALPHA_BETA)


func _fresh_forge_fixture() -> Dictionary:
	var run := ForgeEquipmentTestFixture.base_run()
	var alpha := ForgeEquipmentTestFixture.item(
		"component_alpha", ForgeEquipmentTestFixture.COMPONENT_ALPHA, "", 1
	)
	var beta := ForgeEquipmentTestFixture.item(
		"component_beta", ForgeEquipmentTestFixture.COMPONENT_BETA, "", 2
	)
	run.roster_state.item_instances.assign([alpha, beta])
	run.roster_state.inventory_item_instance_ids.assign([
		alpha.instance_id, beta.instance_id,
	])
	run.roster_state.pending_item_overflow.clear()
	run.next_item_serial = U64Bits.from_u32(0, 3).value
	var digest := run.content_snapshot.manifest_digest_value()
	var battle_catalog := EquipDismantleTestFixture.battle_catalog(digest)
	var storage := FakeSaveStorage.new()
	var repository := ForgeEquipmentTestFixture.repository_for(storage)
	add_child_autofree(repository)
	var profile := SaveRootFixture.create_valid_root().profile
	var run_session := RunSession.new(
		profile, run, TestCatalogLease.new(digest)
	)
	var controller := RunController.new(
		run_session,
		repository,
		RunStateValidator.new(),
		RunSaveRootFactory.new("0.2.0", FixedRunCommitClock.new()),
		battle_catalog
	)
	var economy_catalog := EconomyTestFixture.catalog(digest)
	var empty_relic_rules: Array[RunRelicRule] = []
	var relic_table := RunRelicTable.new(digest, empty_relic_rules)
	var forge_table := ForgeEquipmentTestFixture.forge_table(digest)
	var passive_effect_ids: Array[StringName] = []
	var factory := RunCommandFactory.new(
		economy_catalog,
		relic_table,
		battle_catalog,
		passive_effect_ids,
		run.commander_id,
		0,
		forge_table
	)
	var session := RunPresentationSession.new(
		controller,
		factory,
		battle_catalog,
		passive_effect_ids,
		null,
		run_session,
		forge_table,
		economy_catalog,
		relic_table
	)
	if not session.is_concrete():
		return {"ok": false}
	var screen := R14Support.live_run_screen(
		self, &"RUN_PREPARE", session.snapshot(), session
	)
	var composition := screen.get_node_or_null(^"Composition") as RunPrepareScreen
	return {
		"ok": screen != null and composition != null,
		"screen": screen,
		"composition": composition,
		"run_session": run_session,
		"session": session,
		"repository": repository,
	}


func _select_inventory_pair(inventory: ItemList) -> void:
	inventory.deselect_all()
	for item_id: String in ["component_alpha", "component_beta"]:
		var index := _item_index_for(inventory, item_id)
		assert_gte(index, 0)
		if index >= 0:
			inventory.select(index, false)


func _item_index_for(inventory: ItemList, item_id: String) -> int:
	if inventory == null:
		return -1
	for index: int in inventory.item_count:
		if String(inventory.get_item_metadata(index)) == item_id:
			return index
	return -1


func _action_button(
	screen: ProductionScreen, action_id: StringName
) -> Button:
	if screen == null:
		return null
	for node: Node in screen.find_children("*", "Button", true, false):
		var button := node as Button
		if (
			button != null
			and StringName(button.get_meta(&"action_id", &"")) == action_id
		):
			return button
	return null


func _loaded_run(repository: SaveRepository) -> RunState:
	var loaded := repository.load()
	return loaded.run.deep_clone() if loaded.ok and loaded.run != null else null


func _run_json(run: RunState) -> String:
	if run == null:
		return ""
	var codec := SaveJsonCodec.new(
		FakePinnedCatalogReceiptPort.new(
			ForgeEquipmentTestFixture.equipment_receipt()
		),
		FakeContentIdMigrationPort.new()
	)
	return String(codec.call(&"_encode_run", run))
