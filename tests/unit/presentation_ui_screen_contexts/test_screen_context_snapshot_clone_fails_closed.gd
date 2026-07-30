extends GutTest

## G2 wave2-B L5 regression (fix/g2-ui-review-findings): StagedScreenContext
## and ProductionLiveScreenContext's _clone_snapshot() silently returned null
## for both a legitimately absent snapshot AND an unrecognized snapshot type,
## making the two cases indistinguishable. A future new snapshot type would
## therefore boot a route with a silently missing snapshot instead of failing
## visibly (e.g. a main menu quietly missing buttons). This locks the fix:
## an unrecognized type must set a queryable snapshot_type_error while a
## legitimately absent snapshot must not.

class UnknownSnapshot:
	extends RefCounted


func test_staged_screen_context_flags_unknown_snapshot_type() -> void:
	var known := RunPresentationSnapshot.new()
	known.run_id = &"run.l5.known"
	var staged_known := StagedScreenContext.new(
		&"RUN_MAP", known, null, &"zh_TW", {}
	)
	assert_not_null(staged_known.snapshot, "a recognized snapshot type must still clone")
	assert_eq(staged_known.snapshot_type_error, &"")

	var staged_missing := StagedScreenContext.new(
		&"RUN_MAP", null, null, &"zh_TW", {}
	)
	assert_null(staged_missing.snapshot)
	assert_eq(
		staged_missing.snapshot_type_error,
		&"",
		"a legitimately absent snapshot must not be reported as a type failure"
	)

	var staged_unknown := StagedScreenContext.new(
		&"RUN_MAP", UnknownSnapshot.new(), null, &"zh_TW", {}
	)
	assert_null(
		staged_unknown.snapshot,
		"an unrecognized type still cannot be cloned, so snapshot stays null"
	)
	assert_ne(
		staged_unknown.snapshot_type_error,
		&"",
		"an unrecognized snapshot type must fail closed with a queryable diagnostic"
	)
	assert_ne(
		staged_unknown.snapshot_type_error,
		staged_missing.snapshot_type_error,
		"unknown-type and legitimately-absent must be distinguishable"
	)


func test_production_live_screen_context_flags_unknown_snapshot_type() -> void:
	var known := ResultsPresentationSnapshot.new()
	known.run_id = &"run.l5.known"
	var live_known := ProductionLiveScreenContext.new(&"RESULTS", known)
	assert_not_null(live_known.snapshot, "a recognized snapshot type must still clone")
	assert_eq(live_known.snapshot_type_error, &"")

	var live_missing := ProductionLiveScreenContext.new(&"RESULTS", null)
	assert_null(live_missing.snapshot)
	assert_eq(
		live_missing.snapshot_type_error,
		&"",
		"a legitimately absent snapshot must not be reported as a type failure"
	)

	var live_unknown := ProductionLiveScreenContext.new(
		&"RESULTS", UnknownSnapshot.new()
	)
	assert_null(live_unknown.snapshot)
	assert_ne(
		live_unknown.snapshot_type_error,
		&"",
		"an unrecognized snapshot type must fail closed with a queryable diagnostic"
	)


func test_snapshot_clone_accessor_does_not_repeat_or_lose_the_diagnostic() -> void:
	var staged_unknown := StagedScreenContext.new(
		&"RUN_MAP", UnknownSnapshot.new(), null, &"zh_TW", {}
	)
	var first_error := staged_unknown.snapshot_type_error
	assert_ne(first_error, &"")
	assert_null(staged_unknown.snapshot_clone())
	assert_eq(
		staged_unknown.snapshot_type_error,
		first_error,
		"re-cloning the already-null snapshot must not mutate or clear the diagnostic"
	)
