class_name BattlePlaybackCommandResult
extends RefCounted

var ok: bool
var error: DiagnosticError


static func success() -> BattlePlaybackCommandResult:
	return BattlePlaybackCommandResult.new(true, null)


static func failure(p_error: DiagnosticError) -> BattlePlaybackCommandResult:
	return BattlePlaybackCommandResult.new(false, p_error)


func _init(
	p_ok: bool = false,
	p_error: DiagnosticError = null
) -> void:
	ok = p_ok
	error = p_error.deep_clone() if p_error != null else null
