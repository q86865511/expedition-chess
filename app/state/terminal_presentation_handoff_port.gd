class_name TerminalPresentationHandoffPort
extends RefCounted

const NOT_IMPLEMENTED: StringName = &"TERMINAL_PRESENTATION_HANDOFF_NOT_IMPLEMENTED"


func install_application_handoff(
	_capability: TerminalSettlementPresentationCapability,
	_snapshot: ResultsPresentationSnapshot
) -> AppActionResult:
	return _not_implemented()


func present_installed_handoff() -> AppActionResult:
	return _not_implemented()


func prepare_results_route_generation() -> int:
	# Test/fake ports retain the original single-route default. Production
	# adapters override this and become the sole generation authority.
	return 1


func commit_installed_handoff(
	_capability: InstalledResultsPresentationCapability,
	_snapshot: ResultsPresentationSnapshot
) -> AppActionResult:
	return _not_implemented()


func commit_handoff(
	_capability: TerminalSettlementPresentationCapability,
	_snapshot: ResultsPresentationSnapshot
) -> AppActionResult:
	return _not_implemented()


func _not_implemented() -> AppActionResult:
	return AppActionResult.failure(
		DiagnosticError.new(NOT_IMPLEMENTED, &"error.presentation.handoff_not_implemented")
	)
