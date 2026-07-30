class_name BattleTranscriptInstallResult
extends RefCounted

var ok: bool
var committed: bool
var summary_only: bool
var warning: DiagnosticError
var error: DiagnosticError


static func installed() -> BattleTranscriptInstallResult:
	return BattleTranscriptInstallResult.new(true, true, false, null, null)


static func summary_fallback(
	p_warning: DiagnosticError
) -> BattleTranscriptInstallResult:
	return BattleTranscriptInstallResult.new(true, true, true, p_warning, null)


static func failure(
	p_error: DiagnosticError
) -> BattleTranscriptInstallResult:
	return BattleTranscriptInstallResult.new(false, false, false, null, p_error)


func _init(
	p_ok: bool = false,
	p_committed: bool = false,
	p_summary_only: bool = false,
	p_warning: DiagnosticError = null,
	p_error: DiagnosticError = null
) -> void:
	ok = p_ok
	committed = p_committed
	summary_only = p_summary_only
	warning = p_warning.deep_clone() if p_warning != null else null
	error = p_error.deep_clone() if p_error != null else null
