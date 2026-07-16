extends GutTest

func test_speed_one_and_four_publish_identical_committed_result() -> void:
	var setup := _fast_setup()
	var one := _run_coordinator(setup, 1)
	var four := _run_coordinator(setup, 4)
	assert_true(one["ok"], one["error"])
	assert_true(four["ok"], four["error"])
	assert_eq(one["result_hash"], four["result_hash"])
	assert_eq(one["summary_hash"], four["summary_hash"])
	assert_eq(one["event_hash"], four["event_hash"])

func test_result_commit_failure_hides_terminal_then_retry_publishes_once() -> void:
	var setup := _fast_setup()
	var controller := FakeCombatRunController.new(_combat_run(setup), false)
	var coordinator := CombatCoordinator.new(controller)
	var published: Array[BattleEvent] = []
	var result_count := [0]
	coordinator.events_published.connect(func(events: Array[BattleEvent]) -> void:
		for event: BattleEvent in events:
			published.append(event.deep_clone())
	)
	coordinator.result_published.connect(func(_result: BattleResult) -> void:
		result_count[0] += 1
	)
	assert_true(coordinator.begin_or_resume().ok)
	var failed: CombatCoordinatorStepResult = null
	for _index: int in range(10):
		failed = coordinator.advance()
		if not failed.ok:
			break
	assert_not_null(failed)
	assert_false(failed.ok)
	assert_eq(failed.error.code, CombatCoordinatorError.RESULT_COMMIT_FAILED)
	assert_eq(_count_type(published, &"battle_finished"), 0)
	assert_eq(result_count[0], 0)
	controller.record_succeeds = true
	var retried := coordinator.advance()
	assert_true(retried.ok)
	assert_true(retried.result_committed)
	assert_eq(_count_type(published, &"battle_finished"), 1)
	assert_eq(result_count[0], 1)
	assert_true(
		controller.run_snapshot_for_test().resolution_state \
		is BattleResultPendingResolutionState
	)

func test_reload_of_committed_result_never_initializes_or_steps_simulation() -> void:
	var setup := _fast_setup()
	var result := BattleSimulationFixture.run_to_result(setup)
	var run := _combat_run(setup)
	run.resolution_state = BattleResultPendingResolutionState.new(
		String(setup.battle_setup_hash), result
	)
	var controller := FakeCombatRunController.new(run)
	var coordinator := CombatCoordinator.new(controller)
	var observed: Array[BattleResult] = []
	coordinator.result_published.connect(func(value: BattleResult) -> void:
		observed.append(value.deep_clone())
	)
	var resumed := coordinator.begin_or_resume()
	assert_true(resumed.ok)
	assert_true(resumed.resumed_committed_result)
	assert_eq(observed.size(), 1)
	assert_eq(observed[0].result_hash, result.result_hash)
	assert_false(coordinator.advance().ok)
	assert_eq(controller.record_attempts, 0)

func test_pause_advances_zero_ticks_and_invalid_speed_is_rejected() -> void:
	var controller := FakeCombatRunController.new(_combat_run(_fast_setup()))
	var coordinator := CombatCoordinator.new(controller)
	assert_true(coordinator.begin_or_resume().ok)
	coordinator.set_paused(true)
	assert_true(coordinator.is_paused())
	assert_eq(coordinator.advance().ticks_advanced, 0)
	assert_false(coordinator.set_speed(3))
	assert_eq(coordinator.speed(), 1)
	assert_true(coordinator.set_speed(2))
	assert_eq(coordinator.speed(), 2)

func _run_coordinator(setup: BattleSetup, speed: int) -> Dictionary:
	var controller := FakeCombatRunController.new(_combat_run(setup))
	var coordinator := CombatCoordinator.new(controller)
	var events: Array[BattleEvent] = []
	var results: Array[BattleResult] = []
	coordinator.events_published.connect(func(values: Array[BattleEvent]) -> void:
		for event: BattleEvent in values:
			events.append(event.deep_clone())
	)
	coordinator.result_published.connect(func(value: BattleResult) -> void:
		results.append(value.deep_clone())
	)
	var begun := coordinator.begin_or_resume()
	if not begun.ok:
		return {"ok": false, "error": String(begun.error.code)}
	coordinator.set_speed(speed)
	for _index: int in range(100):
		var step := coordinator.advance()
		if not step.ok:
			return {"ok": false, "error": String(step.error.code)}
		if step.result_committed:
			break
	if results.size() != 1:
		return {"ok": false, "error": "result not published"}
	var framed := BattleEventStreamHasher.new().framed_bytes(events)
	return {
		"ok": framed.ok,
		"error": String(framed.error.code) if framed.error != null else "",
		"result_hash": results[0].result_hash,
		"summary_hash": results[0].summary_hash,
		"event_hash": BattleSetupHashBuilder.sha256_hex(framed.canonical_bytes),
	}

func _fast_setup() -> BattleSetup:
	var inputs := BattleSimulationFixture.create_inputs()
	inputs.player_units[0].logical_y = 3
	inputs.player_units[0].logical_x = 3
	inputs.encounter_snapshot.enemy_units[0].logical_y = 4
	inputs.encounter_snapshot.enemy_units[0].logical_x = 3
	inputs.player_units[0].attack = 1000
	return BattleSimulationFixture.build_setup(inputs)

func _combat_run(setup: BattleSetup) -> RunState:
	var run := SaveRootFixture.create_valid_root().run
	run.run_phase = RunState.RunPhase.COMBAT
	run.run_seed = U64Bits.zero()
	run.resolution_state = CombatPendingResolutionState.new(setup)
	return run

func _count_type(events: Array[BattleEvent], type: StringName) -> int:
	var count := 0
	for event: BattleEvent in events:
		if event.type == type:
			count += 1
	return count
