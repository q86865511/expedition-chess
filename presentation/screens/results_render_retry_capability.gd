class_name ResultsRenderRetryCapability
extends RefCounted

var _repository_identity: Object
var _receipt_id: StringName
var _installed_presentation_digest: String
var _observation_file_digest: String
# Stable T00 field name retained as the current observation digest. It is no
# longer interpreted as the immutable settlement snapshot digest.
var _committed_file_digest: String
var _fallback_route_generation: int
var _retry_attempt_generation: int
var _use_nonce: StringName
var _operation_epoch: int
var _issuer: Object
var _consumed: bool = false


func _init(
	p_repository_identity: Object = null,
	p_receipt_id: StringName = &"",
	p_installed_presentation_digest: String = "",
	p_observation_file_digest: String = "",
	p_fallback_route_generation: int = -1,
	p_retry_attempt_generation: int = -1,
	p_use_nonce: StringName = &"",
	p_operation_epoch: int = -1,
	p_issuer: Object = null
) -> void:
	_repository_identity = p_repository_identity
	_receipt_id = p_receipt_id
	_installed_presentation_digest = p_installed_presentation_digest
	_observation_file_digest = p_observation_file_digest
	_committed_file_digest = p_observation_file_digest
	_fallback_route_generation = p_fallback_route_generation
	_retry_attempt_generation = p_retry_attempt_generation
	_use_nonce = p_use_nonce
	_operation_epoch = p_operation_epoch
	_issuer = p_issuer


func _matches(
	issuer: Object,
	repository_identity: Object,
	receipt_id: StringName,
	installed_presentation_digest: String,
	observation_file_digest: String,
	fallback_route_generation: int,
	retry_attempt_generation: int,
	operation_epoch: int
) -> bool:
	return (
		not _consumed
		and _issuer != null
		and _issuer == issuer
		and _repository_identity == repository_identity
		and _receipt_id == receipt_id
		and _installed_presentation_digest == installed_presentation_digest
		and _observation_file_digest == observation_file_digest
		and _fallback_route_generation == fallback_route_generation
		and _retry_attempt_generation == retry_attempt_generation
		and _operation_epoch + 1 == operation_epoch
		and not _use_nonce.is_empty()
	)


func _consume() -> bool:
	if _consumed:
		return false
	_consumed = true
	return true
