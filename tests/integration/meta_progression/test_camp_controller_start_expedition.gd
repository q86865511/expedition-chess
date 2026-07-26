extends GutTest

## T05 (specs/meta-progression/design.md SS4.2; requirements.md S5-AC-002,
## S5-AC-009 前置檢查段; design.md SS12 row 002
## "test_start_expedition_locks_commander_and_excludes_from_board"): routes
## StartExpeditionCommand through the real CampController.dispatch_start_expedition()
## copy-validate-save-swap pipeline (not just the command's own apply_to()
## draft) -- mirrors
## tests/integration/meta_progression/test_camp_controller_purchase_unlock.gd's
## precedent: a rejected start (commander locked / challenge prerequisite
## unmet) leaves both the canonical in-memory profile and the persisted save
## completely untouched (zero-change); a successful start commits profile' and
## the freshly bootstrapped RunState atomically in one SaveRoot.

func test_dispatch_locks_each_commander_distinctly_and_excludes_from_board() -> void:
	var fixtures := [
		[StartExpeditionTestFixture.COMMANDER_ALPHA_ID, StartExpeditionTestFixture.commander_alpha()],
		[StartExpeditionTestFixture.COMMANDER_BETA_ID, StartExpeditionTestFixture.commander_beta()],
		[StartExpeditionTestFixture.COMMANDER_GAMMA_ID, StartExpeditionTestFixture.commander_gamma()],
	]
	var seen_commander_ids: Array[StringName] = []
	var seen_run_ids: Array[String] = []
	# Each expedition consumes one run serial (profile'.next_run_serial + 1), so
	# three successive starts carry distinct serials. run_id is the canonical run
	# key digest of (profile_id, next_run_serial) -- design SS4.2 -- and carries no
	# commander component; distinct serials are what make the ids distinct (the
	# commander-independence of run_id is pinned separately, below).
	var serial := 5
	for pair: Array in fixtures:
		var commander_id: StringName = pair[0]
		var commander_def: CommanderDef = pair[1]
		var profile := StartExpeditionTestFixture.base_profile(serial)
		serial += 1
		var storage := FakeSaveStorage.new()
		var repository := StartExpeditionTestFixture.repository_for(storage)
		add_child_autofree(repository)
		var controller := StartExpeditionTestFixture.controller_for(profile, repository)
		var command := StartExpeditionCommand.new(
			commander_id, commander_def, 0, StartExpeditionTestFixture.receipt(),
			StartExpeditionTestFixture.catalog()
		)

		var result := controller.dispatch_start_expedition(command)

		assert_true(result.ok, "dispatch must succeed for commander %s" % String(commander_id))
		if not result.ok:
			continue
		assert_eq(result.run.commander_id, commander_id)
		assert_true(result.run.roster_state.board.placements.is_empty())
		for unit: UnitInstance in result.run.roster_state.unit_instances:
			assert_ne(unit.def_id, commander_id)
		assert_false(
			seen_commander_ids.has(result.run.commander_id),
			"each start must lock its OWN commander onto the run"
		)
		seen_commander_ids.append(result.run.commander_id)
		assert_false(
			seen_run_ids.has(result.run.run_id),
			"each distinct next_run_serial must produce a distinct run_id"
		)
		seen_run_ids.append(result.run.run_id)


func test_dispatch_run_id_is_independent_of_the_selected_commander() -> void:
	# design SS4.2: run_key == (profile_id, next_run_serial), with NO commander
	# component. Two starts from the same profile state must therefore agree on
	# run_id no matter which commander is picked -- the invariant that makes the
	# "distinct serial -> distinct run_id" check above meaningful, and the one that
	# breaks first if the run key schema ever grows a commander field.
	var ids: Array[String] = []
	for commander_def: CommanderDef in [
		StartExpeditionTestFixture.commander_alpha(),
		StartExpeditionTestFixture.commander_beta(),
	]:
		var storage := FakeSaveStorage.new()
		var repository := StartExpeditionTestFixture.repository_for(storage)
		add_child_autofree(repository)
		var controller := StartExpeditionTestFixture.controller_for(
			StartExpeditionTestFixture.base_profile(5), repository
		)
		var result := controller.dispatch_start_expedition(StartExpeditionCommand.new(
			commander_def.id, commander_def, 0, StartExpeditionTestFixture.receipt(),
			StartExpeditionTestFixture.catalog()
		))
		assert_true(result.ok, "dispatch must succeed for commander %s" % String(commander_def.id))
		if not result.ok:
			return
		ids.append(result.run.run_id)
	assert_eq(ids.size(), 2)
	assert_eq(ids[0], ids[1], "run_id must not depend on the commander selection")


func test_dispatch_commits_profile_and_run_atomically_and_round_trips() -> void:
	var profile := StartExpeditionTestFixture.base_profile(5)
	var storage := FakeSaveStorage.new()
	var repository := StartExpeditionTestFixture.repository_for(storage)
	add_child_autofree(repository)
	var controller := StartExpeditionTestFixture.controller_for(profile, repository)
	var command := StartExpeditionCommand.new(
		StartExpeditionTestFixture.COMMANDER_ALPHA_ID,
		StartExpeditionTestFixture.commander_alpha(), 0,
		StartExpeditionTestFixture.receipt(), StartExpeditionTestFixture.catalog()
	)

	var result := controller.dispatch_start_expedition(command)

	assert_true(result.ok)
	if not result.ok:
		return
	assert_eq(result.profile.next_run_serial.to_hex(), U64Bits.from_u32(0, 6).value.to_hex())
	assert_eq(result.profile.last_selection.commander_id, StartExpeditionTestFixture.COMMANDER_ALPHA_ID)
	assert_eq(controller.profile_snapshot().next_run_serial.to_hex(), U64Bits.from_u32(0, 6).value.to_hex())

	var loaded := repository.load()
	assert_true(loaded.ok)
	if not loaded.ok:
		return
	assert_eq(loaded.run_status, LoadResult.RunStatus.LOADED)
	assert_not_null(loaded.run)
	assert_eq(loaded.run.commander_id, StartExpeditionTestFixture.COMMANDER_ALPHA_ID)
	assert_eq(loaded.profile.next_run_serial.to_hex(), U64Bits.from_u32(0, 6).value.to_hex())
	assert_eq(loaded.profile.last_selection.commander_id, StartExpeditionTestFixture.COMMANDER_ALPHA_ID)
	# W3-F6: the run-carrying SaveRoot must come from the controller's INJECTED
	# RunSaveRootFactory (fixture app_version + fixed clock), not from a hard-coded
	# RunSaveRootFactory.new() whose defaults differ from the camp factory's.
	var committed := storage.file_bytes(StorageFaultKey.MAIN)
	assert_not_null(committed)
	var committed_text := committed.value.get_string_from_utf8()
	assert_true(
		committed_text.contains('"app_version":"%s"' % StartExpeditionTestFixture.APP_VERSION),
		"the expedition-start save must carry the controller's app_version"
	)
	assert_true(
		committed_text.contains('"saved_at_utc":"%s"' % FixedRunCommitClock.new().now_utc()),
		"the expedition-start save must use the controller's injected clock"
	)


func test_dispatch_rejects_locked_commander_with_zero_persisted_change() -> void:
	var unlocked: Array[StringName] = [StartExpeditionTestFixture.COMMANDER_BETA_ID]
	var profile := StartExpeditionTestFixture.base_profile(5, unlocked)
	var storage := FakeSaveStorage.new()
	var repository := StartExpeditionTestFixture.repository_for(storage)
	add_child_autofree(repository)
	var controller := StartExpeditionTestFixture.controller_for(profile, repository)
	var command := StartExpeditionCommand.new(
		StartExpeditionTestFixture.COMMANDER_ALPHA_ID,
		StartExpeditionTestFixture.commander_alpha(), 0,
		StartExpeditionTestFixture.receipt(), StartExpeditionTestFixture.catalog()
	)

	var result := controller.dispatch_start_expedition(command)

	assert_false(result.ok)
	assert_eq(result.error.code, StartExpeditionError.EXPEDITION_COMMANDER_LOCKED)
	_assert_no_active_run(controller, repository, 5)


func test_dispatch_rejects_challenge_prerequisite_unmet_with_zero_persisted_change() -> void:
	var records: Array[CommanderChallengeRecordState] = [
		StartExpeditionTestFixture.challenge_record(StartExpeditionTestFixture.COMMANDER_ALPHA_ID, 0),
	]
	var profile := StartExpeditionTestFixture.base_profile(
		5, [StartExpeditionTestFixture.COMMANDER_ALPHA_ID], records
	)
	var storage := FakeSaveStorage.new()
	var repository := StartExpeditionTestFixture.repository_for(storage)
	add_child_autofree(repository)
	var controller := StartExpeditionTestFixture.controller_for(profile, repository)
	var command := StartExpeditionCommand.new(
		StartExpeditionTestFixture.COMMANDER_ALPHA_ID,
		StartExpeditionTestFixture.commander_alpha(), 2,
		StartExpeditionTestFixture.receipt(), StartExpeditionTestFixture.catalog()
	)

	var result := controller.dispatch_start_expedition(command)

	assert_false(result.ok)
	assert_eq(result.error.code, StartExpeditionError.EXPEDITION_CHALLENGE_PREREQUISITE_UNMET)
	_assert_no_active_run(controller, repository, 5)


func test_dispatch_rejects_missing_command_as_invalid_without_touching_store() -> void:
	var profile := StartExpeditionTestFixture.base_profile(5)
	var storage := FakeSaveStorage.new()
	var repository := StartExpeditionTestFixture.repository_for(storage)
	add_child_autofree(repository)
	var controller := StartExpeditionTestFixture.controller_for(profile, repository)
	var command := StartExpeditionCommand.new(
		StartExpeditionTestFixture.COMMANDER_ALPHA_ID, null, 0,
		StartExpeditionTestFixture.receipt(), StartExpeditionTestFixture.catalog()
	)

	var result := controller.dispatch_start_expedition(command)

	assert_false(result.ok)
	assert_eq(result.error.code, CampCommandError.INVALID_COMMAND)
	_assert_no_active_run(controller, repository, 5)


func test_dispatch_run_seed_deterministic_from_profile_id_and_next_run_serial() -> void:
	var receipt := StartExpeditionTestFixture.receipt()
	var command_a := StartExpeditionCommand.new(
		StartExpeditionTestFixture.COMMANDER_ALPHA_ID,
		StartExpeditionTestFixture.commander_alpha(), 0, receipt,
		StartExpeditionTestFixture.catalog()
	)
	var command_a_again := StartExpeditionCommand.new(
		StartExpeditionTestFixture.COMMANDER_ALPHA_ID,
		StartExpeditionTestFixture.commander_alpha(), 0, receipt,
		StartExpeditionTestFixture.catalog()
	)
	var command_b := StartExpeditionCommand.new(
		StartExpeditionTestFixture.COMMANDER_ALPHA_ID,
		StartExpeditionTestFixture.commander_alpha(), 0, receipt,
		StartExpeditionTestFixture.catalog()
	)

	var profile_a := StartExpeditionTestFixture.base_profile(5)
	var storage_a := FakeSaveStorage.new()
	var repository_a := StartExpeditionTestFixture.repository_for(storage_a)
	add_child_autofree(repository_a)
	var controller_a := StartExpeditionTestFixture.controller_for(profile_a, repository_a)
	var result_a := controller_a.dispatch_start_expedition(command_a)

	var profile_a_again := StartExpeditionTestFixture.base_profile(5)
	var storage_a_again := FakeSaveStorage.new()
	var repository_a_again := StartExpeditionTestFixture.repository_for(storage_a_again)
	add_child_autofree(repository_a_again)
	var controller_a_again := StartExpeditionTestFixture.controller_for(profile_a_again, repository_a_again)
	var result_a_again := controller_a_again.dispatch_start_expedition(command_a_again)

	var profile_b := StartExpeditionTestFixture.base_profile(6)
	var storage_b := FakeSaveStorage.new()
	var repository_b := StartExpeditionTestFixture.repository_for(storage_b)
	add_child_autofree(repository_b)
	var controller_b := StartExpeditionTestFixture.controller_for(profile_b, repository_b)
	var result_b := controller_b.dispatch_start_expedition(command_b)

	assert_true(result_a.ok and result_a_again.ok and result_b.ok)
	if not (result_a.ok and result_a_again.ok and result_b.ok):
		return
	assert_eq(result_a.run.run_id, result_a_again.run.run_id)
	assert_ne(result_a.run.run_id, result_b.run.run_id)


func _assert_no_active_run(
	controller: CampController,
	repository: SaveRepository,
	expected_next_run_serial: int
) -> void:
	assert_eq(
		controller.profile_snapshot().next_run_serial.to_hex(),
		U64Bits.from_u32(0, expected_next_run_serial).value.to_hex()
	)
	assert_null(controller.profile_snapshot().last_selection)
	var loaded := repository.load()
	assert_true(loaded.ok)
	if not loaded.ok:
		return
	assert_eq(loaded.run_status, LoadResult.RunStatus.NONE)
	assert_null(loaded.run)
	assert_eq(
		loaded.profile.next_run_serial.to_hex(),
		U64Bits.from_u32(0, expected_next_run_serial).value.to_hex()
	)
	assert_null(loaded.profile.last_selection)
