class_name ResultsRenderRetryAuthorityPort
extends RefCounted


func issue_retry_capability(
	_installed_snapshot: ResultsPresentationSnapshot,
	_route_generation: int,
	_attempt_generation: int
) -> ResultsRenderRetryCapabilityResult:
	return ResultsRenderRetryCapabilityResult.failure(
		DiagnosticError.new(
			&"RESULTS_RETRY_AUTHORITY_UNAVAILABLE",
			&"error.presentation.results_retry_authority"
		)
	)


func consume_retry_capability(
	_capability: ResultsRenderRetryCapability,
	_installed_snapshot: ResultsPresentationSnapshot,
	_route_generation: int,
	_attempt_generation: int
) -> bool:
	return false
