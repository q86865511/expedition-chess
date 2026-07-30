class_name CampMutationTransaction
extends RefCounted

## G2 T05 repository-owned Camp writer boundary. The operation is synchronous
## from ownership claim through fresh read, validation and internal save.

const OPERATION_BUSY: StringName = &"CAMP_OPERATION_BUSY"

var _save_repository: SaveRepository
var _content_version: String
var _save_root_factory: CampSaveRootFactory
var _run_save_root_factory: RunSaveRootFactory
var _validator: RunStateValidator


func _init(
	p_save_repository: SaveRepository,
	p_content_version: String,
	p_save_root_factory: CampSaveRootFactory = null,
	p_run_save_root_factory: RunSaveRootFactory = null,
	p_validator: RunStateValidator = null
) -> void:
	_save_repository = p_save_repository
	_content_version = p_content_version
	_save_root_factory = (
		p_save_root_factory
		if p_save_root_factory != null
		else CampSaveRootFactory.new()
	)
	_run_save_root_factory = (
		p_run_save_root_factory
		if p_run_save_root_factory != null
		else RunSaveRootFactory.new()
	)
	_validator = p_validator if p_validator != null else RunStateValidator.new()


func execute(
	expectation: CampMutationExpectation,
	command: RefCounted
) -> RefCounted:
	if expectation == null or command == null:
		return _invalid_result(command)
	if _save_repository == null or not _save_repository._begin_writer_ownership():
		return _busy_result(command)

	# Capture the repository-issued ownership facts while the writer boundary is
	# held. They are checked again before the internal save.
	var repository_identity: Object = _save_repository._repository_identity_token()
	var operation_epoch: int = _save_repository._current_operation_epoch()
	var loaded := _save_repository._load_while_owned()
	if not loaded.ok:
		_save_repository._release_writer_ownership()
		return _load_failure_result(command)
	var committed_digest := _save_repository._committed_file_digest()
	if not _expectation_matches(expectation, loaded, committed_digest):
		_save_repository._release_writer_ownership()
		return _expectation_failure_result(command, loaded)
	if repository_identity != _save_repository._repository_identity_token() \
		or operation_epoch != _save_repository._current_operation_epoch():
		_save_repository._release_writer_ownership()
		return _busy_result(command)

	var result: RefCounted
	if command is PurchaseUnlockCommand:
		result = _execute_purchase(loaded, command)
	elif command is StartExpeditionCommand:
		result = _execute_start(loaded, command)
	elif command is DiscardActiveRunCommand:
		result = _execute_discard(loaded, command)
	else:
		result = _invalid_result(command)
	_save_repository._release_writer_ownership()
	return result


func _execute_purchase(
	loaded: LoadResult,
	command: PurchaseUnlockCommand
) -> CampCommandResult:
	if not command.is_concrete():
		return _camp_failure(CampCommandError.INVALID_COMMAND, &"command")
	var applied := command.apply_to(loaded.profile.deep_clone())
	if not applied.ok:
		return _camp_failure(
			applied.error.code if applied.error != null else UnlockPurchaseError.INPUT_INVALID,
			applied.error.field_path if applied.error != null else &"command"
		)
	var validation := _validator.validate_profile(applied.profile)
	if not validation.ok:
		return _camp_failure(
			CampCommandError.VALIDATION_FAILED,
			validation.error.field_path if validation.error != null else &"profile"
		)
	var saved := _save_repository._save_while_owned(
		_save_root_factory.build(applied.profile, _content_version)
	)
	if not saved.ok:
		return _camp_failure(CampCommandError.SAVE_FAILED, &"save")
	return CampCommandResult.success(applied.profile)


func _execute_start(
	loaded: LoadResult,
	command: StartExpeditionCommand
) -> StartExpeditionCampResult:
	if not command.is_concrete():
		return _start_failure(CampCommandError.INVALID_COMMAND, &"command")
	var applied := command.apply_to(loaded.profile.deep_clone())
	if not applied.ok:
		return _start_failure(
			applied.error.code if applied.error != null else StartExpeditionError.INPUT_INVALID,
			applied.error.field_path if applied.error != null else &"command"
		)
	var candidate := _run_save_root_factory.build(applied.profile, applied.run)
	var validation := _validator.validate_root(candidate)
	if not validation.ok:
		return _start_failure(
			CampCommandError.VALIDATION_FAILED,
			validation.error.field_path if validation.error != null else &"root"
		)
	var saved := _save_repository._save_while_owned(candidate)
	if not saved.ok:
		return _start_failure(CampCommandError.SAVE_FAILED, &"save")
	return StartExpeditionCampResult.success(applied.profile, applied.run, saved)


func _execute_discard(
	loaded: LoadResult,
	command: DiscardActiveRunCommand
) -> CampCommandResult:
	if not command.is_concrete():
		return _camp_failure(
			DiscardActiveRunError.INPUT_INVALID, &"command.expected_run_id"
		)
	if loaded.run_status != LoadResult.RunStatus.LOADED or loaded.run == null:
		return _camp_failure(DiscardActiveRunError.NOT_FOUND, &"save.run")
	if loaded.run.run_id != command.expected_run_id:
		return _camp_failure(DiscardActiveRunError.RUN_CHANGED, &"save.run.run_id")
	var validation := _validator.validate_profile(loaded.profile)
	if not validation.ok:
		return _camp_failure(
			CampCommandError.VALIDATION_FAILED,
			validation.error.field_path if validation.error != null else &"profile"
		)
	var saved := _save_repository._save_while_owned(
		_save_root_factory.build(loaded.profile, _content_version)
	)
	if not saved.ok:
		return _camp_failure(CampCommandError.SAVE_FAILED, &"save")
	return CampCommandResult.success(loaded.profile)


func _expectation_matches(
	expectation: CampMutationExpectation,
	loaded: LoadResult,
	committed_digest: String
) -> bool:
	if not expectation.expected_committed_file_digest.is_empty() \
		and expectation.expected_committed_file_digest != committed_digest:
		return false
	match expectation.kind:
		CampMutationExpectation.Kind.NONE:
			return loaded.run_status == LoadResult.RunStatus.NONE
		CampMutationExpectation.Kind.DECODED_RUN_ID:
			return loaded.run_status == LoadResult.RunStatus.LOADED \
				and loaded.run != null \
				and loaded.run.run_id == expectation.expected_run_id
		CampMutationExpectation.Kind.OPAQUE_FILE_DIGEST:
			return loaded.run_status == LoadResult.RunStatus.INCOMPATIBLE_PRESERVED \
				and not committed_digest.is_empty()
	return false


func _invalid_result(command: RefCounted) -> RefCounted:
	return (
		_start_failure(CampCommandError.INVALID_COMMAND, &"command")
		if command is StartExpeditionCommand
		else _camp_failure(CampCommandError.INVALID_COMMAND, &"command")
	)


func _busy_result(command: RefCounted) -> RefCounted:
	return (
		_start_failure(OPERATION_BUSY, &"transaction")
		if command is StartExpeditionCommand
		else _camp_failure(OPERATION_BUSY, &"transaction")
	)


func _load_failure_result(command: RefCounted) -> RefCounted:
	return (
		_start_failure(CampCommandError.LOAD_FAILED, &"save")
		if command is StartExpeditionCommand
		else _camp_failure(CampCommandError.LOAD_FAILED, &"save")
	)


func _expectation_failure_result(
	command: RefCounted,
	loaded: LoadResult
) -> RefCounted:
	if command is StartExpeditionCommand:
		return _start_failure(
			StartExpeditionError.EXPEDITION_ACTIVE_RUN_EXISTS, &"save.run"
		)
	if command is DiscardActiveRunCommand:
		if (
			loaded.run_status != LoadResult.RunStatus.LOADED
			or loaded.run == null
		):
			return _camp_failure(DiscardActiveRunError.NOT_FOUND, &"save.run")
		return _camp_failure(
			DiscardActiveRunError.RUN_CHANGED, &"save.run.run_id"
		)
	return _camp_failure(CampCommandError.ACTIVE_RUN_EXISTS, &"save.run")


func _camp_failure(code: StringName, field_path: StringName) -> CampCommandResult:
	return CampCommandResult.failure(CampCommandError.new(code, field_path))


func _start_failure(
	code: StringName,
	field_path: StringName
) -> StartExpeditionCampResult:
	return StartExpeditionCampResult.failure(CampCommandError.new(code, field_path))
