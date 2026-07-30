class_name MainMenuSnapshot
extends RefCounted

var can_continue: bool
var can_start: bool
var has_recovery: bool
var active_run_id_display: String
var warning_key: StringName


func deep_clone() -> MainMenuSnapshot:
	var clone := MainMenuSnapshot.new()
	clone.can_continue = can_continue
	clone.can_start = can_start
	clone.has_recovery = has_recovery
	clone.active_run_id_display = active_run_id_display
	clone.warning_key = warning_key
	return clone
