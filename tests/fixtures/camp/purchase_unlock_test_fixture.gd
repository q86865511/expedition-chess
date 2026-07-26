class_name PurchaseUnlockTestFixture
extends RefCounted

## T04 (specs/meta-progression/design.md SS4.1/SS4.3; requirements.md
## S5-AC-011): shared fixtures for CampController / PurchaseUnlockCommand /
## UnlockPurchaseService / CampSaveRootFactory unit and integration tests.
##
## ---------------------------------------------------------------------------
## Test-author contract (design.md does not pin an exact wire signature for
## these T04 types beyond SS3's module diagram and SS4's prose -- the shapes
## below are the test author's binding decision; the implementer must match
## them exactly. Naming and result-object ceremony mirror the established
## RunCommand/CommandResult/CommandError/CommandApplyResult/CommandApplyError
## family in domain/run/controller/, adapted to a ProfileState-scoped
## transaction family per design.md SS4.1 ("新增平行的 CampController").
## ---------------------------------------------------------------------------
##
## New types under domain/run/camp/ (8 files):
##
## 1. UnlockPurchaseError (unlock_purchase_error.gd) -- RefCounted.
##      const UNLOCK_INSUFFICIENT_CURRENCY / UNLOCK_ALREADY_OWNED /
##      UNLOCK_PREREQUISITE_UNMET / INPUT_INVALID: StringName.
##      var code: StringName; var field_path: StringName.
##      _init(code, field_path); deep_clone().
##
## 2. UnlockPurchaseResult (unlock_purchase_result.gd) -- RefCounted.
##      var ok: bool; var profile: ProfileState; var error: UnlockPurchaseError.
##      static success(profile) / static failure(error); ResultInvariant-style
##      mutual exclusion (ok <=> profile != null and error == null).
##
## 3. UnlockPurchaseService (unlock_purchase_service.gd) -- RefCounted.
##      func purchase(profile: ProfileState, unlock_def: UnlockDef) -> UnlockPurchaseResult
##      Pure, deterministic, no RNG (design.md SS13). profile/unlock_def == null
##      -> failure(INPUT_INVALID). Validation order (design.md SS4.3's literal
##      clause order, each independently testable, "分別回具名 error"):
##        a. unlock_def.currency_cost > profile.meta_currency
##           -> failure(UNLOCK_INSUFFICIENT_CURRENCY, &"profile.meta_currency")
##        b. any id in unlock_def.unlocked_content_refs already present in
##           profile.unlocked_content_ids (test-author decision: "未重複持有"
##           is checked against the content ids this unlock would grant, since
##           ProfileState has no separate "purchased unlock ids" ledger --
##           design.md SS4.3's closing sentence "購買紀錄＝unlocked_content_ids"
##           confirms unlocked_content_ids IS the purchase record)
##           -> failure(UNLOCK_ALREADY_OWNED, &"profile.unlocked_content_ids")
##        c. any id in unlock_def.prerequisite_refs NOT present in
##           profile.unlocked_content_ids
##           -> failure(UNLOCK_PREREQUISITE_UNMET, &"profile.unlocked_content_ids")
##        d. success: meta_currency -= currency_cost; unlocked_content_ids =
##           (old ids + unlocked_content_refs) deduplicated and sorted
##           ascending by String() (matches RunStateValidator._sorted_unique_names
##           / ContentSnapshotState._canonicalize_ids convention) -- NOT a
##           blind append; must reposition new ids into canonical sorted order.
##      The returned profile is never the same instance passed in (clone before
##      mutating), and a failing call must leave the CALLER's original profile
##      argument completely untouched (currency, unlocked_content_ids) -- this
##      is what "零變更" is pinned to at the unit level.
##
## 4. PurchaseUnlockCommand (purchase_unlock_command.gd) -- RefCounted.
##      _init(unlock_def: UnlockDef, service: UnlockPurchaseService = null)
##      is_concrete() -> bool  (true iff unlock_def != null)
##      apply_to(profile: ProfileState) -> UnlockPurchaseResult
##        -- thin adapter: not is_concrete() -> failure(INPUT_INVALID);
##        otherwise delegates directly to service.purchase(profile, unlock_def)
##        and returns its result unwrapped (no extra layer of wrapping --
##        test-author simplification vs. the RunCommand family's generic
##        APPLY_REJECTED+diagnostics ceremony, justified by CampController's
##        much smaller command surface in this slice; see camp_controller.gd
##        note below). A single UnlockDef is passed directly (not a catalog+id
##        pair like BuyOfferCommand/DismantleEquipmentCommand) because the
##        caller (ViewModel/AppRoot layer) already resolves exactly which
##        UnlockDef the player selected before constructing this command --
##        unlike a shop's rotating per-slot offers, there is no stateful
##        rotation to resolve an id against.
##
## 5. CampCommandError (camp_command_error.gd) -- RefCounted.
##      const INVALID_COMMAND / VALIDATION_FAILED / SAVE_FAILED /
##      TRANSACTION_BUSY: StringName (namespaced "CAMP_*", structural/
##      mechanical failures of the transaction pipeline itself).
##      var code: StringName; var field_path: StringName. _init/deep_clone.
##      NOTE: when a command's apply_to() rejects for a *domain* reason (e.g.
##      UNLOCK_INSUFFICIENT_CURRENCY), CampController passes that domain code
##      straight through as-is into this same `code` field (no generic
##      "APPLY_FAILED" wrapper, no diagnostics indirection) -- code is an open
##      StringName, not a closed enum, so both namespaces coexist without
##      collision. This is the test author's deliberate simplification vs. the
##      RunCommand family's nested-diagnostic convention (see
##      command_error.gd/command_apply_error.gd): CampController's command
##      surface in this slice is a single command type, so the extra
##      indirection buys nothing yet. A future wave adding
##      StartExpeditionCommand/MetaSettlementCommand may revisit this.
##
## 6. CampCommandResult (camp_command_result.gd) -- RefCounted.
##      var ok: bool; var profile: ProfileState; var error: CampCommandError.
##      static success(profile) / static failure(error); mutual exclusion.
##
## 7. CampSaveRootFactory (camp_save_root_factory.gd) -- RefCounted.
##      _init(app_version: String = "0.2.0", clock: RunCommitClock = null)
##      func build(profile: ProfileState, content_version: String) -> SaveRoot
##        -- always builds with run = null (mirrors RunSaveRootFactory's shape
##        exactly, but RunSaveRootFactory cannot build a null-run root because
##        it reads run.content_snapshot -- design.md SS4.1's stated reason for
##        this file existing at all). schema_version = SaveSchemaContract.CURRENT,
##        rng_version = 1, hash_version = 1, saved_at_utc = clock.now_utc().
##      SCOPE NOTE (deliberately out of scope for T04, see orchestrator prompt
##      "同波邊界": StartExpeditionCommand produces an actual new RunState and
##      will use RunSaveRootFactory once RunBootstrapService (T05) builds one;
##      MetaSettlementCommand (T02, domain/run/meta/) clears an existing run to
##      null but reads a terminal RunState as input. Neither is this factory's
##      concern -- CampSaveRootFactory here is scoped strictly to the
##      "no active run" (profile-only) case that PurchaseUnlockCommand needs.
##
## 8. CampController (camp_controller.gd) -- RefCounted.
##      _init(profile: ProfileState, save_repository: SaveRepository,
##            content_version: String, save_root_factory: CampSaveRootFactory = null,
##            validator: RunStateValidator = null)
##        -- clones profile in (never aliases the caller's instance).
##      func profile_snapshot() -> ProfileState  (deep-clone read accessor,
##        mirrors RunController.roster_snapshot()'s "never the same object
##        graph" contract).
##      func dispatch(command: PurchaseUnlockCommand) -> CampCommandResult
##        -- copy-validate-save-swap (design.md SS4.1's literal phrase):
##        1. command == null or not command.is_concrete()
##           -> failure(CampCommandError.INVALID_COMMAND, &"command"); no clone,
##           no validate, no save attempted.
##        2. reentrant dispatch while a transaction is active
##           -> failure(CampCommandError.TRANSACTION_BUSY, &"transaction").
##        3. clone current profile -> draft; command.apply_to(draft).
##           On failure: propagate the domain error code straight through (see
##           CampCommandError note above) with zero further mutation attempted.
##        4. validate: RunStateValidator.validate_profile(apply_result.profile).
##           On failure -> failure(CampCommandError.VALIDATION_FAILED, ...);
##           save is never attempted. This is a real, distinct, independently
##           observable step -- not merged into the save call's own internal
##           validation (see test_camp_controller_purchase_unlock.gd's
##           "rejects_invalid_profile_from_command_before_saving" case, which
##           injects a service returning an ok=true-but-invalid profile
##           specifically to prove this step is load-bearing).
##        5. save: CampSaveRootFactory.build(profile', content_version) ->
##           SaveRepository.save(candidate). On failure ->
##           failure(CampCommandError.SAVE_FAILED, &"save"); in-memory profile
##           is NOT swapped (canonical state stays at the pre-dispatch value).
##        6. swap: in-memory profile becomes profile' (deep-cloned); return
##           CampCommandResult.success(profile').
##      Only PurchaseUnlockCommand exists in this wave; dispatch()'s parameter
##      type is intentionally narrow (not a shared "CampCommand" base) per the
##      orchestrator prompt's "留...擴充點即可" framing -- a future wave adding
##      StartExpeditionCommand/MetaSettlementCommand is expected to widen this
##      signature (or introduce a shared base type) then, not now.
## ---------------------------------------------------------------------------

const CONTENT_VERSION: String = SaveRootFixture.CONTENT_VERSION

## A minimal, RunStateValidator.validate_profile()-clean ProfileState. Reuses
## SaveRootFixture.PROFILE_ID (already matches the ^[0-9a-f]{32}$ pattern) so
## no new profile_id regex bookkeeping is needed. `unlocked` ids must already
## be in canonical sorted order (callers pick already-sorted fixture ids to
## keep call sites simple; UnlockPurchaseService is what must produce sorted
## output from unsorted grants, not this fixture).
static func base_profile(
	currency: int = 500,
	unlocked: Array[StringName] = [&"commander.alpha"]
) -> ProfileState:
	var ids: Array[StringName] = unlocked.duplicate()
	var empty_discovered: Array[StringName] = []
	var empty_receipts: Array[SettlementReceiptState] = []
	var empty_records: Array[CommanderChallengeRecordState] = []
	return ProfileState.new(
		SaveRootFixture.PROFILE_ID,
		U64Bits.one(),
		currency,
		ids,
		empty_discovered,
		0,
		empty_receipts,
		&"settings.default",
		null,
		empty_records
	)

## Builds an UnlockDef with the given purchase-gating fields. `prerequisite_refs`
## and `unlocked_content_refs` need not be pre-sorted -- UnlockDef itself does
## not enforce ordering (only ProfileState.unlocked_content_ids does, via
## RunStateValidator).
static func make_unlock_def(
	id: StringName,
	currency_cost: int,
	prerequisite_refs: Array[StringName],
	unlocked_content_refs: Array[StringName]
) -> UnlockDef:
	var def := UnlockDef.new()
	def.id = id
	def.unlock_kind = &"purchase"
	def.currency_cost = currency_cost
	def.prerequisite_refs = prerequisite_refs.duplicate()
	def.unlocked_content_refs = unlocked_content_refs.duplicate()
	return def

## SaveRepository wired to the base SaveRootFixture receipt/migration ports.
## No custom receipt extension is needed here (unlike
## tests/fixtures/build_items/equip_dismantle_test_fixture.gd's
## equipment_receipt()): SaveJsonCodec._migrate_profile_names (used for
## ProfileState.unlocked_content_ids/discovered_content_ids) resolves ids via
## the migration port alone and never checks pinned-receipt active_entry_ids
## membership -- unlike the stricter _migrate_required_id path used for
## in-run content refs (e.g. bound equipment def_ids), which is why that other
## fixture needs an extended receipt and this one does not.
static func repository_for(storage: SaveStoragePort) -> SaveRepository:
	return SaveRootFixture.create_repository(storage)

## Constructs a CampController AND seeds `repository` with `profile`'s initial
## committed state via CampSaveRootFactory (mirrors real usage: AppRoot always
## loads a profile from the repository before constructing CampController --
## see design.md SS4.4 -- so the repository must already hold that profile's
## content). Seeding lets tests assert "the persisted state after a rejected
## dispatch equals the state before it" by comparing against a real load()
## instead of an assumption.
static func controller_for(profile: ProfileState, repository: SaveRepository) -> CampController:
	var factory := CampSaveRootFactory.new("0.2.0", FixedRunCommitClock.new())
	var seed_result := repository.save(factory.build(profile, CONTENT_VERSION))
	assert(seed_result.ok, "PurchaseUnlockTestFixture.controller_for() seed save must succeed")
	return CampController.new(profile, repository, CONTENT_VERSION, factory)
