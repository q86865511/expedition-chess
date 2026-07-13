extends GutTest

func test_declared_run_phase_edge_matrix() -> void:
	var allowed: Array[Vector2i] = [
		Vector2i(RunState.RunPhase.MAP, RunState.RunPhase.PREPARE),
		Vector2i(RunState.RunPhase.PREPARE, RunState.RunPhase.COMBAT),
		Vector2i(RunState.RunPhase.COMBAT, RunState.RunPhase.REWARD),
		Vector2i(RunState.RunPhase.COMBAT, RunState.RunPhase.MAP),
		Vector2i(RunState.RunPhase.COMBAT, RunState.RunPhase.PREPARE),
		Vector2i(RunState.RunPhase.REWARD, RunState.RunPhase.MAP),
	]
	for from_phase: int in range(4):
		for to_phase: int in range(4):
			var root := SaveRootFixture.create_valid_root()
			root.run.run_phase = from_phase as RunState.RunPhase
			var storage := FakeSaveStorage.new()
			var repository := SaveRootFixture.create_repository(storage)
			add_child_autofree(repository)
			var controller := _controller_for(root, repository)
			var event := TestRunEvent.new(to_phase as RunState.RunPhase)
			var expected := allowed.has(Vector2i(from_phase, to_phase))
			assert_eq(
				controller.can_transition(event),
				expected,
				"edge %d -> %d" % [from_phase, to_phase]
			)

func test_success_commits_then_swaps_and_publishes_once() -> void:
	var root := SaveRootFixture.create_valid_root()
	var storage := FakeSaveStorage.new()
	var repository := SaveRootFixture.create_repository(storage)
	add_child_autofree(repository)
	var controller := _controller_for(root, repository)
	var probe := ViewPublicationProbe.new()
	controller.view_published.connect(probe.capture)

	var result := controller.dispatch(
		TestMutationCommand.new(TestMutationCommand.Kind.SET_HP, 87)
	)
	assert_true(result.ok)
	assert_eq(result.view_state.expedition_hp, 87)
	assert_eq(result.view_state.publication_serial.to_hex(), "0000000000000001")
	assert_eq(probe.count, 1)
	assert_eq(probe.last_view.expedition_hp, 87)
	var loaded := repository.load()
	assert_true(loaded.ok)
	assert_eq(loaded.run.expedition_hp, 87)

	result.view_state.expedition_hp = -999
	result.view_state.economy.gold = 999
	probe.last_view.expedition_hp = -998
	assert_eq(controller.view_state().expedition_hp, 87)
	assert_eq(controller.view_state().economy.gold, 0)
	assert_eq(probe.count, 1)

func test_transition_commits_phase_and_payload_together() -> void:
	var root := SaveRootFixture.create_valid_root()
	var storage := FakeSaveStorage.new()
	var repository := SaveRootFixture.create_repository(storage)
	add_child_autofree(repository)
	var controller := _controller_for(root, repository)
	var probe := ViewPublicationProbe.new()
	controller.view_published.connect(probe.capture)

	var result := controller.transition(
		TestRunEvent.new(RunState.RunPhase.PREPARE, 76)
	)
	assert_true(result.ok)
	assert_eq(result.view_state.run_phase, RunState.RunPhase.PREPARE)
	assert_eq(result.view_state.expedition_hp, 76)
	assert_eq(probe.count, 1)
	var loaded := repository.load()
	assert_true(loaded.ok)
	assert_eq(loaded.run.run_phase, RunState.RunPhase.PREPARE)
	assert_eq(loaded.run.expedition_hp, 76)

func test_publish_listener_cannot_reenter_and_reorder_commits() -> void:
	var root := SaveRootFixture.create_valid_root()
	var storage := FakeSaveStorage.new()
	var repository := SaveRootFixture.create_repository(storage)
	add_child_autofree(repository)
	var controller := _controller_for(root, repository)
	var reentrant := ReentrantPublicationProbe.new(controller)
	var observer := ViewPublicationProbe.new()
	controller.view_published.connect(reentrant.capture)
	controller.view_published.connect(observer.capture)

	var outer := controller.dispatch(
		TestMutationCommand.new(TestMutationCommand.Kind.SET_HP, 73)
	)
	assert_true(outer.ok)
	assert_eq(reentrant.callback_count, 1)
	assert_not_null(reentrant.result)
	assert_false(reentrant.result.ok)
	assert_eq(reentrant.result.error.code, CommandError.TRANSACTION_BUSY)
	assert_eq(observer.count, 1)
	assert_eq(observer.last_view.publication_serial.to_hex(), "0000000000000001")
	assert_eq(observer.last_view.expedition_hp, 73)
	assert_eq(controller.view_state().publication_serial.to_hex(), "0000000000000001")
	assert_eq(controller.view_state().expedition_hp, 73)

func test_invalid_edge_and_apply_rejection_have_zero_mutation() -> void:
	var root := SaveRootFixture.create_valid_root()
	var storage := FakeSaveStorage.new()
	var repository := SaveRootFixture.create_repository(storage)
	add_child_autofree(repository)
	var controller := _controller_for(root, repository)
	var probe := ViewPublicationProbe.new()
	controller.view_published.connect(probe.capture)
	var before := controller.view_state()

	var invalid := controller.transition(TestRunEvent.new(RunState.RunPhase.COMBAT, 1))
	assert_false(invalid.ok)
	assert_eq(invalid.error.code, RunTransitionError.INVALID_EDGE)
	var rejected := controller.dispatch(TestMutationCommand.new(TestMutationCommand.Kind.REJECT))
	assert_false(rejected.ok)
	assert_eq(rejected.error.code, CommandError.APPLY_FAILED)
	_assert_view_unchanged(before, controller.view_state())
	assert_eq(storage.journal_snapshot().size(), 0)
	assert_eq(probe.count, 0)

func test_validation_failure_discards_draft_before_storage() -> void:
	var root := SaveRootFixture.create_valid_root()
	var storage := FakeSaveStorage.new()
	var repository := SaveRootFixture.create_repository(storage)
	add_child_autofree(repository)
	var session := _session_for(root)
	var controller := _controller_with_session(session, repository)
	var probe := ViewPublicationProbe.new()
	controller.view_published.connect(probe.capture)
	var before_view := controller.view_state()
	var before_run := session.run_snapshot()

	var result := controller.dispatch(
		TestMutationCommand.new(TestMutationCommand.Kind.INVALID_COMMANDER)
	)
	assert_false(result.ok)
	assert_eq(result.error.code, CommandError.VALIDATION_FAILED)
	_assert_view_unchanged(before_view, controller.view_state())
	assert_eq(
		session.run_snapshot().rng_stream_states[0].snapshot.counter.to_hex(),
		before_run.rng_stream_states[0].snapshot.counter.to_hex()
	)
	assert_eq(
		session.run_snapshot().next_transaction_serial.to_hex(),
		before_run.next_transaction_serial.to_hex()
	)
	assert_eq(storage.journal_snapshot().size(), 0)
	assert_eq(probe.count, 0)

func test_command_cannot_replace_the_run_pinned_content_snapshot() -> void:
	var root := SaveRootFixture.create_valid_root()
	var storage := FakeSaveStorage.new()
	var repository := SaveRootFixture.create_repository(storage)
	add_child_autofree(repository)
	var session := _session_for(root)
	var controller := _controller_with_session(session, repository)
	var probe := ViewPublicationProbe.new()
	controller.view_published.connect(probe.capture)
	var before_run := session.run_snapshot()

	var result := controller.dispatch(
		TestMutationCommand.new(TestMutationCommand.Kind.REPLACE_CONTENT_DIGEST)
	)
	assert_false(result.ok)
	assert_eq(result.error.code, CommandError.VALIDATION_FAILED)
	assert_eq(result.error.field_path, &"content_snapshot")
	assert_eq(
		session.run_snapshot().content_snapshot.manifest_digest_value(),
		before_run.content_snapshot.manifest_digest_value()
	)
	assert_eq(
		session.run_snapshot().next_transaction_serial.to_hex(),
		before_run.next_transaction_serial.to_hex()
	)
	assert_eq(storage.journal_snapshot().size(), 0)
	assert_eq(probe.count, 0)

func test_released_catalog_pin_rejects_commit_before_storage() -> void:
	var root := SaveRootFixture.create_valid_root()
	var storage := FakeSaveStorage.new()
	var repository := SaveRootFixture.create_repository(storage)
	add_child_autofree(repository)
	var lease := TestCatalogLease.new(root.run.content_snapshot.manifest_digest_value())
	var session := RunSession.new(root.profile, root.run, lease)
	var controller := _controller_with_session(session, repository)
	lease.release()

	var result := controller.dispatch(
		TestMutationCommand.new(TestMutationCommand.Kind.SET_HP, 61)
	)
	assert_false(result.ok)
	assert_eq(result.error.code, CommandError.VALIDATION_FAILED)
	assert_eq(result.error.field_path, &"content_snapshot.manifest_digest")
	assert_eq(controller.view_state().expedition_hp, 100)
	assert_eq(storage.journal_snapshot().size(), 0)

func test_storage_and_final_readback_failures_never_publish_draft() -> void:
	var faults: Array[StorageFaultKey] = [
		StorageFaultKey.new(StorageFaultKey.DIRECTORY, StorageFaultKey.MAIN, 0),
		StorageFaultKey.new(StorageFaultKey.READ, StorageFaultKey.MAIN, 0),
	]
	for fault: StorageFaultKey in faults:
		var root := SaveRootFixture.create_valid_root()
		var storage := FakeSaveStorage.new()
		storage.inject_fault(fault)
		var repository := SaveRootFixture.create_repository(storage)
		add_child_autofree(repository)
		var session := _session_for(root)
		var controller := _controller_with_session(session, repository)
		var probe := ViewPublicationProbe.new()
		controller.view_published.connect(probe.capture)
		var before := controller.view_state()

		var result := controller.dispatch(
			TestMutationCommand.new(TestMutationCommand.Kind.SET_HP, 42)
		)
		assert_false(result.ok)
		assert_eq(result.error.code, CommandError.SAVE_FAILED)
		_assert_view_unchanged(before, controller.view_state())
		assert_eq(probe.count, 0)

func test_publication_serial_exhaustion_fails_before_save() -> void:
	var root := SaveRootFixture.create_valid_root()
	var storage := FakeSaveStorage.new()
	var repository := SaveRootFixture.create_repository(storage)
	add_child_autofree(repository)
	var session := RunSession.new(
		root.profile,
		root.run,
		TestCatalogLease.new(root.run.content_snapshot.manifest_digest_value()),
		U64Bits.max_value()
	)
	var controller := _controller_with_session(session, repository)
	var result := controller.dispatch(
		TestMutationCommand.new(TestMutationCommand.Kind.SET_HP, 55)
	)
	assert_false(result.ok)
	assert_eq(result.error.code, CommandError.PUBLICATION_SERIAL_EXHAUSTED)
	assert_eq(controller.view_state().publication_serial.to_hex(), "ffffffffffffffff")
	assert_eq(controller.view_state().expedition_hp, 100)
	assert_eq(storage.journal_snapshot().size(), 0)

func _controller_for(root: SaveRoot, repository: SaveRepository) -> RunController:
	return _controller_with_session(_session_for(root), repository)

func _session_for(root: SaveRoot) -> RunSession:
	return RunSession.new(
		root.profile,
		root.run,
		TestCatalogLease.new(root.run.content_snapshot.manifest_digest_value())
	)

func _controller_with_session(
	session: RunSession,
	repository: SaveRepository
) -> RunController:
	var factory := RunSaveRootFactory.new("0.1.0", FixedRunCommitClock.new())
	return RunController.new(session, repository, RunStateValidator.new(), factory)

func _assert_view_unchanged(before: RunViewState, after: RunViewState) -> void:
	assert_eq(after.publication_serial.to_hex(), before.publication_serial.to_hex())
	assert_eq(after.run_id, before.run_id)
	assert_eq(after.run_phase, before.run_phase)
	assert_eq(after.expedition_hp, before.expedition_hp)
	assert_eq(after.economy.gold, before.economy.gold)
