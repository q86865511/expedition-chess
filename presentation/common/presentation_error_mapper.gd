class_name PresentationErrorMapper
extends RefCounted

const _MESSAGE_KEYS: Dictionary = {
	&"SAVE_IO_FAILURE": &"error.save.io_failure",
	&"ROUTE_BIND_FAILED": &"error.presentation.route_bind_failed",
	&"SCENE_BIND_FAILED": &"error.presentation.scene_bind_failed",
	&"RENDER_FAILED": &"error.presentation.render_failed",
}


func map_failure(
	source_code: StringName,
	committed: bool,
	authoritative_state: Dictionary
) -> Dictionary:
	var normalized_source := source_code
	if normalized_source.is_empty():
		normalized_source = &"PRESENTATION_FAILURE_UNKNOWN"
	var message_key: StringName = _MESSAGE_KEYS.get(
		normalized_source,
		&"error.presentation.failure"
	)
	return {
		"committed": committed,
		"presentation_ok": false,
		"fallback_active": committed,
		"retryable": committed,
		"source_code": normalized_source,
		"message_key": message_key,
		"authoritative_state": authoritative_state.duplicate(true),
	}
