class_name SaveRepositoryResultsRenderRetryAuthority
extends ResultsRenderRetryAuthorityPort

var _repository: SaveRepository
var _issuer: RefCounted = RefCounted.new()


func _init(repository: SaveRepository) -> void:
	_repository = repository


func issue_retry_capability(
	installed_snapshot: ResultsPresentationSnapshot,
	route_generation: int,
	attempt_generation: int
) -> ResultsRenderRetryCapabilityResult:
	if _repository == null:
		return ResultsRenderRetryCapabilityResult.failure(
			_error(&"RESULTS_RETRY_AUTHORITY_UNAVAILABLE")
		)
	var capability := _repository._issue_results_render_retry_capability(
		installed_snapshot,
		route_generation,
		attempt_generation,
		_issuer
	)
	if capability == null:
		return ResultsRenderRetryCapabilityResult.failure(
			_error(&"RESULTS_RETRY_AUTHORITY_STALE")
		)
	return ResultsRenderRetryCapabilityResult.new(true, capability, null)


func consume_retry_capability(
	capability: ResultsRenderRetryCapability,
	installed_snapshot: ResultsPresentationSnapshot,
	route_generation: int,
	attempt_generation: int
) -> bool:
	return (
		_repository != null
		and _repository._consume_results_render_retry_capability(
			capability,
			installed_snapshot,
			route_generation,
			attempt_generation,
			_issuer
		)
	)


func _error(code: StringName) -> DiagnosticError:
	return DiagnosticError.new(
		code,
		&"error.presentation.results_retry_authority"
	)
