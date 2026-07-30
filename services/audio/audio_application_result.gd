class_name AudioApplicationResult
extends RefCounted

var ok: bool
var snapshot: SettingsSnapshot
var error: DiagnosticError


static func success(p_snapshot: SettingsSnapshot) -> AudioApplicationResult:
	return AudioApplicationResult.new(true, p_snapshot, null)


static func failure(p_error: DiagnosticError) -> AudioApplicationResult:
	return AudioApplicationResult.new(false, null, p_error)


func _init(
	p_ok: bool,
	p_snapshot: SettingsSnapshot,
	p_error: DiagnosticError
) -> void:
	ResultInvariant.require(
		p_ok,
		p_error,
		p_snapshot != null,
		p_snapshot == null
	)
	ok = p_ok
	snapshot = p_snapshot.deep_clone() if p_snapshot != null else null
	error = p_error.deep_clone() if p_error != null else null
