class_name SettingsAdapterPreflightResult
extends RefCounted

var ok: bool
var token: SettingsActivationToken
var error: DiagnosticError


static func success(
	p_token: SettingsActivationToken
) -> SettingsAdapterPreflightResult:
	return SettingsAdapterPreflightResult.new(true, p_token, null)


static func failure(
	p_error: DiagnosticError
) -> SettingsAdapterPreflightResult:
	return SettingsAdapterPreflightResult.new(false, null, p_error)


func _init(
	p_ok: bool,
	p_token: SettingsActivationToken,
	p_error: DiagnosticError
) -> void:
	ResultInvariant.require(
		p_ok,
		p_error,
		p_token != null,
		p_token == null
	)
	ok = p_ok
	token = p_token
	error = p_error.deep_clone() if p_error != null else null
