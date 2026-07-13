class_name PersistenceCommitCapability
extends RefCounted

const SAVE: StringName = &"save"
const ACTIVE_RUN_LOAD: StringName = &"active_run_load"

var _repository_nonce: RefCounted
var _use_nonce: RefCounted
var _kind: StringName
var _committed_digest: String

func _init(
	p_repository_nonce: RefCounted,
	p_use_nonce: RefCounted,
	p_kind: StringName,
	p_committed_digest: String
) -> void:
	_repository_nonce = p_repository_nonce
	_use_nonce = p_use_nonce
	_kind = p_kind
	_committed_digest = p_committed_digest

func _matches(
	repository_nonce: RefCounted,
	kind: StringName,
	committed_digest: String
) -> bool:
	return _repository_nonce != null \
		and _repository_nonce == repository_nonce \
		and _use_nonce != null \
		and _kind == kind \
		and _committed_digest == committed_digest

func _use_identity() -> RefCounted:
	return _use_nonce
