class_name RetainedRunRecoveryToken
extends RefCounted

var _repository_identity: Object
var _operation_epoch: int
var _committed_file_digest: String
var _expected_run_id: StringName
var _use_nonce: StringName


func _init(
	p_repository_identity: Object = null,
	p_operation_epoch: int = -1,
	p_committed_file_digest: String = "",
	p_expected_run_id: StringName = &"",
	p_use_nonce: StringName = &""
) -> void:
	_repository_identity = p_repository_identity
	_operation_epoch = p_operation_epoch
	_committed_file_digest = p_committed_file_digest
	_expected_run_id = p_expected_run_id
	_use_nonce = p_use_nonce


func is_opaque() -> bool:
	return _expected_run_id.is_empty()


func is_issued() -> bool:
	return (
		_repository_identity != null
		and _operation_epoch >= 0
		and not _committed_file_digest.is_empty()
	)
