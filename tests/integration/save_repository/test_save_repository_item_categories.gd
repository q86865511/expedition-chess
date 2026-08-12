extends GutTest

## 正式內容的 item def 分成 item_component(零件)／equipment(成品裝備)／consumable
## (消耗品)三種 category;persisted RunState.roster_state.item_instances.def_id 的遷移
## 閘門若只接受單一 &"item",玩家配裝後的第一次存檔就會在 SaveRepository read-back
## 被判 run incompatible(SAVE_TMP_READBACK_INVALID)。本檔用正式 receipt／migration
## port 走完整解碼路徑,鎖住「三種正式類別可存可讀、非 item 類別仍被擋」。

const _COMPONENT_INSTANCE_ID: String = "it_0000000000000a01"
const _EQUIPMENT_INSTANCE_ID: String = "it_0000000000000a02"
const _CONSUMABLE_INSTANCE_ID: String = "it_0000000000000a03"

func test_production_item_categories_survive_repository_save_and_load() -> void:
	var registry := _installed_registry()
	var pinned := registry.compile_pinned_generation(_selection())
	assert_true(pinned.ok)
	var def_ids: Array[StringName] = [
		&"item_component.c0", &"equipment.c0_c1", &"consumable.test",
	]
	for def_id: StringName in def_ids:
		assert_true(
			pinned.receipt.active_entry_ids.has(def_id),
			"pinned receipt must publish %s" % String(def_id)
		)
	var root := _root_with_items(pinned.receipt, def_ids)
	var repository := _repository(registry)
	var saved := repository.save(root)
	assert_true(saved.ok, "production item categories must survive the tmp read-back")
	var loaded := repository.load()
	assert_true(loaded.ok)
	assert_eq(loaded.run_status, LoadResult.RunStatus.LOADED)
	assert_not_null(loaded.run)
	var loaded_def_ids: Array[StringName] = []
	for item: ItemInstanceState in loaded.run.roster_state.item_instances:
		loaded_def_ids.append(item.def_id)
	assert_eq(loaded_def_ids, def_ids)

func test_item_def_id_of_a_non_item_category_is_still_rejected() -> void:
	var registry := _installed_registry()
	var pinned := registry.compile_pinned_generation(_selection())
	assert_true(pinned.ok)
	assert_true(pinned.receipt.active_entry_ids.has(&"unit.player_00"))
	var def_ids: Array[StringName] = [
		&"unit.player_00", &"equipment.c0_c1", &"consumable.test",
	]
	var root := _root_with_items(pinned.receipt, def_ids)
	var saved := _repository(registry).save(root)
	assert_false(saved.ok, "a unit def_id in an item slot must not decode")
	assert_eq(saved.error.code, SaveError.TMP_READBACK_INVALID)

func _installed_registry() -> ContentRegistryService:
	var registry := ContentRegistryService.new()
	add_child_autofree(registry)
	var installed := registry.install_validated(
		SyntheticContentFixture.build_valid(),
		"fixture.1",
		[&"pack.core"]
	)
	assert_true(installed.ok)
	return registry

func _selection() -> CatalogSelection:
	var root_ids: Array[StringName] = [
		&"commander.c0", &"unit.player_00", &"unit.player_01", &"unit.player_02",
		&"item_component.c0", &"equipment.c0_c1", &"consumable.test",
	]
	var reward_ids: Array[StringName] = [&"reward_table.default"]
	var map_ids: Array[StringName] = [&"map_node.normal"]
	var challenge_ids: Array[StringName] = [
		&"unlock.challenge_0", &"unlock.challenge_1", &"unlock.challenge_2",
		&"unlock.challenge_3", &"unlock.challenge_4", &"unlock.challenge_5",
	]
	return CatalogSelection.new(
		"fixture.1",
		root_ids,
		&"economy.default",
		&"config.combat_default",
		reward_ids,
		map_ids,
		challenge_ids,
		&"meta_reward.default"
	)

func _root_with_items(
	receipt: PinnedCatalogBuildReceipt,
	def_ids: Array[StringName]
) -> SaveRoot:
	var root := SaveRootFixture.create_valid_root()
	root.profile.unlocked_content_ids = [&"commander.c0"]
	root.run.commander_id = &"commander.c0"
	var snapshot_result := ContentSnapshotState.from_pinned_receipt(receipt)
	assert_true(snapshot_result.ok)
	root.run.content_snapshot = snapshot_result.snapshot
	var instance_ids: Array[String] = [
		_COMPONENT_INSTANCE_ID, _EQUIPMENT_INSTANCE_ID, _CONSUMABLE_INSTANCE_ID,
	]
	var items: Array[ItemInstanceState] = []
	for index: int in range(def_ids.size()):
		items.append(ItemInstanceState.new(
			instance_ids[index], def_ids[index], null, U64Bits.zero()
		))
	var empty_strings: Array[String] = []
	var empty_units: Array[UnitInstance] = []
	var empty_placements: Array[BoardPlacementState] = []
	root.run.roster_state = RosterState.new(
		BoardState.new(empty_placements),
		empty_strings,
		empty_units,
		items,
		instance_ids,
		empty_strings,
		root.run.roster_state.active_relic_slots
	)
	return root

func _repository(registry: ContentRegistryService) -> SaveRepository:
	var repository := SaveRepository.new(
		FakeSaveStorage.new(),
		ContentRegistryReceiptAdapter.new(registry),
		ContentRegistryMigrationAdapter.new(registry),
		RunStateValidator.new()
	)
	add_child_autofree(repository)
	return repository
