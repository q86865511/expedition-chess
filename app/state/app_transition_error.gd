class_name AppTransitionError
extends RefCounted

const INVALID_EVENT: StringName = &"APP_INVALID_EVENT"
const INVALID_EDGE: StringName = &"APP_INVALID_EDGE"
const COMMIT_REQUIRED: StringName = &"APP_COMMIT_REQUIRED"

var code: StringName
var current_state: int
var event_kind: int

func _init(p_code: StringName, p_current_state: int, p_event_kind: int) -> void:
	code = p_code
	current_state = p_current_state
	event_kind = p_event_kind

func deep_clone() -> AppTransitionError:
	return AppTransitionError.new(code, current_state, event_kind)
