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
	CONTINUE_RUN,
	RETURN_RESULTS_TO_CAMP,
	RETURN_RESULTS_TO_MENU,
}

var kind: Kind

func _init(p_kind: Kind) -> void:
	kind = p_kind

func deep_clone() -> AppEvent:
	return AppEvent.new(kind)
