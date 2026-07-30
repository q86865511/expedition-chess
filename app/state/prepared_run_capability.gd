class_name PreparedRunCapability
extends RefCounted

var _repository_identity: Object
var _operation_epoch: int
var _committed_file_digest: String
var _run_id: StringName
var _manifest_digest: String
var _use_nonce: StringName


func _init(
	p_repository_identity: Object = null,
	p_operation_epoch: int = -1,
	p_committed_file_digest: String = "",
	p_run_id: StringName = &"",
	p_manifest_digest: String = "",
	p_use_nonce: StringName = &""
) -> void:
	_repository_identity = p_repository_identity
	_operation_epoch = p_operation_epoch
	_committed_file_digest = p_committed_file_digest
	_run_id = p_run_id
	_manifest_digest = p_manifest_digest
	_use_nonce = p_use_nonce


func _matches(
	repository_identity: Object,
	committed_file_digest: String,
	run_id: StringName,
	manifest_digest: String
) -> bool:
	return _repository_identity == repository_identity \
		and _operation_epoch >= 0 \
		and _committed_file_digest == committed_file_digest \
		and _run_id == run_id \
		and _manifest_digest == manifest_digest \
		and not _use_nonce.is_empty()
