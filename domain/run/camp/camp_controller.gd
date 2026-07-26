class_name CampController
extends RefCounted

## T04 (design.md §4.1; requirements.md S5-AC-011; REQ-TECH-002/004/006):
## profile-scoped copy-validate-save-swap transaction house, parallel to
## RunController (run_controller.gd:147-204) but with ProfileState as the
## subject and run == null SaveRoots written through SaveRepository. Same
## discipline: clone -> validate -> SaveRepository.save -> swap; any failure
## returns a named typed error with zero partial mutation.
##
## dispatch()'s parameter type is intentionally narrow to PurchaseUnlockCommand
## this wave; StartExpeditionCommand / MetaSettlementCommand are expected to
## widen this signature (or introduce a shared base type) in a later wave --
## the copy-validate-save-swap body here is that extension point.

var _profile: ProfileState
var _save_repository: SaveRepository
var _content_version: String
var _save_root_factory: CampSaveRootFactory
var _run_save_root_factory: RunSaveRootFactory
var _validator: RunStateValidator
var _transaction_active: bool = false

func _init(
	p_profile: ProfileState,
	p_save_repository: SaveRepository,
	p_content_version: String,
	p_save_root_factory: CampSaveRootFactory = null,
	p_validator: RunStateValidator = null,
	p_run_save_root_factory: RunSaveRootFactory = null
) -> void:
	# clone in: never alias the caller's ProfileState instance.
	_profile = p_profile.deep_clone()
	_save_repository = p_save_repository
	_content_version = p_content_version
	_save_root_factory = (
		p_save_root_factory
		if p_save_root_factory != null
		else CampSaveRootFactory.new()
	)
	# dispatch_start_expedition() writes a SaveRoot that carries a run, so it needs
	# the run-scoped factory. It is injectable for the same reasons the camp one is:
	# app_version and the commit clock must be a single choice per controller, not
	# one value for unlock purchases and RunSaveRootFactory's defaults for starts.
	_run_save_root_factory = (
		p_run_save_root_factory
		if p_run_save_root_factory != null
		else RunSaveRootFactory.new()
	)
	_validator = p_validator if p_validator != null else RunStateValidator.new()

## Deep-clone read accessor for ViewModels; mirrors RunController.roster_snapshot()'s
## "never the same object graph" contract.
func profile_snapshot() -> ProfileState:
	return _profile.deep_clone()

func dispatch(command: PurchaseUnlockCommand) -> CampCommandResult:
	# 1. structural guard: no clone/validate/save attempted.
	if command == null or not command.is_concrete():
		return CampCommandResult.failure(
			CampCommandError.new(CampCommandError.INVALID_COMMAND, &"command")
		)
	# 2. reentrancy guard.
	if _transaction_active:
		return CampCommandResult.failure(
			CampCommandError.new(CampCommandError.TRANSACTION_BUSY, &"transaction")
		)
	_transaction_active = true
	# 3. Fresh-load the whole persisted root before any profile-only write. A Camp
	#    writer is permitted only when storage explicitly says there is no run;
	#    load failure and every retained-run shape fail closed so this run=null
	#    transaction cannot bypass the expected-run-id discard boundary.
	var stored := _save_repository.load()
	if not stored.ok:
		_transaction_active = false
		return CampCommandResult.failure(
			CampCommandError.new(CampCommandError.LOAD_FAILED, &"save")
		)
	if stored.run_status != LoadResult.RunStatus.NONE:
		_transaction_active = false
		return CampCommandResult.failure(
			CampCommandError.new(CampCommandError.ACTIVE_RUN_EXISTS, &"save.run")
		)
	# 4. The freshly loaded profile is authoritative. This also prevents a stale
	#    CampController instance from overwriting a newer profile-only commit.
	var draft := stored.profile.deep_clone()
	var apply_result := command.apply_to(draft)
	if not apply_result.ok:
		_transaction_active = false
		var apply_field: StringName = (
			apply_result.error.field_path if apply_result.error != null else &"command"
		)
		var apply_code: StringName = (
			apply_result.error.code
			if apply_result.error != null
			else UnlockPurchaseError.INPUT_INVALID
		)
		return CampCommandResult.failure(CampCommandError.new(apply_code, apply_field))
	# 5. validate: a real, independently observable step before any save.
	var validation := _validator.validate_profile(apply_result.profile)
	if not validation.ok:
		_transaction_active = false
		var validation_field: StringName = (
			validation.error.field_path if validation.error != null else &"profile"
		)
		return CampCommandResult.failure(
			CampCommandError.new(CampCommandError.VALIDATION_FAILED, validation_field)
		)
	# 6. save: run == null SaveRoot through the atomic SaveRepository. On
	# failure the in-memory profile is NOT swapped.
	var candidate := _save_root_factory.build(apply_result.profile, _content_version)
	var save_result := _save_repository.save(candidate)
	if not save_result.ok:
		_transaction_active = false
		return CampCommandResult.failure(
			CampCommandError.new(CampCommandError.SAVE_FAILED, &"save")
		)
	# 7. swap: canonical profile becomes the committed draft.
	_profile = apply_result.profile.deep_clone()
	_transaction_active = false
	return CampCommandResult.success(apply_result.profile)

## T05 (design.md §4.2): a SECOND entry point added alongside dispatch(), NOT a
## breaking widening of it -- dispatch() stays PurchaseUnlockCommand-only. Same
## copy-validate-save-swap discipline, but a successful start commits profile'
## AND the freshly bootstrapped RunState atomically in one SaveRoot. The
## candidate is built via the EXISTING RunSaveRootFactory (not CampSaveRootFactory,
## which is scoped to run == null profile-only saves) since the SaveRoot now
## carries an actual run. CampController keeps no in-memory RunState of its own
## (its scope is "no active run"): only the persisted SaveRoot carries it, while
## the returned result still hands `run` back for T11's AppStateMachine transition.
func dispatch_start_expedition(command: StartExpeditionCommand) -> StartExpeditionCampResult:
	# 1. structural guard: no clone/validate/save attempted.
	if command == null or not command.is_concrete():
		return StartExpeditionCampResult.failure(
			CampCommandError.new(CampCommandError.INVALID_COMMAND, &"command")
		)
	# 2. reentrancy guard.
	if _transaction_active:
		return StartExpeditionCampResult.failure(
			CampCommandError.new(CampCommandError.TRANSACTION_BUSY, &"transaction")
		)
	_transaction_active = true
	# 3. Fresh-load and fail closed. A successful start replaces SaveRoot.run, so
	#    only an explicit RunStatus.NONE grants permission to continue. Both a
	#    decoded active run and preserved incompatible run bytes are barriers.
	var stored := _save_repository.load()
	if not stored.ok:
		_transaction_active = false
		return StartExpeditionCampResult.failure(
			CampCommandError.new(CampCommandError.LOAD_FAILED, &"save")
		)
	if stored.run_status != LoadResult.RunStatus.NONE:
		_transaction_active = false
		return StartExpeditionCampResult.failure(
			CampCommandError.new(
				StartExpeditionError.EXPEDITION_ACTIVE_RUN_EXISTS, &"save.run"
			)
		)
	# 4. Use the freshly loaded profile as the transaction subject so a stale
	#    controller cannot overwrite a newer profile-only commit.
	var draft := stored.profile.deep_clone()
	var apply_result := command.apply_to(draft)
	if not apply_result.ok:
		_transaction_active = false
		var apply_field: StringName = (
			apply_result.error.field_path if apply_result.error != null else &"command"
		)
		var apply_code: StringName = (
			apply_result.error.code
			if apply_result.error != null
			else StartExpeditionError.INPUT_INVALID
		)
		return StartExpeditionCampResult.failure(
			CampCommandError.new(apply_code, apply_field)
		)
	# 5. validate: build the candidate profile'+run SaveRoot and run the full
	#    RunStateValidator BEFORE any save (a real, independently observable step).
	var candidate := _run_save_root_factory.build(
		apply_result.profile, apply_result.run
	)
	var validation := _validator.validate_root(candidate)
	if not validation.ok:
		_transaction_active = false
		var validation_field: StringName = (
			validation.error.field_path if validation.error != null else &"root"
		)
		return StartExpeditionCampResult.failure(
			CampCommandError.new(CampCommandError.VALIDATION_FAILED, validation_field)
		)
	# 6. save: profile'+run committed atomically. On failure the in-memory
	#    profile is NOT swapped and no active run is persisted.
	var save_result := _save_repository.save(candidate)
	if not save_result.ok:
		_transaction_active = false
		return StartExpeditionCampResult.failure(
			CampCommandError.new(CampCommandError.SAVE_FAILED, &"save")
		)
	# 7. swap: canonical profile becomes profile'. CampController does not retain
	#    the RunState -- only the persisted SaveRoot does. The SaveResult travels
	#    back untouched: it is the one-time commit proof T11's composition root
	#    hands to AppStateMachine.transition_after_save(START_RUN, ...).
	_profile = apply_result.profile.deep_clone()
	_transaction_active = false
	return StartExpeditionCampResult.success(
		apply_result.profile, apply_result.run, save_result
	)


## S5-AC-008：玩家明示的 compare-and-clear 交易。以交易當下重新 load 的持久化 root
## 為權威，不相信 CampController 建立時的 profile snapshot；expected_run_id 不符、沒有
## active run、load/validation/save 任一失敗都不 swap 記憶體 profile，也不改存檔。
func dispatch_discard_active_run(command: DiscardActiveRunCommand) -> CampCommandResult:
	if command == null or not command.is_concrete():
		return CampCommandResult.failure(CampCommandError.new(
			DiscardActiveRunError.INPUT_INVALID, &"command.expected_run_id"
		))
	if _transaction_active:
		return CampCommandResult.failure(CampCommandError.new(
			CampCommandError.TRANSACTION_BUSY, &"transaction"
		))
	_transaction_active = true
	var loaded := _save_repository.load()
	if not loaded.ok:
		_transaction_active = false
		return CampCommandResult.failure(CampCommandError.new(
			DiscardActiveRunError.LOAD_FAILED, &"save"
		))
	if loaded.run_status != LoadResult.RunStatus.LOADED or loaded.run == null:
		_transaction_active = false
		return CampCommandResult.failure(CampCommandError.new(
			DiscardActiveRunError.NOT_FOUND, &"save.run"
		))
	if loaded.run.run_id != command.expected_run_id:
		_transaction_active = false
		return CampCommandResult.failure(CampCommandError.new(
			DiscardActiveRunError.RUN_CHANGED, &"save.run.run_id"
		))
	var validation := _validator.validate_profile(loaded.profile)
	if not validation.ok:
		_transaction_active = false
		var validation_field: StringName = (
			validation.error.field_path if validation.error != null else &"profile"
		)
		return CampCommandResult.failure(CampCommandError.new(
			CampCommandError.VALIDATION_FAILED, validation_field
		))
	var candidate := _save_root_factory.build(loaded.profile, _content_version)
	var save_result := _save_repository.save(candidate)
	if not save_result.ok:
		_transaction_active = false
		return CampCommandResult.failure(CampCommandError.new(
			CampCommandError.SAVE_FAILED, &"save"
		))
	_profile = loaded.profile.deep_clone()
	_transaction_active = false
	return CampCommandResult.success(loaded.profile)
