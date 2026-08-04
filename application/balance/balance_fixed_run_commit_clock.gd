class_name BalanceFixedRunCommitClock
extends RunCommitClock

const FIXED_UTC: String = "2026-08-02T00:00:00Z"


func now_utc() -> String:
	return FIXED_UTC


func now_unix() -> int:
	return 1785628800
