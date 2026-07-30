class_name RetainedRunRecoveryService
extends RefCounted

var _repository: SaveRepository


func _init(p_repository: SaveRepository) -> void:
	_repository = p_repository


func issue_token(
	loaded: LoadResult,
	expected_run_id: StringName
) -> RetainedRunRecoveryToken:
	if _repository == null:
		return RetainedRunRecoveryToken.new()
	return _repository._issue_retained_run_recovery_token(
		loaded,
		expected_run_id
	)


func discard(token: RetainedRunRecoveryToken) -> SaveResult:
	if _repository == null or token == null:
		return _failure(&"RECOVERY_TOKEN_INVALID", &"recovery.token")
	if token._repository_identity != _repository._repository_identity_token():
		return _failure(&"RECOVERY_TOKEN_WRONG_REPOSITORY", &"recovery.token")
	if token._operation_epoch < 0 \
		or token._committed_file_digest.is_empty():
		return _failure(&"RECOVERY_TOKEN_INVALID", &"recovery.token")
	if not _repository._claim_operation_if_epoch(token._operation_epoch):
		return _failure(&"RECOVERY_TOKEN_STALE", &"recovery.token")
	var result := _repository._discard_retained_run_while_owned(token)
	_repository._release_writer_ownership()
	return result


func _failure(code: StringName, field_path: StringName) -> SaveResult:
	return SaveResult.failure(SaveError.new(code, field_path))
