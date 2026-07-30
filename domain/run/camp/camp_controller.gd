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
var _mutation_transaction: CampMutationTransaction

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
	_mutation_transaction = CampMutationTransaction.new(
		_save_repository,
		_content_version,
		_save_root_factory,
		_run_save_root_factory,
		_validator
	)

## Deep-clone read accessor for ViewModels; mirrors RunController.roster_snapshot()'s
## "never the same object graph" contract.
func profile_snapshot() -> ProfileState:
	return _profile.deep_clone()

func dispatch(command: PurchaseUnlockCommand) -> CampCommandResult:
	if command == null or not command.is_concrete():
		return CampCommandResult.failure(
			CampCommandError.new(CampCommandError.INVALID_COMMAND, &"command")
		)
	var result := _mutation_transaction.execute(
		CampMutationExpectation.run_free(), command
	) as CampCommandResult
	if result.ok:
		_profile = result.profile.deep_clone()
	return result

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
	if command == null or not command.is_concrete():
		return StartExpeditionCampResult.failure(
			CampCommandError.new(CampCommandError.INVALID_COMMAND, &"command")
		)
	var result := _mutation_transaction.execute(
		CampMutationExpectation.run_free(), command
	) as StartExpeditionCampResult
	if result.ok:
		_profile = result.profile.deep_clone()
	return result


## S5-AC-008：玩家明示的 compare-and-clear 交易。以交易當下重新 load 的持久化 root
## 為權威，不相信 CampController 建立時的 profile snapshot；expected_run_id 不符、沒有
## active run、load/validation/save 任一失敗都不 swap 記憶體 profile，也不改存檔。
func dispatch_discard_active_run(command: DiscardActiveRunCommand) -> CampCommandResult:
	if command == null or not command.is_concrete():
		return CampCommandResult.failure(CampCommandError.new(
			DiscardActiveRunError.INPUT_INVALID, &"command.expected_run_id"
		))
	var result := _mutation_transaction.execute(
		CampMutationExpectation.decoded_run(command.expected_run_id), command
	) as CampCommandResult
	if result.ok:
		_profile = result.profile.deep_clone()
	return result
