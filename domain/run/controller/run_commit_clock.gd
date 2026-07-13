class_name RunCommitClock
extends RefCounted

func now_utc() -> String:
	return Time.get_datetime_string_from_system(true, false) + "Z"
