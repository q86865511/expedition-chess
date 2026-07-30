extends GutTest

const Support = preload(
	"res://tests/unit/presentation_ui_accessibility/accessibility_test_support.gd"
)


func test_precommit_failure_preserves_old_authoritative_state_and_source_error() -> void:
	var script := Support.load_script(self, Support.ERROR_MAPPER_PATH)
	if script == null:
		return
	var mapper: Object = script.new()
	if not Support.require_methods(
		self,
		mapper,
		[&"map_failure"],
		Support.ERROR_MAPPER_PATH
	):
		return

	var old_state := {
		"serial": 40,
		"route": &"CAMP",
		"nested": {"save_digest": "old"},
	}
	var outcome: Variant = mapper.call(
		&"map_failure",
		&"SAVE_IO_FAILURE",
		false,
		old_state
	)
	old_state["serial"] = 999
	(old_state["nested"] as Dictionary)["save_digest"] = "mutated"
	assert_true(outcome is Dictionary)
	if not outcome is Dictionary:
		return
	assert_eq(outcome.get("committed"), false)
	assert_eq(outcome.get("presentation_ok"), false)
	assert_eq(outcome.get("fallback_active"), false)
	assert_eq(outcome.get("retryable"), false)
	assert_eq(outcome.get("source_code"), &"SAVE_IO_FAILURE")
	assert_false(String(outcome.get("message_key", "")).is_empty())
	assert_true(String(outcome.get("message_key", "")).begins_with("error."))
	var preserved: Dictionary = outcome.get("authoritative_state", {})
	assert_eq(preserved.get("serial"), 40)
	assert_eq((preserved.get("nested", {}) as Dictionary).get("save_digest"), "old")


func test_postcommit_route_failure_keeps_new_commit_and_enters_retryable_fallback() -> void:
	var script := Support.load_script(self, Support.ERROR_MAPPER_PATH)
	if script == null:
		return
	var mapper: Object = script.new()
	if not Support.require_methods(
		self,
		mapper,
		[&"map_failure"],
		Support.ERROR_MAPPER_PATH
	):
		return

	var committed_state := {
		"serial": 41,
		"route": &"RESULTS",
		"nested": {"save_digest": "new"},
	}
	var outcome: Variant = mapper.call(
		&"map_failure",
		&"ROUTE_BIND_FAILED",
		true,
		committed_state
	)
	committed_state["serial"] = 999
	(committed_state["nested"] as Dictionary)["save_digest"] = "mutated"
	assert_true(outcome is Dictionary)
	if not outcome is Dictionary:
		return
	assert_eq(outcome.get("committed"), true)
	assert_eq(outcome.get("presentation_ok"), false)
	assert_eq(outcome.get("fallback_active"), true)
	assert_eq(outcome.get("retryable"), true)
	assert_eq(outcome.get("source_code"), &"ROUTE_BIND_FAILED")
	assert_false(String(outcome.get("message_key", "")).is_empty())
	assert_true(String(outcome.get("message_key", "")).begins_with("error."))
	var preserved: Dictionary = outcome.get("authoritative_state", {})
	assert_eq(preserved.get("serial"), 41)
	assert_eq((preserved.get("nested", {}) as Dictionary).get("save_digest"), "new")
