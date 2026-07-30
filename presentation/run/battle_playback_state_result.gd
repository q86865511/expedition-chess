class_name BattlePlaybackStateResult
extends RefCounted

var ok: bool
var state: BattlePlaybackState
var error: DiagnosticError


static func failure(p_error: DiagnosticError) -> BattlePlaybackStateResult:
	return BattlePlaybackStateResult.new(false, null, p_error)


func _init(
	p_ok: bool = false,
	p_state: BattlePlaybackState = null,
	p_error: DiagnosticError = null
) -> void:
	ok = p_ok
	state = p_state.deep_clone() if p_state != null else null
	error = p_error.deep_clone() if p_error != null else null
