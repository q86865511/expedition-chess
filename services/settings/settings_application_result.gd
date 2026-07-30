class_name SettingsApplicationResult
extends RefCounted

var ok: bool
var committed: bool
var presentation_ok: bool
var snapshot: SettingsSnapshot
var error: DiagnosticError


static func success(p_snapshot: SettingsSnapshot) -> SettingsApplicationResult:
	return SettingsApplicationResult.new(true, true, true, p_snapshot, null)


static func failure(p_error: DiagnosticError) -> SettingsApplicationResult:
	return SettingsApplicationResult.new(false, false, false, null, p_error)


static func committed_presentation_failure(
	p_snapshot: SettingsSnapshot,
	p_error: DiagnosticError
) -> SettingsApplicationResult:
	return SettingsApplicationResult.new(false, true, false, p_snapshot, p_error)


func _init(
	p_ok: bool,
	p_committed: bool,
	p_presentation_ok: bool,
	p_snapshot: SettingsSnapshot,
	p_error: DiagnosticError
) -> void:
	ResultInvariant.require(
		p_ok,
		p_error,
		p_snapshot != null and p_presentation_ok,
		not p_presentation_ok
			and (
				(p_committed and p_snapshot != null)
				or (not p_committed and p_snapshot == null)
			)
	)
	ok = p_ok
	committed = p_committed
	presentation_ok = p_presentation_ok
	snapshot = p_snapshot.deep_clone() if p_snapshot != null else null
	error = p_error.deep_clone() if p_error != null else null
