extends GutTest


class TransitionSession:
	extends RunPresentationSession

	var current_snapshot := RunPresentationSnapshot.new()
	var next_snapshot := RunPresentationSnapshot.new()
	var dispatch_count: int = 0

	func _init(source_phase: StringName, target_phase: StringName) -> void:
		current_snapshot.run_id = &"run.r14.intent-route-fault"
		current_snapshot.app_phase = source_phase
		current_snapshot.manifest_digest = "manifest.intent-route-fault"
		next_snapshot = current_snapshot.deep_clone()
		next_snapshot.app_phase = target_phase

	func snapshot() -> RunPresentationSnapshot:
		return current_snapshot.deep_clone()

	func dispatch(_intent: RunPresentationIntent) -> RunPresentationResult:
		dispatch_count += 1
		current_snapshot = next_snapshot.deep_clone()
		return RunPresentationResult.success(current_snapshot)


func test_committed_phase_route_fault_revokes_old_lease_and_blocks_reentry() -> void:
	var cases: Array[Dictionary] = [
		{
			"source": &"MAP",
			"target": &"PREPARE",
			"intent": RunPresentationIntent.Kind.ENTER_NODE,
		},
		{
			"source": &"PREPARE",
			"target": &"COMBAT",
			"intent": RunPresentationIntent.Kind.START_OR_RESUME_COMBAT,
		},
		{
			"source": &"REWARD",
			"target": &"MAP",
			"intent": RunPresentationIntent.Kind.ADVANCE_REWARD,
		},
	]
	for item: Dictionary in cases:
		var registry := LiveScreenLeaseRegistry.new()
		var lease := registry.activate(AppStateMachine.State.RUN, 101)
		var session := TransitionSession.new(
			StringName(item.get("source")),
			StringName(item.get("target"))
		)
		var fault_code := StringName(
			"R14_ROUTE_FAULT_%s" % String(item.get("target"))
		)
		var port := LiveScreenIntentPort.new(
			lease,
			registry,
			session,
			func(_result: RunPresentationResult) -> AppActionResult:
				return AppActionResult.failure(
					DiagnosticError.new(
						fault_code,
						&"error.presentation.r14_route_fault"
					)
				)
		)
		var result := port.dispatch(
			RunPresentationIntent.new(int(item.get("intent")))
		)
		assert_false(result.ok)
		assert_true(result.committed)
		assert_not_null(result.snapshot)
		if result.snapshot != null:
			assert_eq(
				result.snapshot.app_phase,
				StringName(item.get("target")),
				"postcommit failure must preserve the new canonical phase"
			)
		assert_eq(result.error.source_code, fault_code)
		assert_false(
			registry.is_active(lease),
			"route activation fault must revoke the stale screen writer lease"
		)
		var replay := port.dispatch(
			RunPresentationIntent.new(int(item.get("intent")))
		)
		assert_eq(
			replay.error.source_code,
			LiveScreenIntentPort.SCREEN_NOT_ACTIVE
		)
		assert_eq(
			session.dispatch_count,
			1,
			"stale control reentry must not redispatch canonical domain work"
		)
