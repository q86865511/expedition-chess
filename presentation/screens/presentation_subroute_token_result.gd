class_name PresentationSubrouteTokenResult
extends RefCounted

var ok: bool
var token: PresentationSubrouteToken
var error: DiagnosticError


static func success(
	p_token: PresentationSubrouteToken
) -> PresentationSubrouteTokenResult:
	return PresentationSubrouteTokenResult.new(true, p_token, null)


static func failure(
	p_error: DiagnosticError
) -> PresentationSubrouteTokenResult:
	return PresentationSubrouteTokenResult.new(false, null, p_error)


func _init(
	p_ok: bool = false,
	p_token: PresentationSubrouteToken = null,
	p_error: DiagnosticError = null
) -> void:
	ok = p_ok
	token = p_token
	error = p_error.deep_clone() if p_error != null else null
