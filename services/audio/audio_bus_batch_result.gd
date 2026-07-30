class_name AudioBusBatchResult
extends RefCounted

var ok: bool
var error_code: StringName
var error: DiagnosticError


func _init(p_ok: bool, p_error: DiagnosticError) -> void:
	ResultInvariant.require(p_ok, p_error, true, true)
	ok = p_ok
	error = p_error.deep_clone() if p_error != null else null
	error_code = error.source_code if error != null else &""


static func success() -> AudioBusBatchResult:
	return AudioBusBatchResult.new(true, null)


static func failure(code: StringName) -> AudioBusBatchResult:
	return AudioBusBatchResult.new(
		false,
		DiagnosticError.new(code, &"error.audio.bus_batch")
	)
