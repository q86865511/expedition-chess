class_name RunPreparationService
extends RefCounted

const PREPARE_INVALID: StringName = &"PREPARED_RUN_INVALID"
const PREPARE_STALE: StringName = &"PREPARED_RUN_STALE"
const PREPARE_CONSUMED: StringName = &"PREPARED_RUN_ALREADY_CONSUMED"

var _save_repository: SaveRepository
var _next_nonce: int = 1
var _revoked_uses: Dictionary = {}


func _init(p_save_repository: SaveRepository) -> void:
	_save_repository = p_save_repository


func prepare(load_result: LoadResult) -> PreparedRunResult:
	if _save_repository == null or load_result == null or not load_result.ok \
		or load_result.run_status != LoadResult.RunStatus.LOADED \
		or load_result.run == null \
		or load_result._committed_digest.is_empty():
		return PreparedRunResult.failure(_error(PREPARE_INVALID))
	var manifest_digest := load_result.run.content_snapshot.manifest_digest_value()
	var nonce := StringName("prepared_run_%d" % _next_nonce)
	_next_nonce += 1
	return PreparedRunResult.success(PreparedRunCapability.new(
		_save_repository._repository_identity_token(),
		_save_repository._current_operation_epoch(),
		load_result._committed_digest,
		StringName(load_result.run.run_id),
		manifest_digest,
		nonce
	))


func consume(
	capability: PreparedRunCapability
) -> PreparedRunConsumeResult:
	if capability == null or _revoked_uses.has(capability._use_nonce):
		return PreparedRunConsumeResult.failure(_error(PREPARE_CONSUMED))
	if capability._repository_identity != _save_repository._repository_identity_token() \
		or not _save_repository._claim_operation_if_epoch(capability._operation_epoch):
		revoke(capability)
		return PreparedRunConsumeResult.failure(_error(PREPARE_STALE))
	var loaded := _save_repository._load_while_owned()
	var committed_digest := _save_repository._committed_file_digest()
	var valid := loaded.ok \
		and loaded.run_status == LoadResult.RunStatus.LOADED \
		and loaded.run != null \
		and capability._matches(
			_save_repository._repository_identity_token(),
			committed_digest,
			StringName(loaded.run.run_id),
			loaded.run.content_snapshot.manifest_digest_value()
		)
	_save_repository._release_writer_ownership()
	revoke(capability)
	if not valid:
		return PreparedRunConsumeResult.failure(_error(PREPARE_STALE))
	return PreparedRunConsumeResult.success(loaded.profile, loaded.run)


func revoke(capability: PreparedRunCapability) -> void:
	if capability != null and not capability._use_nonce.is_empty():
		_revoked_uses[capability._use_nonce] = true


func _error(code: StringName) -> DiagnosticError:
	return DiagnosticError.new(code, &"error.presentation.prepared_run")
