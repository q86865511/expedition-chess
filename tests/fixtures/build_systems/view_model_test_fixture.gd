class_name ViewModelTestFixture
extends RefCounted

## Shared fixtures for T10 (presentation/viewmodels/ ViewModel 四件套) unit tests.
##
## Wire-contract decisions baked into these fixtures (test-author decision --
## specs/build-systems/design.md §8 fixes *what* each ViewModel reads/writes,
## not the exact GDScript API surface, mirroring the precedent set by
## tests/fixtures/build_items/forge_equipment_test_fixture.gd's header):
##
## 1. Every ViewModel is constructed with a `RunController` reference. Reads
##    go through two new read-only accessors this task's tests require
##    `RunController` to expose (analogous to its existing
##    `committed_combat_snapshot()`), both returning **deep clones** so a
##    ViewModel can never retain a mutable domain reference:
##      - `RunController.roster_snapshot() -> RosterState`
##      - `RunController.pending_reward_snapshot() -> PendingRewardState`
##        (null when `resolution_state` is not a `RewardPendingResolutionState`)
##    Design §8's "ViewModel 讀 RunController 提供的 read-only run snapshot
##    （clone）" wording is the direct basis for adding these two accessors
##    rather than inventing a parallel snapshot channel.
## 2. Writes always go through `RunController.dispatch(command) -> CommandResult`
##    (existing method) -- never through a command's bare `apply_to()`. Named
##    error codes are surfaced via the existing "source_code" diagnostic
##    string convention (see equip_dismantle_test_fixture.gd's
##    `error_source_code`), read here via `command_error_source_code()` for the
##    `CommandResult`/`CommandError` shape instead of `CommandApplyResult`.
##
## RunController construction below always passes the pinned `BattleRuleCatalog`
## as the 5th constructor argument (per this task's explicit constraint --
## tasks.md's wave1 note: "RunController 的 battle_catalog 為選填參數，正式
## composition root 接線（T10/T11）必須傳入 pinned catalog").

## Generic RunController builder: wraps `run` in a RunSession (matching
## catalog-lease digest) and a RunSaveRootFactory, always with a non-null
## pinned `battle_catalog` as the 5th constructor argument.
static func controller_for(
	run: RunState,
	battle_catalog: BattleRuleCatalog,
	repository: SaveRepository
) -> RunController:
	var profile := SaveRootFixture.create_valid_root().profile
	var lease := TestCatalogLease.new(run.content_snapshot.manifest_digest_value())
	var session := RunSession.new(profile, run, lease)
	var factory := RunSaveRootFactory.new("0.1.0", FixedRunCommitClock.new())
	return RunController.new(session, repository, RunStateValidator.new(), factory, battle_catalog)

## Extracts the "source_code" diagnostic string from a dispatch()-level
## CommandResult's CommandError (see equip_dismantle_test_fixture.gd's
## error_source_code() for the CommandApplyResult equivalent).
static func command_error_source_code(result: CommandResult) -> String:
	if result.error == null:
		return ""
	for diagnostic: DiagnosticValue in result.error.diagnostic_values:
		if diagnostic.key == &"source_code" and diagnostic.string_value != null:
			return diagnostic.string_value.value
	return ""

# ---------------------------------------------------------------------------
# TraitPreviewViewModel fixtures: two on-field units sharing trait.pack
# (threshold 2), wrapped in a minimal PREPARE-phase RunState. No dispatch is
# ever exercised against this run, so no custom pinned-catalog receipt is
# needed beyond SaveRootFixture's default -- reads never touch SaveRepository.
# ---------------------------------------------------------------------------

const TRAIT_ID: StringName = &"trait.pack"
const TRAIT_EFFECT_ID: StringName = &"effect.pack_t1"
const TRAIT_UNIT_A: StringName = &"unit.trait_a"
const TRAIT_UNIT_B: StringName = &"unit.trait_c"

static func trait_battle_catalog(manifest_digest: String) -> BattleRuleCatalog:
	var units: Array[BattleUnitRule] = [
		_unit_rule(TRAIT_UNIT_A, [TRAIT_ID]), _unit_rule(TRAIT_UNIT_B, [TRAIT_ID]),
	]
	var trait_rule := BattleTraitRule.new()
	trait_rule.trait_id = TRAIT_ID
	trait_rule.trait_kind = &"faction"
	trait_rule.member_rule = &"unit"
	var threshold := BattleTraitThresholdRule.new()
	threshold.required_count = 2
	threshold.effect_ids = [TRAIT_EFFECT_ID]
	trait_rule.thresholds = [threshold]
	var effect_rule := BattleEffectRule.new()
	effect_rule.effect_id = TRAIT_EFFECT_ID
	effect_rule.content_role = &"general"
	effect_rule.trigger = &"battle_start"
	effect_rule.stacking = &"replace"
	effect_rule.max_stacks = 1
	effect_rule.duration_ticks = 1
	var traits: Array[BattleTraitRule] = [trait_rule]
	var effects: Array[BattleEffectRule] = [effect_rule]
	var abilities: Array[BattleAbilityRule] = []
	var encounters: Array[BattleEncounterRule] = []
	var equipment: Array[BattleEquipmentRule] = []
	var configs: Array[BattleCombatConfigRule] = []
	return BattleRuleCatalog.new(
		manifest_digest, units, traits, abilities, effects, encounters, equipment, configs
	)

## Two on-field units (unit.trait_a/unit.trait_c, distinct def_ids) reaching
## trait.pack's threshold(2) -> tier 1 active. Pinned to SaveRootFixture's
## default receipt/digest (read-only usage -- never dispatched/saved).
static func trait_preview_run() -> RunState:
	var run := SaveRootFixture.create_valid_root().run
	run.run_phase = RunState.RunPhase.PREPARE
	var placements: Array[BoardPlacementState] = [
		BoardPlacementState.new(0, 0, "u_0000000000000001"),
		BoardPlacementState.new(0, 1, "u_0000000000000002"),
	]
	var no_equipment: Array[String] = []
	var units: Array[UnitInstance] = [
		UnitInstance.new("u_0000000000000001", TRAIT_UNIT_A, 1, no_equipment, U64Bits.zero()),
		UnitInstance.new("u_0000000000000002", TRAIT_UNIT_B, 1, no_equipment, U64Bits.zero()),
	]
	var no_items: Array[ItemInstanceState] = []
	var no_ids: Array[String] = []
	var relics: Array[RelicSlotState] = []
	for index: int in range(5):
		relics.append(RelicSlotState.new(index, null))
	run.roster_state = RosterState.new(
		BoardState.new(placements), no_ids, units, no_items, no_ids, no_ids, relics
	)
	return run

static func _unit_rule(unit_id: StringName, trait_ids: Array) -> BattleUnitRule:
	var rule := BattleUnitRule.new()
	rule.unit_id = unit_id
	var typed_traits: Array[StringName] = []
	for value in trait_ids:
		typed_traits.append(value as StringName)
	rule.trait_ids = typed_traits
	rule.base_stats = BattleUnitStatsRule.new()
	rule.base_stats.health = 100
	rule.base_stats.attack = 10
	rule.base_stats.armor = 0
	rule.base_stats.magic_resist = 0
	rule.base_stats.attack_speed_milli = 1000
	rule.base_stats.attack_range_cells = 1
	rule.base_stats.start_mana = 0
	rule.base_stats.max_mana = 50
	rule.base_stats.move_speed_milli = 1000
	var scaling := BattleStarScalingRule.new()
	scaling.star = 1
	scaling.health_bps = 10000
	scaling.attack_bps = 10000
	scaling.armor_bps = 10000
	scaling.magic_resist_bps = 10000
	scaling.attack_speed_bps = 10000
	scaling.attack_range_bps = 10000
	scaling.start_mana_bps = 10000
	scaling.max_mana_bps = 10000
	scaling.move_speed_bps = 10000
	rule.star_scalings = [scaling]
	rule.ai_profile = &"melee"
	rule.basic_attack_profile = &"melee"
	rule.availability = &"always"
	rule.shop_condition = &"none"
	return rule

# ---------------------------------------------------------------------------
# RelicSlotViewModel fixtures: REWARD phase, RELIC_RESOLUTION sub-phase, 5
# filled slots (relic.old) plus one offered candidate (relic.new). Custom
# pinned receipt extends SaveRootFixture's base with both relic ids in
# active_entry_ids so the SaveJsonCodec relic_id migration gate (
# save_json_codec.gd:1134-1136) never tombstones them on the dispatch()
# save/load roundtrip -- mirrors forge_equipment_test_fixture.gd's
# equipment_receipt() precedent.
# ---------------------------------------------------------------------------

const RELIC_OLD: StringName = &"relic.old"
const RELIC_NEW: StringName = &"relic.new"
const _RELIC_RECEIPT_SELECTION_DIGEST: String = "1010101010101010101010101010101010101010101010101010101010101010"
const _RELIC_RECEIPT_MANIFEST_DIGEST: String = "2020202020202020202020202020202020202020202020202020202020202020"

static func relic_receipt() -> PinnedCatalogBuildReceipt:
	var base := SaveRootFixture.create_receipt()
	var active_ids: Array[StringName] = base.active_entry_ids.duplicate()
	active_ids.append(RELIC_OLD)
	active_ids.append(RELIC_NEW)
	active_ids.sort_custom(func(left: StringName, right: StringName) -> bool:
		return String(left) < String(right)
	)
	return PinnedCatalogBuildReceipt.new(
		base.catalog_schema_version,
		base.content_codec_version,
		base.content_version,
		_RELIC_RECEIPT_SELECTION_DIGEST,
		active_ids,
		base.economy_config_id,
		base.combat_config_id,
		base.reward_table_ids,
		base.map_node_def_ids,
		base.challenge_unlock_def_ids,
		base.meta_reward_table_id,
		_RELIC_RECEIPT_MANIFEST_DIGEST
	)

static func relic_repository_for(storage: SaveStoragePort) -> SaveRepository:
	return SaveRepository.new(
		storage,
		FakePinnedCatalogReceiptPort.new(relic_receipt()),
		FakeContentIdMigrationPort.new(),
		RunStateValidator.new()
	)

static func relic_battle_catalog() -> BattleRuleCatalog:
	var units: Array[BattleUnitRule] = []
	var traits: Array[BattleTraitRule] = []
	var abilities: Array[BattleAbilityRule] = []
	var effects: Array[BattleEffectRule] = []
	var encounters: Array[BattleEncounterRule] = []
	var equipment: Array[BattleEquipmentRule] = []
	var configs: Array[BattleCombatConfigRule] = []
	return BattleRuleCatalog.new(
		_RELIC_RECEIPT_MANIFEST_DIGEST, units, traits, abilities, effects, encounters, equipment, configs
	)

## RewardService-compatible EconomyExpeditionCatalog pinned to the same
## digest, reusing EconomyTestFixture.settlement_catalog()'s config/reward
## table shape (only the manifest digest differs from its default).
static func relic_economy_catalog() -> EconomyExpeditionCatalog:
	return EconomyTestFixture.settlement_catalog(_RELIC_RECEIPT_MANIFEST_DIGEST)

## Builds a REWARD-phase run in PendingRewardState.Phase.RELIC_RESOLUTION,
## with all 5 active_relic_slots already filled by RELIC_OLD and one selected
## RELIC-kind offer (content_id = RELIC_NEW, via `selected_choice_id`) among
## three total offers -- RunStateValidator._validate_pending_reward requires
## exactly 3 offers for a non-EVENT_GRANT stage (mirrors
## ResolutionFixtureFactory._create_reward_pending()'s 3-offer STANDARD-stage
## shape) -- ready for ResolveRelicRewardCommand.new(slot_index, catalog) to be
## dispatched directly through the real RunController (mirrors
## tests/unit/economy_expediton/test_battle_settlement_and_rewards.gd's manual
## RELIC_RESOLUTION setup, minus the RewardService.choose() detour, since that
## detour only exists there to prove `choose()` itself works).
static func relic_resolution_run() -> RunState:
	var root := SaveRootFixture.create_valid_root()
	var run := root.run
	var snapshot_result := ContentSnapshotState.from_pinned_receipt(relic_receipt())
	assert(snapshot_result.ok, "relic_receipt() must build a valid content snapshot")
	run.content_snapshot = snapshot_result.snapshot
	run.run_phase = RunState.RunPhase.REWARD
	var registry := RuntimeKeySchemaRegistry.new()
	var relics: Array[RelicSlotState] = []
	for index: int in range(5):
		relics.append(RelicSlotState.new(index, OptionalStringNameValue.of(RELIC_OLD)))
	var no_placements: Array[BoardPlacementState] = []
	var no_units: Array[UnitInstance] = []
	var no_items: Array[ItemInstanceState] = []
	var no_ids: Array[String] = []
	run.roster_state = RosterState.new(
		BoardState.new(no_placements), no_ids, no_units, no_items, no_ids, no_ids, relics
	)
	# RunStateValidator._validate_pending_reward requires run.current_node_id to
	# be non-null and equal to pending.node_id, and a separate top-level check
	# requires run.current_node_id/run.map_state.current_node_id to agree -- so
	# both are pointed at the same placeholder token even though
	# resolve_relic()/its _validate_source() never itself inspects map_state
	# (SaveRootFixture.create_valid_root() otherwise leaves map_state.nodes/
	# current_node_id empty).
	var node_id := "node.fixture"
	run.current_node_id = OptionalStringValue.new(node_id)
	run.map_state.current_node_id = OptionalStringValue.new(node_id)
	# The transaction key built below only needs to be *structurally valid* to
	# satisfy PendingRewardState's non-null transaction_id constructor param --
	# resolve_relic() never reads it -- so an arbitrary stable-ascii node token
	# is used rather than a real map node id.
	var transaction := registry.build_transaction(
		StringName(run.run_id), &"node_fixture", &"reward", run.next_transaction_serial
	)
	assert(transaction.ok, "build_transaction() must succeed for the fixture's placeholder tokens")
	var offers: Array[RewardOfferState] = [
		RewardOfferState.new(
			"choice_relic", RewardOfferState.RewardKind.RELIC,
			OptionalStringNameValue.of(RELIC_NEW), 1, null,
			"7777777777777777777777777777777777777777777777777777777777777777"
		),
		RewardOfferState.new(
			"choice_gold_1", RewardOfferState.RewardKind.GOLD, null, 3, null,
			"8888888888888888888888888888888888888888888888888888888888888888"
		),
		RewardOfferState.new(
			"choice_gold_2", RewardOfferState.RewardKind.GOLD, null, 1, null,
			"9999999999999999999999999999999999999999999999999999999999999999"
		),
	]
	var reserved: Array[ReservedCopyState] = []
	var pending := PendingRewardState.new(
		node_id, PendingRewardState.StageId.RELIC,
		PendingRewardState.Phase.RELIC_RESOLUTION, offers, reserved,
		OptionalStringValue.new("choice_relic"), null,
		transaction.key_state as TransactionKeyState
	)
	run.resolution_state = RewardPendingResolutionState.new(pending)
	return run
