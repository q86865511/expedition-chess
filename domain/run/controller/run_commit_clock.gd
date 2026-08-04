class_name RunCommitClock
extends RefCounted

func now_utc() -> String:
	return Time.get_datetime_string_from_system(true, false) + "Z"

func now_unix() -> int:
	return int(Time.get_unix_time_from_system())
