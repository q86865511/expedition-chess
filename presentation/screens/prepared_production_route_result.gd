class_name PreparedProductionRouteResult
extends RefCounted

var ok: bool
var prepared: PreparedProductionRoute
var error: DiagnosticError


static func success(
	value: PreparedProductionRoute
) -> PreparedProductionRouteResult:
	var result := PreparedProductionRouteResult.new()
	result.ok = true
	result.prepared = value
	return result


static func failure(code: StringName) -> PreparedProductionRouteResult:
	var result := PreparedProductionRouteResult.new()
	result.ok = false
	result.error = DiagnosticError.new(
		code,
		StringName("error.presentation.%s" % String(code).to_lower())
	)
	return result
