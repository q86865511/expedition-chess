class_name AppEvent
extends RefCounted

enum Kind {
	BOOT_COMPLETED,
	OPEN_CAMP,
	RETURN_TO_MENU,
	START_RUN,
	FINISH_RUN,
	ABANDON_RUN,
	ACKNOWLEDGE_RESULTS,
	ACTIVE_RUN_LOADED,
}

var kind: Kind

func _init(p_kind: Kind) -> void:
	kind = p_kind

func deep_clone() -> AppEvent:
	return AppEvent.new(kind)
