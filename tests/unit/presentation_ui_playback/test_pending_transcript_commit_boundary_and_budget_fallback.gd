extends GutTest

const Support = preload(
	"res://tests/unit/presentation_ui_playback/playback_test_support.gd"
)


func test_precommit_transcript_is_private_and_save_failure_discards_it() -> void:
	var accumulator_script := Support.load_script(self, Support.ACCUMULATOR_PATH)
	if accumulator_script == null:
		return
	var accumulator: Variant = accumulator_script.new(8)
	if not Support.append_events(self, accumulator, Support.events(4)):
		return
	assert_eq(accumulator.call(&"pending_count"), 4)
	assert_eq(
		accumulator.call(&"public_event_count"),
		0,
		"RecordBattleResult save success is the first legal publication boundary"
	)
	if not Support.require_methods(
		self,
		accumulator,
		[&"discard_on_save_failure"],
		Support.ACCUMULATOR_PATH
	):
		return

	accumulator.call(&"discard_on_save_failure")
	assert_eq(accumulator.call(&"pending_count"), 0)
	assert_eq(accumulator.call(&"public_event_count"), 0)
	assert_true(bool(accumulator.call(&"is_revoked")))

	var session := RunPresentationSession.new()
	var rejected: Variant = Support.install_transcript(
		self,
		session,
		accumulator,
		Support.identity("save-failed"),
		256
	)
	if rejected == null:
		return
	assert_false(bool(rejected.get("ok")))
	assert_false(bool(rejected.get("committed")))
	assert_eq(Support.error_code(rejected), &"PENDING_TRANSCRIPT_REVOKED")
	assert_false(session.try_playback().ok)


func test_save_success_seals_transfers_and_clears_the_only_precommit_owner() -> void:
	var accumulator_script := Support.load_script(self, Support.ACCUMULATOR_PATH)
	if accumulator_script == null:
		return
	var source := Support.events(4)
	var original_signatures := Support.event_signatures(source)
	var accumulator: Variant = accumulator_script.new(8)
	if not Support.append_events(self, accumulator, source):
		return
	source[0].sequence = 999
	var session := RunPresentationSession.new()
	var accepted: Variant = Support.install_transcript(
		self,
		session,
		accumulator,
		Support.identity("committed"),
		512
	)
	if accepted == null:
		return

	assert_true(bool(accepted.get("ok")))
	assert_true(bool(accepted.get("committed")))
	assert_false(bool(accepted.get("summary_only")))
	assert_null(accepted.get("warning"))
	assert_eq(accumulator.call(&"pending_count"), 0)
	assert_eq(accumulator.call(&"public_event_count"), 0)
	assert_true(bool(accumulator.call(&"is_revoked")))
	assert_true(session.try_playback().ok)
	var drained := session.drain_playback_window(
		Support.identity("committed"),
		4
	)
	assert_true(drained.ok)
	assert_eq(
		Support.event_signatures(drained.window.events),
		original_signatures,
		"postcommit owner must not alias the simulation producer's event array"
	)


func test_encoded_byte_budget_keeps_commit_and_falls_back_to_summary_warning() -> void:
	var accumulator_script := Support.load_script(self, Support.ACCUMULATOR_PATH)
	if accumulator_script == null:
		return
	var accumulator: Variant = accumulator_script.new(2)
	if not Support.append_events(self, accumulator, Support.events(1)):
		return
	var session := RunPresentationSession.new()
	var fallback: Variant = Support.install_transcript(
		self,
		session,
		accumulator,
		Support.identity("budget"),
		2049
	)
	if fallback == null:
		return

	assert_true(bool(fallback.get("ok")))
	assert_true(bool(fallback.get("committed")))
	assert_true(bool(fallback.get("summary_only")))
	assert_eq(
		Support.warning_code(fallback),
		&"PRESENTATION_TRANSCRIPT_MEMORY_BUDGET_EXCEEDED"
	)
	assert_eq(accumulator.call(&"pending_count"), 0)
	assert_true(bool(accumulator.call(&"is_revoked")))
	assert_true(session.is_committed_summary_only())
	assert_eq(
		session.playback_warning().source_code,
		&"PRESENTATION_TRANSCRIPT_MEMORY_BUDGET_EXCEEDED"
	)
	assert_false(session.try_playback().ok)


func test_combat_coordinator_buffers_before_record_result_commit() -> void:
	var source := FileAccess.get_file_as_string(Support.COORDINATOR_PATH)
	assert_false(source.is_empty(), "CombatCoordinator source must be readable")
	assert_true(
		source.contains("PendingBattleTranscriptAccumulator"),
		"canonical combat events must enter a private precommit accumulator"
	)
	assert_false(
		source.contains("for _index: int in range(_speed)"),
		"production canonical simulation must remain fixed at 1x"
	)
	assert_false(
		source.contains("_publish_live_events("),
		"CombatCoordinator must not publish uncommitted live events"
	)
	assert_true(
		source.find("dispatch(command)") < source.find("_accept_committed_transcript"),
		"transcript transfer must happen only after RecordBattleResult final save succeeds"
	)
