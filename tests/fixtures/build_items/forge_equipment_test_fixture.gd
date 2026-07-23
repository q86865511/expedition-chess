class_name ForgeEquipmentTestFixture
extends RefCounted

## Shared fixtures for T03 (ForgeEquipmentCommand) unit and integration tests.
##
## Naming convention baked into these fixtures (test-author decision, since
## specs/build-systems/design.md §5.1 does not pin an exact wire contract for
## T03 -- only the behavioural contract: "兩個 inventory 零件 instance id →
## ForgeRecipeTable 以無序 component-pair(含相同零件自配)查恰一 equipment_id
## (21 封閉,查無即拒)→ 消耗兩零件、以 next_item_serial 產一件完整裝備入
## inventory(滿則入 overflow)"):
##   ForgeEquipmentCommand.new(component_instance_id_a: String,
##     component_instance_id_b: String, forge_table: ForgeRecipeTable) -> RunCommand
##   .apply_to(draft: RunState) -> CommandApplyResult
## Named error codes are carried as the existing "source_code" diagnostic
## string (see commit_board_layout_command.gd's `_rejected` helper, reused by
## equip_item_command.gd/dismantle_equipment_command.gd), read via
## EquipDismantleTestFixture.error_source_code() (shared helper, not
## duplicated here).
##
## Two components -- `item_component.alpha` / `item_component.beta` -- with two
## registered recipes: a self-pair (alpha+alpha -> equipment.alpha_alpha) and a
## cross-pair (alpha+beta -> equipment.alpha_beta). `beta+beta` is deliberately
## NOT registered so tests can exercise the "recipe not found" rejection
## without inventing a third component.
##
## Pinned catalog receipt digests distinct from both SaveRootFixture.MANIFEST_DIGEST
## and EquipDismantleTestFixture's receipt digests, so a repository built with this
## fixture's receipt is never confused with either.
const _RECEIPT_SELECTION_DIGEST: String = "7777777777777777777777777777777777777777777777777777777777777777"
const _RECEIPT_MANIFEST_DIGEST: String = "8888888888888888888888888888888888888888888888888888888888888888"

const COMPONENT_ALPHA: StringName = &"item_component.alpha"
const COMPONENT_BETA: StringName = &"item_component.beta"
const EQUIPMENT_ALPHA_ALPHA: StringName = &"equipment.alpha_alpha"
const EQUIPMENT_ALPHA_BETA: StringName = &"equipment.alpha_beta"

## Pinned catalog receipt used by base_run()/repository_for(): the base
## SaveRootFixture receipt with this file's component/equipment def_ids added
## to active_entry_ids. Without this, SaveJsonCodec's content-id tombstone
## gating would mark item_instances referencing these ids as
## MIGRATION_TOMBSTONE_REQUIRED on a save()/load() roundtrip -- mirrors
## equip_dismantle_test_fixture.gd's equipment_receipt().
static func equipment_receipt() -> PinnedCatalogBuildReceipt:
	var base := SaveRootFixture.create_receipt()
	var active_ids: Array[StringName] = base.active_entry_ids.duplicate()
	active_ids.append(COMPONENT_ALPHA)
	active_ids.append(COMPONENT_BETA)
	active_ids.append(EQUIPMENT_ALPHA_ALPHA)
	active_ids.append(EQUIPMENT_ALPHA_BETA)
	active_ids.sort_custom(func(left: StringName, right: StringName) -> bool:
		return String(left) < String(right)
	)
	return PinnedCatalogBuildReceipt.new(
		base.catalog_schema_version,
		base.content_codec_version,
		base.content_version,
		_RECEIPT_SELECTION_DIGEST,
		active_ids,
		base.economy_config_id,
		base.combat_config_id,
		base.reward_table_ids,
		base.map_node_def_ids,
		base.challenge_unlock_def_ids,
		base.meta_reward_table_id,
		_RECEIPT_MANIFEST_DIGEST
	)

## SaveRepository wired to `equipment_receipt()` so save()/load() round-trips
## accept this fixture's component/equipment def_ids instead of tombstoning them.
static func repository_for(storage: SaveStoragePort) -> SaveRepository:
	return SaveRepository.new(
		storage,
		FakePinnedCatalogReceiptPort.new(equipment_receipt()),
		FakeContentIdMigrationPort.new(),
		RunStateValidator.new()
	)

## Two registered recipes: self-pair (alpha+alpha) and cross-pair (alpha+beta).
## `beta+beta` is intentionally absent -- ForgeRecipeTable.try_recipe() returns
## null for it, modeling the "query with no matching recipe" rejection path.
## Defaults to `_RECEIPT_MANIFEST_DIGEST` -- the same generation base_run()
## pins into its content_snapshot -- so ForgeEquipmentCommand's
## generation-mismatch guard accepts this table by default. Pass a different
## digest to exercise the mismatch rejection.
static func forge_table(manifest_digest: String = _RECEIPT_MANIFEST_DIGEST) -> ForgeRecipeTable:
	var self_pair := ForgeRecipeRule.new()
	self_pair.equipment_id = EQUIPMENT_ALPHA_ALPHA
	self_pair.component_ids = [COMPONENT_ALPHA]
	var cross_pair := ForgeRecipeRule.new()
	cross_pair.equipment_id = EQUIPMENT_ALPHA_BETA
	var cross_components: Array[StringName] = [COMPONENT_ALPHA, COMPONENT_BETA]
	cross_pair.component_ids = cross_components
	var recipes: Array[ForgeRecipeRule] = [self_pair, cross_pair]
	return ForgeRecipeTable.new(manifest_digest, recipes)

## Builds a valid, minimal PREPARE-phase RunState with no units (forging only
## touches roster_state.item_instances/inventory, not units), pinned to
## `equipment_receipt()`'s content_snapshot. Pool state is kept conserved
## (REQ-TECH-004 invariant, trivially satisfied by zero units/zero pool
## entries) so callers may run the full RunStateValidator or RunController
## commit path without unrelated failures.
static func base_run() -> RunState:
	var run := SaveRootFixture.create_valid_root().run
	var snapshot_result := ContentSnapshotState.from_pinned_receipt(equipment_receipt())
	assert(snapshot_result.ok, "equipment_receipt() must build a valid content snapshot")
	run.content_snapshot = snapshot_result.snapshot
	run.run_phase = RunState.RunPhase.PREPARE
	var no_placements: Array[BoardPlacementState] = []
	var no_units: Array[UnitInstance] = []
	var no_items: Array[ItemInstanceState] = []
	var no_ids: Array[String] = []
	var relics: Array[RelicSlotState] = []
	for index: int in range(5):
		relics.append(RelicSlotState.new(index, null))
	run.roster_state = RosterState.new(
		BoardState.new(no_placements), no_ids, no_units, no_items, no_ids, no_ids, relics
	)
	var no_pool_entries: Array[UnitPoolEntryState] = []
	run.unit_pool_state = UnitPoolState.new(no_pool_entries)
	return run

static func item_id(index: int) -> String:
	return "it_%016x" % index

## bound_unit_id == "" means unbound (sitting free in inventory or overflow).
static func item(
	instance_id: String,
	def_id: StringName,
	bound_unit_id: String = "",
	serial: int = 1
) -> ItemInstanceState:
	var bound: OptionalStringValue = (
		OptionalStringValue.new(bound_unit_id) if not bound_unit_id.is_empty() else null
	)
	return ItemInstanceState.new(
		instance_id, def_id, bound, U64Bits.from_u32(0, serial).value
	)

static func find_item(run: RunState, instance_id: String) -> ItemInstanceState:
	for item_instance: ItemInstanceState in run.roster_state.item_instances:
		if item_instance.instance_id == instance_id:
			return item_instance
	return null
