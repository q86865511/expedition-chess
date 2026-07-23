class_name EquipDismantleTestFixture
extends RefCounted

## Shared fixtures for T04 (EquipItemCommand / DismantleEquipmentCommand /
## run_state_validator equipment-kind invariant) unit and integration tests.
##
## Naming convention baked into these fixtures (test-author decision, since
## specs/build-systems/design.md does not pin an exact wire contract for T04):
## - `equipment.*` ids are registered in the returned BattleRuleCatalog via
##   BattleEquipmentRule (so BattleRuleCatalog.try_equipment_rule(id) != null).
## - `item_component.*` ids are NOT registered as equipment rules (so
##   try_equipment_rule(id) == null) -- this is how EquipItemCommand and the
##   validator invariant are expected to distinguish "component" from
##   "equipment" without depending on T01's ForgeRecipeTable/RunRelicTable.
## - `consumable.*` ids model a "拆卸道具" as an ordinary unbound
##   ItemInstanceState sitting in inventory (S4 design §1 explicitly commits
##   to zero new persisted RunState fields, so this reuses the existing
##   item_instances/inventory_item_instance_ids schema rather than inventing
##   a new consumable-count field). DismantleEquipmentCommand still gates
##   consumption on the def_id resolving to a genuine dismantle ConsumableDef
##   via `consumable_rules()` (use_timing == &"dismantle"); an arbitrary
##   inventory item can never be spent to unbind equipment.

const UNIQUE_GROUP_ALPHA: StringName = &"grp.alpha"

## Pinned catalog receipt digests for the T04 equipment-extended receipt (see
## `equipment_receipt()`) -- distinct from SaveRootFixture.MANIFEST_DIGEST so a
## repository built with the extended receipt is never confused with the base
## fixture's repository/codec.
const _RECEIPT_SELECTION_DIGEST: String = "5555555555555555555555555555555555555555555555555555555555555555"
const _RECEIPT_MANIFEST_DIGEST: String = "6666666666666666666666666666666666666666666666666666666666666666"

## Pinned catalog receipt used by base_run()/repository_for(): the base
## SaveRootFixture receipt with this file's `equipment.*` def_ids added to
## active_entry_ids. Without this, SaveJsonCodec's content-id tombstone gating
## (save_json_codec.gd's _migrate_required_id) marks item_instances bound to
## these ids as MIGRATION_TOMBSTONE_REQUIRED on the save() encode/decode
## read-back roundtrip, since they are absent from SaveRootFixture's base
## receipt -- mirrors test_commit_board_layout_command.gd's _equipment_receipt().
static func equipment_receipt() -> PinnedCatalogBuildReceipt:
	var base := SaveRootFixture.create_receipt()
	var active_ids: Array[StringName] = base.active_entry_ids.duplicate()
	active_ids.append(&"equipment.plain_a")
	active_ids.append(&"equipment.plain_b")
	active_ids.append(&"equipment.plain_c")
	active_ids.append(&"equipment.plain_d")
	# A non-equipment content id enabled in the pinned run so a component can
	# survive the save/load roundtrip without being tombstoned. It is deliberately
	# NOT registered in battle_catalog() as an equipment rule, so binding it trips
	# the run_state_validator equipment-kind invariant (F1 integration coverage).
	active_ids.append(&"item_component.gem")
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
## accept this fixture's equipment.* item def_ids instead of tombstoning them.
static func repository_for(storage: SaveStoragePort) -> SaveRepository:
	return SaveRepository.new(
		storage,
		FakePinnedCatalogReceiptPort.new(equipment_receipt()),
		FakeContentIdMigrationPort.new(),
		RunStateValidator.new()
	)

## Defaults to `_RECEIPT_MANIFEST_DIGEST` -- the same generation base_run() pins
## into its content_snapshot -- so EquipItemCommand's generation-mismatch guard
## (equip_item_command.gd) and RunController's commit-time catalog pin accept
## this catalog. Pass a different digest to exercise the mismatch rejection.
static func battle_catalog(manifest_digest: String = _RECEIPT_MANIFEST_DIGEST) -> BattleRuleCatalog:
	var units: Array[BattleUnitRule] = []
	var traits: Array[BattleTraitRule] = []
	var abilities: Array[BattleAbilityRule] = []
	var effects: Array[BattleEffectRule] = []
	var encounters: Array[BattleEncounterRule] = []
	var configs: Array[BattleCombatConfigRule] = []
	var equipment: Array[BattleEquipmentRule] = [
		_equipment_rule(&"equipment.plain_a"),
		_equipment_rule(&"equipment.plain_b"),
		_equipment_rule(&"equipment.plain_c"),
		_equipment_rule(&"equipment.plain_d"),
		_equipment_rule(&"equipment.unique_a", OptionalStringNameValue.of(UNIQUE_GROUP_ALPHA)),
		_equipment_rule(&"equipment.unique_b", OptionalStringNameValue.of(UNIQUE_GROUP_ALPHA)),
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

## Pinned ConsumableRuleTable registering `consumable.dismantle_kit` as a genuine
## dismantle ConsumableDef (use_timing == &"dismantle", no run_operations, per
## content_validator.gd rule (d)). Non-registered ids -- and non-dismantle
## consumables like `consumable.non_dismantle` -- resolve to is_dismantle_consumable
## == false, so DismantleEquipmentCommand rejects them without consuming anything.
static func consumable_rules(
	manifest_digest: String = _RECEIPT_MANIFEST_DIGEST
) -> ConsumableRuleTable:
	var dismantle := ConsumableRule.new()
	dismantle.consumable_id = &"consumable.dismantle_kit"
	dismantle.use_timing = &"dismantle"
	dismantle.has_run_operations = false
	var rules: Array[ConsumableRule] = [dismantle]
	return ConsumableRuleTable.new(manifest_digest, rules)

## Builds a valid, minimal PREPARE-phase RunState with `unit_count` benched
## (not board-placed) units of def_id &"unit.fixture", each with an empty
## roster.item_instances / inventory to be populated by callers. Pool state
## is kept conserved (REQ-TECH-004 invariant) so callers may run the full
## RunStateValidator or RunController commit path without unrelated failures.
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

## bound_unit_id == "" means unbound.
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

## Extracts the "source_code" diagnostic string set by the established
## `_rejected(field_path, source_code)` command helper convention (see
## commit_board_layout_command.gd), so tests can assert on named error codes
## without needing a dedicated error-code enum class.
static func error_source_code(result: CommandApplyResult) -> String:
	if result.error == null:
		return ""
	for diagnostic: DiagnosticValue in result.error.diagnostic_values:
		if diagnostic.key == &"source_code" and diagnostic.string_value != null:
			return diagnostic.string_value.value
	return ""
