extends GutTest

const RESOLUTION_KINDS: Array[int] = [
	ResolutionState.Kind.IDLE,
	ResolutionState.Kind.COMBAT_PENDING,
	ResolutionState.Kind.BATTLE_RESULT_PENDING,
	ResolutionState.Kind.REWARD_PENDING,
]

func test_all_resolution_kinds_preserve_full_retry_identity() -> void:
	var harness := ResolutionRetryHarness.new()
	for kind: int in RESOLUTION_KINDS:
		var result := harness.run_case(kind)
		assert_true(
			result.ok,
			"resolution kind %d failed at %s" % [kind, result.field_path]
		)
		if not result.ok:
			continue
		assert_eq(result.after_json, result.before_json, "kind %d canonical bytes" % kind)
		assert_gt(result.before_key_count, 0, "kind %d has complete key ledger" % kind)
		assert_eq(
			result.after_key_count, result.before_key_count,
			"kind %d does not create a retry key" % kind
		)
