class_name BattleEventWindowResult
extends RefCounted

var ok: bool
var window: BattleEventWindow
var error: DiagnosticError


static func failure(p_error: DiagnosticError) -> BattleEventWindowResult:
	return BattleEventWindowResult.new(false, null, p_error)


func _init(
	p_ok: bool = false,
	p_window: BattleEventWindow = null,
	p_error: DiagnosticError = null
) -> void:
	ok = p_ok
	window = p_window.deep_clone() if p_window != null else null
	error = p_error.deep_clone() if p_error != null else null
