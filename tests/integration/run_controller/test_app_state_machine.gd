extends GutTest

func test_all_declared_app_edges_are_accepted_with_repository_proofs() -> void:
	var root := SaveRootFixture.create_valid_root()
	var repository := SaveRootFixture.create_repository(FakeSaveStorage.new())
	add_child_autofree(repository)
	var machine := AppStateMachine.new(repository)
	assert_eq(machine.state(), AppStateMachine.State.BOOT)
	assert_true(machine.transition(AppEvent.new(AppEvent.Kind.BOOT_COMPLETED)).ok)
	assert_true(machine.transition(AppEvent.new(AppEvent.Kind.OPEN_CAMP)).ok)
	var start_commit := repository.save(root)
	assert_true(start_commit.ok)
	assert_true(machine.transition_after_save(
		AppEvent.new(AppEvent.Kind.START_RUN), start_commit
	).ok)
	root.run.expedition_hp = 99
	var finish_commit := repository.save(root)
	assert_true(finish_commit.ok)
	assert_true(machine.transition_after_save(
		AppEvent.new(AppEvent.Kind.FINISH_RUN), finish_commit
	).ok)
	assert_true(machine.transition(AppEvent.new(
		AppEvent.Kind.ACKNOWLEDGE_RESULTS
	)).ok)
	assert_true(machine.transition(AppEvent.new(AppEvent.Kind.RETURN_TO_MENU)).ok)
	assert_eq(machine.state(), AppStateMachine.State.MENU)

func test_loaded_active_run_requires_a_repository_issued_load_proof() -> void:
	var root := SaveRootFixture.create_valid_root()
	var repository := SaveRootFixture.create_repository(FakeSaveStorage.new())
	add_child_autofree(repository)
	assert_true(repository.save(root).ok)
	var loaded := repository.load()
	assert_true(loaded.ok)
	assert_eq(loaded.run_status, LoadResult.RunStatus.LOADED)
	var machine := AppStateMachine.new(repository)

	var uncommitted := machine.transition(
		AppEvent.new(AppEvent.Kind.ACTIVE_RUN_LOADED)
	)
	assert_false(uncommitted.ok)
	assert_eq(uncommitted.error.code, AppTransitionError.COMMIT_REQUIRED)
	assert_eq(machine.state(), AppStateMachine.State.BOOT)
	assert_true(machine.transition_after_active_run_load(
		AppEvent.new(AppEvent.Kind.ACTIVE_RUN_LOADED), loaded
	).ok)
	assert_eq(machine.state(), AppStateMachine.State.RUN)

func test_forged_success_result_and_reused_proof_are_rejected() -> void:
	var root := SaveRootFixture.create_valid_root()
	var repository := SaveRootFixture.create_repository(FakeSaveStorage.new())
	add_child_autofree(repository)
	var genuine := repository.save(root)
	assert_true(genuine.ok)
	var forged := SaveResult.success(
		"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
	)

	var first_machine := AppStateMachine.new(repository)
	assert_true(first_machine.transition(AppEvent.new(
		AppEvent.Kind.BOOT_COMPLETED
	)).ok)
	assert_true(first_machine.transition(AppEvent.new(AppEvent.Kind.OPEN_CAMP)).ok)
	var forged_result := first_machine.transition_after_save(
		AppEvent.new(AppEvent.Kind.START_RUN), forged
	)
	assert_false(forged_result.ok)
	assert_eq(forged_result.error.code, AppTransitionError.COMMIT_REQUIRED)
	assert_true(first_machine.transition_after_save(
		AppEvent.new(AppEvent.Kind.START_RUN), genuine
	).ok)

	var second_machine := AppStateMachine.new(repository)
	assert_true(second_machine.transition(AppEvent.new(
		AppEvent.Kind.BOOT_COMPLETED
	)).ok)
	assert_true(second_machine.transition(AppEvent.new(AppEvent.Kind.OPEN_CAMP)).ok)
	var reused := second_machine.transition_after_save(
		AppEvent.new(AppEvent.Kind.START_RUN), genuine
	)
	assert_false(reused.ok)
	assert_eq(reused.error.code, AppTransitionError.COMMIT_REQUIRED)
	assert_eq(second_machine.state(), AppStateMachine.State.CAMP)

func test_invalid_edge_does_not_consume_commit_and_abandon_needs_fresh_save() -> void:
	var root := SaveRootFixture.create_valid_root()
	var repository := SaveRootFixture.create_repository(FakeSaveStorage.new())
	add_child_autofree(repository)
	var commit := repository.save(root)
	var machine := AppStateMachine.new(repository)
	var invalid := machine.transition_after_save(
		AppEvent.new(AppEvent.Kind.START_RUN), commit
	)
	assert_false(invalid.ok)
	assert_eq(invalid.error.code, AppTransitionError.INVALID_EDGE)
	assert_true(machine.transition(AppEvent.new(AppEvent.Kind.BOOT_COMPLETED)).ok)
	assert_true(machine.transition(AppEvent.new(AppEvent.Kind.OPEN_CAMP)).ok)
	assert_true(machine.transition_after_save(
		AppEvent.new(AppEvent.Kind.START_RUN), commit
	).ok)

	var uncommitted := machine.transition(AppEvent.new(AppEvent.Kind.ABANDON_RUN))
	assert_false(uncommitted.ok)
	assert_eq(uncommitted.error.code, AppTransitionError.COMMIT_REQUIRED)
	assert_eq(machine.state(), AppStateMachine.State.RUN)
	var invalid_event := machine.transition(AppEvent.new(AppEvent.Kind.OPEN_CAMP))
	assert_false(invalid_event.ok)
	assert_eq(invalid_event.error.code, AppTransitionError.INVALID_EDGE)
	root.run.expedition_hp = 98
	var abandon_commit := repository.save(root)
	assert_true(abandon_commit.ok)
	assert_true(machine.transition_after_save(
		AppEvent.new(AppEvent.Kind.ABANDON_RUN), abandon_commit
	).ok)
	assert_eq(machine.state(), AppStateMachine.State.CAMP)
