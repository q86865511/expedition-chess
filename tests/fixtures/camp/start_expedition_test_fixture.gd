class_name StartExpeditionTestFixture
extends RefCounted

## T05 (specs/meta-progression/design.md SS4.2; requirements.md S5-AC-002,
## S5-AC-009 前置檢查段): shared fixtures for StartExpeditionCommand /
## RunBootstrapService / CampController.dispatch_start_expedition() unit and
## integration tests.
##
## ---------------------------------------------------------------------------
## Test-author contract (design.md SS4.2 pins the literal call signature
## "RunBootstrapService.build(profile, commander_def, challenge_level,
## pinned_receipt)" and the step-1/step-2/step-3 prose, but not every wire
## detail below -- these are the test author's binding decisions; the
## implementer must match them exactly. Naming/ceremony mirrors T04's
## PurchaseUnlockCommand/UnlockPurchaseService family
## (tests/fixtures/camp/purchase_unlock_test_fixture.gd).
## ---------------------------------------------------------------------------
##
## New types under domain/run/camp/ (this wave, 7 files):
##
## 1. StartExpeditionError (start_expedition_error.gd) -- RefCounted.
##      const EXPEDITION_COMMANDER_LOCKED / EXPEDITION_CHALLENGE_PREREQUISITE_UNMET
##      / INPUT_INVALID: StringName (design.md SS13's two named codes plus a
##      structural INPUT_INVALID, mirrors UnlockPurchaseError's shape).
##      var code: StringName; var field_path: StringName. _init/deep_clone.
##
## 2. RunBootstrapError (run_bootstrap_error.gd) -- RefCounted.
##      const INPUT_INVALID: StringName only -- RunBootstrapService performs no
##      *business* validation (commander-locked / challenge-prerequisite are
##      StartExpeditionCommand's job, checked BEFORE calling build(), per
##      design.md SS4.2's step numbering "1. 驗證...2. RunBootstrapService.build").
##      var code/field_path; _init/deep_clone.
##
## 3. RunBootstrapResult (run_bootstrap_result.gd) -- RefCounted.
##      var ok: bool; var run: RunState; var error: RunBootstrapError.
##      static success(run) / static failure(error); ResultInvariant-style
##      mutual exclusion (ok <=> run != null and error == null).
##
## 4. StartExpeditionResult (start_expedition_result.gd) -- RefCounted.
##      var ok: bool; var profile: ProfileState; var run: RunState;
##      var error: StartExpeditionError. static success(profile, run) /
##      static failure(error); mutual exclusion
##      (ok <=> profile != null and run != null and error == null).
##
## 5. RunBootstrapService (run_bootstrap_service.gd) -- RefCounted.
##      const STARTING_ECONOMY_LEVEL: int = 1 (matches
##      SaveRootFixture.create_valid_root()'s EconomyState.new(0, 1, ...)
##      convention for "a run just starting").
##      func build(profile: ProfileState, commander_def: CommanderDef,
##        challenge_level: int, pinned_receipt: PinnedCatalogBuildReceipt,
##        catalog: EconomyExpeditionCatalog)
##        -> RunBootstrapResult
##      Pure/deterministic given its inputs (no wall-clock, no Object-id
##      entropy, no new RNG stream). null profile/commander_def/pinned_receipt/
##      catalog -> failure(INPUT_INVALID, "profile"|"commander_def"|
##      "pinned_receipt"|"catalog"); a catalog pinned to another generation ->
##      failure(INPUT_INVALID, "catalog.manifest_digest"); a negative
##      commander_def.population_bonus -> failure(INPUT_INVALID,
##      "commander_def.population_bonus"); a starting_pack of more than
##      BoardPreparationValidator.BENCH_CAPACITY units ->
##      failure(INPUT_INVALID, "commander_def.starting_pack").
##      Otherwise, in this order:
##        a. content_snapshot = ContentSnapshotState.from_pinned_receipt(pinned_receipt);
##           build failure -> failure(INPUT_INVALID, "content_snapshot").
##        b. run_key = RuntimeKeySchemaRegistry.new().build_run(profile.profile_id,
##           profile.next_run_serial) -- the PRE-increment serial. This is what
##           RunStateValidator.validate_root's invariant
##           "run.run_key.next_run_serial.add(one) == profile.next_run_serial"
##           requires: run_key freezes the OLD serial value, and
##           StartExpeditionCommand (below) bumps profile' to the NEXT one.
##           encode failure -> failure(INPUT_INVALID, "run_key").
##        c. run_id = String(run_key.key_state.digest).
##        d. run_seed = U64Bits.from_hex(run_id.substr(0, 16)).value -- test-author
##           decision for design.md SS4.2's "run_seed 決定性衍生自 run key
##           （profile_id＋next_run_serial）": the run_key digest is already the
##           canonical SHA-256 encoding of (profile_id, next_run_serial), so
##           truncating its first 16 hex chars into a U64 is a deterministic,
##           zero-entropy derivation that consumes no RNG stream (design.md SS2's
##           "不新增 stream").
##        e. 4 named rng streams, in RngService.STREAMS order (map=0/shop=1/
##           reward=2/combat=3, matching NamedRngState.StreamName), each seeded
##           via RngService.new().derive_stream(run_seed, stream_name,
##           StringName(run_id)).stream.snapshot(), stored as
##           NamedRngState(index, snapshot).
##        f. roster seeded from commander_def.starting_pack
##           (Array[ContentAmountDef]): for each entry in array order, for each
##           of its count_u32 copies, one UnitInstance(star=1, def_id=
##           entry.content_id, no equipment, instance_id="u_%016x" % running_serial,
##           acquired_serial=U64Bits.from_u32(0, running_serial).value) --
##           running_serial starts at 0 and increments by 1 per unit created
##           (test-author decision matching
##           tests/fixtures/build_items/resolve_overflow_test_fixture.gd's
##           "u_%016x" % index convention). ALL seeded units go to
##           roster.bench_unit_instance_ids; NONE are placed on the board.
##           The COMMANDER itself never becomes a UnitInstance at all (no unit
##           with def_id == commander_def.id is ever created) -- design.md
##           SS4.2's "指揮官不入 board placements／不佔人口" holds by
##           construction, not by a runtime filter: the commander cannot appear
##           in placements or bench and cannot consume board population because
##           no such UnitInstance exists to place.
##           next_unit_serial = U64Bits.from_u32(0, running_serial).value after
##           seeding (the NEXT id to be assigned; running_serial equals the
##           total number of seeded units).
##        g. unit_pool_state = catalog.create_initial_pool() (one entry per
##           ShopUnitRule, total_copies = remaining_copies = the tier's
##           pool_copies, held = reserved = 0) with the starting_pack's copies
##           MOVED from remaining_copies to held_copies -- the player already
##           holds them, so the shop and the reward tables must not be able to
##           deal the same copies again, and the per-def total stays conserved
##           (RunStateValidator._validate_pool requires
##           remaining+reserved+held == total, and
##           _validate_pool_roster_conservation requires held == the star-
##           weighted roster count). A starting_pack def with no ShopUnitRule
##           (a commander-exclusive unit) has no catalog entry, so it gets a
##           player-only entry (total = held, remaining = 0) -- a roster unit
##           whose def_id has no pool entry at all fails conservation. A
##           starting_pack asking for more copies than the pool holds is
##           rejected: failure(INPUT_INVALID,
##           "commander_def.starting_pack.count_u32"). Entries sorted ascending
##           by def_id string (RunStateValidator._validate_pool's ordering).
##           (W3-F1: the previous shape -- only the starting_pack defs, every
##           remaining_copies == 0 -- made the shop return zero offers for the
##           entire run and the first unit reward fail UNIT_POOL_INVALID.)
##        h. economy_state = EconomyState.new(gold=0, level=
##           STARTING_ECONOMY_LEVEL, xp=0, win_streak=0, loss_streak=0,
##           shop_refresh_index=0, shop_offers=[]). commander_def
##           .population_bonus is deliberately NOT folded into level (W3-F3):
##           economy_state.level is simultaneously the shop tier-odds key
##           (shop_service.gd:203) and the XP ladder
##           (battle_settlement_service.gd:308), so folding it in would grant
##           shop power and free levels beyond the population cap design.md
##           SS4.2 authorises (REQ-META-002). design.md SS4.2's "population cap
##           於此套用 commander.population_bonus" is instead expressed the way
##           the population model works -- capacity == base_level + sources
##           (population_calculator.gd:8-51), so the bonus is an extra
##           PopulationSourceSnapshot(COMMANDER, commander_id, "commander",
##           bonus) built by RunBootstrapService.try_commander_population_source()
##           and injected into CommitBoardLayoutCommand by whoever constructs
##           it (RunState has no persisted population-source ledger). This also
##           matches the content budget model, which adds the commander bonus
##           ON TOP of base_population_cap (content_validator.gd:752-769).
##        i. map_state = MapState.new([], [], null, []) -- no map generated yet
##           (GenerateExpeditionMapCommand, a later command per design.md SS3's
##           module diagram, populates it; RunStateValidator._validate_map
##           accepts an empty map unconditionally, and
##           SaveRootFixture.create_valid_root() establishes this same
##           empty-map-at-a-fresh-run precedent).
##        j. expedition_hp = 100 (matches SaveRootFixture / RunStateValidator's
##           "expedition_hp <= 100" bound -- full HP at expedition start).
##        k. run_phase = RunState.RunPhase.MAP. commander_id = commander_def.id.
##           challenge_level = the input as-is. act_index = 0.
##           current_node_id = null. cleared_normal_count = cleared_elite_count
##           = defeated_boss_count = 0. next_transaction_serial =
##           next_item_serial = U64Bits.zero(). income_claimed_node_ids =
##           loss_stipend_claimed_act_ids = reservation_owners =
##           transaction_receipts = claim_receipts = discovered_content_ids = []
##           (T09's RunDiscoveryLog triggers -- deploy/purchase/shop/encounter/
##           reward -- do not fire at bootstrap; bench-seeding is none of those
##           four, so nothing is discovered yet). resolution_state =
##           IdleResolutionState.new(). active_relic_slots = 5 empty
##           RelicSlotState (slot_index 0..4, relic_id = null; matches
##           SaveRootFixture's 5-slot convention). run_id = the run_key digest
##           from step b/c.
##
## 6. StartExpeditionCommand (start_expedition_command.gd) -- RefCounted.
##      _init(commander_id: StringName, commander_def: CommanderDef,
##        challenge_level: int, pinned_receipt: PinnedCatalogBuildReceipt,
##        catalog: EconomyExpeditionCatalog,
##        bootstrap_service: RunBootstrapService = null)
##      is_concrete() -> bool (commander_def != null and pinned_receipt != null
##        and catalog != null and challenge_level >= 0)
##      apply_to(profile: ProfileState) -> StartExpeditionResult
##        design.md SS4.2 step 1's literal clause order, each independently
##        observable ("分別回具名 error 拒選"), reading the CALLER's `profile`
##        argument directly (no clone) for every check below -- exactly
##        mirroring UnlockPurchaseService's convention that a rejecting call
##        never touches the caller's object because nothing is ever assigned
##        to it before the success branch:
##        a. not is_concrete() -> failure(StartExpeditionError.INPUT_INVALID,
##           "command").
##        b. not profile.unlocked_content_ids.has(commander_id)
##           -> failure(StartExpeditionError.EXPEDITION_COMMANDER_LOCKED,
##              "profile.unlocked_content_ids").
##        c. challenge_level > 0 and no CommanderChallengeRecordState in
##           profile.commander_challenge_records for this commander_id has
##           highest_cleared_level >= challenge_level - 1 (challenge_level == 0
##           always passes this clause regardless of records -- design.md SS4.2
##           "level 0 無前置")
##           -> failure(StartExpeditionError.EXPEDITION_CHALLENGE_PREREQUISITE_UNMET,
##              "profile.commander_challenge_records").
##        d. profile.next_run_serial == U64Bits.max_value()
##           -> failure(StartExpeditionError.SERIAL_EXHAUSTED,
##              "profile.next_run_serial"). U64Bits.add() wraps silently, which
##           would make the new run reuse the profile's first run_id/run_seed;
##           same guard convention as every other serial bump in the project.
##        e. bootstrap_service.build(profile, commander_def, challenge_level,
##           pinned_receipt, catalog); a RunBootstrapResult failure propagates as
##           failure(StartExpeditionError.INPUT_INVALID, "run") (structural-only
##           -- a build failure here means malformed fixture/content input, not
##           a domain rejection, so it does not need its own named code).
##        f. success: profile' = profile.deep_clone() with next_run_serial =
##           profile.next_run_serial.add(U64Bits.one()), last_selection =
##           ProfileLastSelectionState.new(commander_id, challenge_level).
##           Returns StartExpeditionResult.success(profile', run) -- profile'
##           is never the same instance as the caller's argument.
##
## 7. CampController widening (camp_controller.gd, existing file from T04): a
##      NEW method `dispatch_start_expedition(command: StartExpeditionCommand)
##      -> StartExpeditionCampResult` is added ALONGSIDE the existing
##      `dispatch()` (which stays PurchaseUnlockCommand-only, per T04's own
##      note "widen this signature... in a later wave" -- a second entry point
##      is this wave's chosen resolution, not a breaking change to dispatch()).
##      Same copy-validate-save-swap discipline as dispatch():
##        1. command == null or not command.is_concrete()
##           -> failure(CampCommandError.INVALID_COMMAND, "command"); no clone,
##           no validate, no save attempted.
##        2. reentrancy guard (TRANSACTION_BUSY), same as dispatch().
##        3. command.apply_to(current profile clone) -> StartExpeditionResult;
##           a domain rejection's code passes straight through into
##           CampCommandError.code (same "open StringName" passthrough
##           convention as dispatch()'s PurchaseUnlockError handling).
##        4. validate: build a candidate SaveRoot via RunSaveRootFactory (the
##           EXISTING factory from
##           domain/run/controller/run_save_root_factory.gd, reused as-is since
##           it already reads run.content_snapshot.content_version_value() --
##           CampSaveRootFactory is deliberately NOT used here, it is scoped to
##           run == null profile-only saves per its own file header). It is a
##           CONSTRUCTOR-INJECTED collaborator (CampController._init's
##           p_run_save_root_factory), exactly like the camp one: app_version and
##           the commit clock must be one choice per controller, not defaults
##           that differ between unlock purchases and expedition starts. Then call
##           RunStateValidator.new().validate_root(candidate) BEFORE
##           SaveRepository.save (mirrors dispatch()'s "real, independently
##           observable" pre-save validate step). Failure ->
##           CampCommandError.VALIDATION_FAILED.
##        5. save: SaveRepository.save(candidate). Failure ->
##           CampCommandError.SAVE_FAILED; in-memory profile NOT swapped.
##        6. swap: in-memory profile becomes profile' (deep-cloned).
##           CampController does not retain the created RunState as its own
##           in-memory state (its scope is "no active run" per design.md SS4.1)
##           -- only the persisted SaveRoot carries it; the returned
##           StartExpeditionCampResult still carries `run` back to the caller
##           for the same-turn AppStateMachine transition (T11's concern, out
##           of scope here).
##
## 8. StartExpeditionCampResult (start_expedition_camp_result.gd) -- RefCounted.
##      var ok: bool; var profile: ProfileState; var run: RunState;
##      var error: CampCommandError. static success(profile, run) /
##      static failure(error); mutual exclusion
##      (ok <=> profile != null and run != null and error == null).
## ---------------------------------------------------------------------------

const _RECEIPT_SELECTION_DIGEST: String = "7"
const _RECEIPT_MANIFEST_DIGEST: String = "6"

## Deliberately NOT RunSaveRootFactory / CampSaveRootFactory's "0.2.0" default, so
## a hard-coded factory anywhere in the camp transaction path is observable.
const APP_VERSION: String = "9.9.9"

const COMMANDER_ALPHA_ID: StringName = &"commander.test_alpha"
const COMMANDER_BETA_ID: StringName = &"commander.test_beta"
const COMMANDER_GAMMA_ID: StringName = &"commander.test_gamma"
const COMMANDER_DELTA_ID: StringName = &"commander.test_delta"

const UNIT_ALPHA_RECRUIT: StringName = &"unit.test_alpha_recruit"
const UNIT_BETA_RECRUIT: StringName = &"unit.test_beta_recruit"
const UNIT_GAMMA_RECRUIT_A: StringName = &"unit.test_gamma_recruit_a"
const UNIT_GAMMA_RECRUIT_B: StringName = &"unit.test_gamma_recruit_b"
## In catalog() but in nobody's starting_pack: proves the bootstrapped pool is the
## WHOLE catalog pool, not just the defs the commander deals out.
const UNIT_SHOP_ONLY: StringName = &"unit.test_shop_only"
## In commander_delta's starting_pack but NOT in catalog(): a commander-exclusive
## unit, which must still get a player-only pool entry.
const UNIT_DELTA_EXCLUSIVE: StringName = &"unit.test_delta_exclusive"

## Copies per unit in catalog()'s pool: every catalog unit is cost_tier 1, and
## EconomyTestFixture's pool_copies_by_tier gives tier 1 this many copies.
const CATALOG_TIER_1_COPIES: int = 18

## Three commanders with distinct starting packs / passive refs / population
## bonuses (design.md SS12 row 002's "三起始包/被動 refs 不同").
static func commander_alpha() -> CommanderDef:
	var def := CommanderDef.new()
	def.id = COMMANDER_ALPHA_ID
	def.display_name_key = &"loc.commander_test_alpha"
	def.starting_pack = [_amount(UNIT_ALPHA_RECRUIT, 2)]
	def.passive_effect_refs = [&"effect.test_alpha_passive"]
	def.population_bonus = 1
	return def

static func commander_beta() -> CommanderDef:
	var def := CommanderDef.new()
	def.id = COMMANDER_BETA_ID
	def.display_name_key = &"loc.commander_test_beta"
	def.starting_pack = [_amount(UNIT_BETA_RECRUIT, 1)]
	def.passive_effect_refs = [&"effect.test_beta_passive"]
	def.population_bonus = 0
	return def

static func commander_gamma() -> CommanderDef:
	var def := CommanderDef.new()
	def.id = COMMANDER_GAMMA_ID
	def.display_name_key = &"loc.commander_test_gamma"
	def.starting_pack = [
		_amount(UNIT_GAMMA_RECRUIT_A, 1),
		_amount(UNIT_GAMMA_RECRUIT_B, 2),
	]
	def.passive_effect_refs = [&"effect.test_gamma_passive"]
	def.population_bonus = 2
	return def

## A fourth commander whose starting_pack unit has no ShopUnitRule in catalog()
## (a commander-exclusive recruit) -- the pool entry for it must be player-only.
static func commander_delta() -> CommanderDef:
	var def := CommanderDef.new()
	def.id = COMMANDER_DELTA_ID
	def.display_name_key = &"loc.commander_test_delta"
	def.starting_pack = [_amount(UNIT_DELTA_EXCLUSIVE, 2)]
	def.passive_effect_refs = [&"effect.test_delta_passive"]
	def.population_bonus = 0
	return def

## Same shape as commander_alpha() but with a caller-chosen starting_pack /
## population_bonus, for the guard cases (oversized pack, negative bonus, a pack
## bigger than the catalog pool holds).
static func commander_with(
	starting_pack: Array[ContentAmountDef],
	population_bonus: int = 0
) -> CommanderDef:
	var def := commander_alpha()
	def.starting_pack = starting_pack
	def.population_bonus = population_bonus
	return def

static func amount(content_id: StringName, count: int) -> ContentAmountDef:
	return _amount(content_id, count)

static func _amount(content_id: StringName, count: int) -> ContentAmountDef:
	var amount := ContentAmountDef.new()
	amount.content_id = content_id
	amount.count_u32 = count
	return amount

## A minimal, RunStateValidator.validate_profile()-clean ProfileState with all
## three commanders unlocked by default (callers narrow `unlocked` to exercise
## the EXPEDITION_COMMANDER_LOCKED rejection). `next_run_serial` defaults to a
## non-zero value so "run_seed changes when next_run_serial changes" is a
## meaningful assertion against a non-trivial baseline.
static func base_profile(
	next_run_serial: int = 5,
	unlocked: Array[StringName] = [COMMANDER_ALPHA_ID, COMMANDER_BETA_ID, COMMANDER_GAMMA_ID],
	records: Array[CommanderChallengeRecordState] = []
) -> ProfileState:
	var ids: Array[StringName] = unlocked.duplicate()
	var empty_discovered: Array[StringName] = []
	var empty_receipts: Array[SettlementReceiptState] = []
	var serial := U64Bits.from_u32(0, next_run_serial)
	assert(serial.ok, "StartExpeditionTestFixture.base_profile() serial must be constructible")
	return ProfileState.new(
		SaveRootFixture.PROFILE_ID,
		serial.value,
		0,
		ids,
		empty_discovered,
		0,
		empty_receipts,
		&"settings.default",
		null,
		records
	)

static func challenge_record(commander_id: StringName, highest_cleared_level: int) -> CommanderChallengeRecordState:
	return CommanderChallengeRecordState.new(commander_id, highest_cleared_level)

## Pinned receipt this fixture's runs pin their content_snapshot to. A
## dedicated selection/manifest digest pair (distinct from SaveRootFixture's
## and other fixtures') so a repository built with this fixture's receipt is
## never confused with another fixture's generation.
static func receipt() -> PinnedCatalogBuildReceipt:
	var base := SaveRootFixture.create_receipt()
	# This fixture's own commander/unit def_ids must be active in the pinned
	# generation, otherwise save()/load() round-trips tombstone them and the run
	# is discarded (mirrors resolve_overflow_test_fixture.gd's equipment_receipt()).
	# NOTE every catalog() unit id must be listed too: a bootstrapped run's pool now
	# carries one entry per catalog unit, and save_json_codec.gd:1896 tombstones a
	# run holding any content id that is not active in the pinned generation.
	var active_ids: Array[StringName] = base.active_entry_ids.duplicate()
	active_ids.append(COMMANDER_ALPHA_ID)
	active_ids.append(COMMANDER_BETA_ID)
	active_ids.append(COMMANDER_GAMMA_ID)
	active_ids.append(COMMANDER_DELTA_ID)
	active_ids.append(UNIT_ALPHA_RECRUIT)
	active_ids.append(UNIT_BETA_RECRUIT)
	active_ids.append(UNIT_GAMMA_RECRUIT_A)
	active_ids.append(UNIT_GAMMA_RECRUIT_B)
	active_ids.append(UNIT_SHOP_ONLY)
	active_ids.append(UNIT_DELTA_EXCLUSIVE)
	active_ids.sort_custom(func(left: StringName, right: StringName) -> bool:
		return String(left) < String(right)
	)
	return PinnedCatalogBuildReceipt.new(
		base.catalog_schema_version,
		base.content_codec_version,
		base.content_version,
		_RECEIPT_SELECTION_DIGEST.repeat(64),
		active_ids,
		base.economy_config_id,
		base.combat_config_id,
		base.reward_table_ids,
		base.map_node_def_ids,
		base.challenge_unlock_def_ids,
		base.meta_reward_table_id,
		_RECEIPT_MANIFEST_DIGEST.repeat(64)
	)

## The pinned-generation EconomyExpeditionCatalog a bootstrapped run deals its unit
## pool from. Built on EconomyTestFixture.catalog() (same config/map-node shape) but
## pinned to receipt().manifest_digest and stocked with this fixture's own units:
## the four starting-pack recruits plus UNIT_SHOP_ONLY, which no commander deals, so
## "the pool is the whole catalog" is observable. Shop odds are extended down to
## level 1 because that is where a fresh run starts (EconomyTestFixture only defines
## levels 3..9; the real content pack -- content/packs/vertical_slice/economy_configs/
## slice_default.tres -- defines 1..9).
static func catalog() -> EconomyExpeditionCatalog:
	var digest := receipt().manifest_digest
	var source := EconomyTestFixture.catalog(digest)
	var config := source.config()
	for level: int in [1, 2]:
		config.shop_odds_by_level.append(ShopOddsRule.new(level, [10000, 0, 0, 0, 0]))
	var units: Array[ShopUnitRule] = []
	for unit_id: StringName in [
		UNIT_ALPHA_RECRUIT, UNIT_BETA_RECRUIT, UNIT_GAMMA_RECRUIT_A,
		UNIT_GAMMA_RECRUIT_B, UNIT_SHOP_ONLY,
	]:
		units.append(ShopUnitRule.new(unit_id, 1, 1))
	var nodes: Array[MapNodeRule] = []
	for kind: int in range(7):
		nodes.append_array(source.map_nodes_for(kind))
	return EconomyExpeditionCatalog.new(digest, config, units, nodes)

## A catalog pinned to a DIFFERENT generation, for the build()/dispatch generation
## guard (its digest can never equal receipt().manifest_digest).
static func foreign_catalog() -> EconomyExpeditionCatalog:
	return EconomyTestFixture.catalog("5".repeat(64))

## SaveRepository wired to this fixture's receipt() so save()/load() round-trips
## accept the fixture's pinned generation (mirrors
## tests/fixtures/build_items/resolve_overflow_test_fixture.gd's
## equipment_receipt()/repository_for() precedent).
static func repository_for(storage: SaveStoragePort) -> SaveRepository:
	return SaveRepository.new(
		storage,
		FakePinnedCatalogReceiptPort.new(receipt()),
		FakeContentIdMigrationPort.new(),
		RunStateValidator.new()
	)

## Constructs a CampController AND seeds `repository` with `profile`'s initial
## committed state via CampSaveRootFactory (mirrors PurchaseUnlockTestFixture's
## controller_for(): AppRoot always loads a profile from the repository before
## constructing CampController -- design.md SS4.4 -- so the repository must
## already hold that profile's content).
## Both SaveRoot factories are pinned to the same app_version and the same fixed
## clock, so an unlock purchase and an expedition start write identical version /
## saved_at_utc metadata (W3-F6: dispatch_start_expedition() used to hard-code
## RunSaveRootFactory.new()).
static func controller_for(profile: ProfileState, repository: SaveRepository) -> CampController:
	var content_version := receipt().content_version
	var factory := CampSaveRootFactory.new(APP_VERSION, FixedRunCommitClock.new())
	var run_factory := RunSaveRootFactory.new(APP_VERSION, FixedRunCommitClock.new())
	var seed_result := repository.save(factory.build(profile, content_version))
	assert(seed_result.ok, "StartExpeditionTestFixture.controller_for() seed save must succeed")
	return CampController.new(
		profile, repository, content_version, factory, null, run_factory
	)

## A bare RunBootstrapService for unit-level tests that want to exercise
## RunBootstrapService.build() directly without going through
## StartExpeditionCommand/CampController.
static func bootstrap_service() -> RunBootstrapService:
	return RunBootstrapService.new()
