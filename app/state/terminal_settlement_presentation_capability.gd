class_name TerminalSettlementPresentationCapability
extends RefCounted

var _repository_identity: Object
var _operation_epoch: int
var _committed_file_digest: String
var _run_id: StringName
var _receipt_id: StringName
var _use_nonce: StringName
var _issuer_nonce: Object
var _consumed: bool = false
var _application_claimed: bool = false


func _init(
	p_repository_identity: Object = null,
	p_operation_epoch: int = -1,
	p_committed_file_digest: String = "",
	p_run_id: StringName = &"",
	p_receipt_id: StringName = &"",
	p_use_nonce: StringName = &"",
	p_issuer_nonce: Object = null
) -> void:
	_repository_identity = p_repository_identity
	_operation_epoch = p_operation_epoch
	_committed_file_digest = p_committed_file_digest
	_run_id = p_run_id
	_receipt_id = p_receipt_id
	_use_nonce = p_use_nonce
	_issuer_nonce = p_issuer_nonce


func _matches(
	repository_identity: Object,
	operation_epoch: int,
	committed_file_digest: String
) -> bool:
	return _repository_identity == repository_identity \
		and _operation_epoch == operation_epoch \
		and _committed_file_digest == committed_file_digest \
		and not _run_id.is_empty() \
		and not _receipt_id.is_empty() \
		and not _use_nonce.is_empty() \
		and not _consumed


func _authorizes_snapshot(snapshot: ResultsPresentationSnapshot) -> bool:
	return (
		snapshot != null
		and snapshot.has_authoritative_pair()
		and snapshot.run_id == _run_id
		and snapshot.receipt_id == _receipt_id
		and snapshot.committed_file_digest == _committed_file_digest
		and snapshot.can_exit_results
	)


func _consume(
	issuer_nonce: Object,
	repository_identity: Object,
	operation_epoch: int,
	committed_file_digest: String,
	snapshot: ResultsPresentationSnapshot
) -> bool:
	if (
		_consumed
		or _issuer_nonce == null
		or _issuer_nonce != issuer_nonce
		or not _matches(
			repository_identity,
			operation_epoch,
			committed_file_digest
		)
		or not _authorizes_snapshot(snapshot)
	):
		return false
	_consumed = true
	return true


func _claim_application_install(snapshot: ResultsPresentationSnapshot) -> bool:
	if (
		_application_claimed
		or _issuer_nonce == null
		or not _consumed
		or not _authorizes_snapshot(snapshot)
	):
		return false
	_application_claimed = true
	return true


func _is_consumed() -> bool:
	return _consumed
