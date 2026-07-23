class_name ResolveOverflowTestFixture
extends RefCounted

## Shared fixtures for T05 (ResolveOverflowCommand + overflow hard gate +
## crash/load) unit and integration tests.
##
## Naming convention baked into these fixtures (test-author decision, since
## specs/build-systems/design.md §5.4 does not pin an exact wire contract for
## T05 -- only the behavioural contract: "tray 一次性、非靜默丟棄;逐件明確選
## 擇:裝備(走 EquipItemCommand 的驗證邏輯)、鍛造(若為零件,走
## ForgeEquipmentCommand 的配方消耗邏輯,需 tray 內或 inventory 有另一零件)、
## 或明確放棄(移除該 instance)"):
##
##   ResolveOverflowCommand.equip(overflow_item_instance_id: String,
##     target_unit_instance_id: String, catalog: BattleRuleCatalog) -> RunCommand
##   ResolveOverflowCommand.forge(overflow_item_instance_id: String,
##     other_component_instance_id: String, forge_table: ForgeRecipeTable) -> RunCommand
##   ResolveOverflowCommand.abandon(overflow_item_instance_id: String) -> RunCommand
##   .apply_to(draft: RunState) -> CommandApplyResult
##
## Named error codes are carried as the existing "source_code" diagnostic
## string (see commit_board_layout_command.gd's `_rejected` helper, reused by
## equip_item_command.gd/dismantle_equipment_command.gd/forge_equipment_command.gd),
## read via EquipDismantleTestFixture.error_source_code() (shared helper, not
## duplicated here). Expected codes for this command (test-author decision):
##   RESOLVE_OVERFLOW_ITEM_NOT_IN_TRAY, RESOLVE_OVERFLOW_NOT_EQUIPMENT,
##   RESOLVE_OVERFLOW_SLOTS_FULL, RESOLVE_OVERFLOW_UNIQUE_GROUP_CONFLICT,
##   RESOLVE_OVERFLOW_RECIPE_NOT_FOUND, RESOLVE_OVERFLOW_COMPONENT_NOT_AVAILABLE.
##
## Two equipment ids -- `equipment.ovf_unique_a` / `equipment.ovf_unique_b` --
## sharing `UNIQUE_GROUP` (for the equip-disposition unique_group rejection),
## a plain `equipment.ovf_plain` (no unique_group, used to fill a unit's 3
## slots for the slots-full rejection), and two components --
## `item_component.ovf_alpha` / `item_component.ovf_beta` -- with exactly one
## registered cross-pair recipe producing `equipment.ovf_forged` (so a query
## with any other pairing -- e.g. alpha+alpha -- is deliberately unregistered
## and exercises the "recipe not found" rejection).
const _RECEIPT_SELECTION_DIGEST: String = "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"
const _RECEIPT_MANIFEST_DIGEST: String = "dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"

const UNIQUE_GROUP: StringName = &"grp.ovf"
const EQUIPMENT_PLAIN: StringName = &"equipment.ovf_plain"
const EQUIPMENT_UNIQUE_A: StringName = &"equipment.ovf_unique_a"
const EQUIPMENT_UNIQUE_B: StringName = &"equipment.ovf_unique_b"
const COMPONENT_ALPHA: StringName = &"item_component.ovf_alpha"
const COMPONENT_BETA: StringName = &"item_component.ovf_beta"
const EQUIPMENT_FORGED: StringName = &"equipment.ovf_forged"

## Pinned catalog receipt used by base_run()/repository_for(): the base
## SaveRootFixture receipt with this file's equipment/component def_ids added
## to active_entry_ids -- mirrors forge_equipment_test_fixture.gd /
## equip_dismantle_test_fixture.gd's equipment_receipt(). Distinct digests so a
## repository built with this fixture's receipt is never confused with either.
static func equipment_receipt() -> PinnedCatalogBuildReceipt:
	var base := SaveRootFixture.create_receipt()
	var active_ids: Array[StringName] = base.active_entry_ids.duplicate()
	active_ids.append(EQUIPMENT_PLAIN)
	active_ids.append(EQUIPMENT_UNIQUE_A)
	active_ids.append(EQUIPMENT_UNIQUE_B)
	active_ids.append(COMPONENT_ALPHA)
	active_ids.append(COMPONENT_BETA)
	active_ids.append(EQUIPMENT_FORGED)
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
## accept this fixture's def_ids instead of tombstoning them.
static func repository_for(storage: SaveStoragePort) -> SaveRepository:
	return SaveRepository.new(
		storage,
		FakePinnedCatalogReceiptPort.new(equipment_receipt()),
		FakeContentIdMigrationPort.new(),
		RunStateValidator.new()
	)

## Defaults to `_RECEIPT_MANIFEST_DIGEST` -- the same generation base_run()
## pins into its content_snapshot -- so ResolveOverflowCommand's (design §5.1's
## precedent) generation-mismatch guard accepts this catalog by default.
static func battle_catalog(manifest_digest: String = _RECEIPT_MANIFEST_DIGEST) -> BattleRuleCatalog:
	var units: Array[BattleUnitRule] = []
	var traits: Array[BattleTraitRule] = []
	var abilities: Array[BattleAbilityRule] = []
	var effects: Array[BattleEffectRule] = []
	var encounters: Array[BattleEncounterRule] = []
	var configs: Array[BattleCombatConfigRule] = []
	var equipment: Array[BattleEquipmentRule] = [
		_equipment_rule(EQUIPMENT_PLAIN),
		_equipment_rule(EQUIPMENT_UNIQUE_A, OptionalStringNameValue.of(UNIQUE_GROUP)),
		_equipment_rule(EQUIPMENT_UNIQUE_B, OptionalStringNameValue.of(UNIQUE_GROUP)),
		_equipment_rule(EQUIPMENT_FORGED),
	]
	return BattleRuleCatalog.new(
		manifest_digest, units, traits, abilities, effects, encounters, equipment, configs
	)

static func _equipment_rule(
	equipment_id: StringName,
	unique_group: OptionalStringNameValue = null
) -> BattleEquipmentRule:
	var rule := BattleEquipmentRule.new()
	rule.equipment_id = equipment_id
	var no_modifiers: Array[BattleStatModifierRule] = []
	rule.stat_modifiers = no_modifiers
	var no_effects: Array[StringName] = []
	rule.effect_ids = no_effects
	rule.unique_group = unique_group
	return rule

## Exactly one registered recipe: the cross-pair alpha+beta -> EQUIPMENT_FORGED.
## Any other pairing (e.g. alpha+alpha, or an unknown component) is
## deliberately unregistered, so ForgeRecipeTable.try_recipe() returns null --
## modeling the "recipe not found" rejection path.
static func forge_table(manifest_digest: String = _RECEIPT_MANIFEST_DIGEST) -> ForgeRecipeTable:
	var cross_pair := ForgeRecipeRule.new()
	cross_pair.equipment_id = EQUIPMENT_FORGED
	var component_ids: Array[StringName] = [COMPONENT_ALPHA, COMPONENT_BETA]
	cross_pair.component_ids = component_ids
	var recipes: Array[ForgeRecipeRule] = [cross_pair]
	return ForgeRecipeTable.new(manifest_digest, recipes)

## Builds a valid, minimal PREPARE-phase RunState with `unit_count` benched
## (not board-placed) units of def_id &"unit.fixture", each with an empty
## roster.item_instances / inventory / overflow tray to be populated by
## callers. Pool state is kept conserved (REQ-TECH-004 invariant) so callers
## may run the full RunStateValidator or RunController commit path without
## unrelated failures.
static func base_run(unit_count: int = 1) -> RunState:
	var run := SaveRootFixture.create_valid_root().run
	var snapshot_result := ContentSnapshotState.from_pinned_receipt(equipment_receipt())
	assert(snapshot_result.ok, "equipment_receipt() must build a valid content snapshot")
	run.content_snapshot = snapshot_result.snapshot
	run.run_phase = RunState.RunPhase.PREPARE
	var units: Array[UnitInstance] = []
	var bench: Array[String] = []
	var no_equipment: Array[String] = []
	for index: int in range(unit_count):
		var instance_id := unit_id(index + 1)
		units.append(UnitInstance.new(
			instance_id, &"unit.fixture", 1, no_equipment,
			U64Bits.from_u32(0, index + 1).value
		))
		bench.append(instance_id)
	var no_placements: Array[BoardPlacementState] = []
	var no_items: Array[ItemInstanceState] = []
	var no_ids: Array[String] = []
	var relics: Array[RelicSlotState] = []
	for index: int in range(5):
		relics.append(RelicSlotState.new(index, null))
	run.roster_state = RosterState.new(
		BoardState.new(no_placements), bench, units, no_items, no_ids, no_ids, relics
	)
	run.unit_pool_state = UnitPoolState.new([
		UnitPoolEntryState.new(&"unit.fixture", unit_count, 0, 0, unit_count),
	])
	return run

static func unit_id(index: int) -> String:
	return "u_%016x" % index

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

static func find_unit(run: RunState, instance_id: String) -> UnitInstance:
	for unit: UnitInstance in run.roster_state.unit_instances:
		if unit.instance_id == instance_id:
			return unit
	return null

static func find_item(run: RunState, instance_id: String) -> ItemInstanceState:
	for item_instance: ItemInstanceState in run.roster_state.item_instances:
		if item_instance.instance_id == instance_id:
			return item_instance
	return null
