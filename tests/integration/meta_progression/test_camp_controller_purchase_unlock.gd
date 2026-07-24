extends GutTest

## T04 (specs/meta-progression/design.md SS4.1/SS4.3; requirements.md
## S5-AC-011; design.md SS12 test "test_purchase_unlock_success_and_named_failures"
## -- integration half): routes PurchaseUnlockCommand through the real
## CampController.dispatch() copy-validate-save-swap pipeline (not just the
## command's own apply_to() draft) -- mirrors
## tests/integration/build_items/test_forge_equipment_command_transaction.gd's
## storage-fault-injection precedent, proving a rejected purchase (named
## business rule, an invalid post-apply profile, or a storage fault) leaves
## both the canonical in-memory profile and the persisted save completely
## untouched, and that a successful purchase commits atomically with
## run == null / LoadResult.RunStatus.NONE on read-back.

func test_dispatch_success_commits_currency_and_unlocked_ids_atomically() -> void:
	var profile := PurchaseUnlockTestFixture.base_profile(500, [&"commander.alpha"])
	var storage := FakeSaveStorage.new()
	var repository := PurchaseUnlockTestFixture.repository_for(storage)
	add_child_autofree(repository)
	var controller := PurchaseUnlockTestFixture.controller_for(profile, repository)
	var no_prereqs: Array[StringName] = []
	var grants: Array[StringName] = [&"commander.mike"]
	var unlock := PurchaseUnlockTestFixture.make_unlock_def(
		&"unlock.commander_mike", 120, no_prereqs, grants
	)

	var result := controller.dispatch(PurchaseUnlockCommand.new(unlock))

	assert_true(result.ok)
	if not result.ok:
		return
	var expected_ids: Array[StringName] = [&"commander.alpha", &"commander.mike"]
	assert_eq(result.profile.meta_currency, 380)
	assert_eq(result.profile.unlocked_content_ids, expected_ids)
	assert_eq(controller.profile_snapshot().meta_currency, 380)
	assert_eq(controller.profile_snapshot().unlocked_content_ids, expected_ids)

	var loaded := repository.load()
	assert_true(loaded.ok)
	if not loaded.ok:
		return
	assert_eq(loaded.run_status, LoadResult.RunStatus.NONE)
	assert_null(loaded.run)
	assert_eq(loaded.profile.meta_currency, 380)
	assert_eq(loaded.profile.unlocked_content_ids, expected_ids)


func test_dispatch_rejects_insufficient_currency_with_zero_persisted_change() -> void:
	var profile := PurchaseUnlockTestFixture.base_profile(50, [&"commander.alpha"])
	var storage := FakeSaveStorage.new()
	var repository := PurchaseUnlockTestFixture.repository_for(storage)
	add_child_autofree(repository)
	var controller := PurchaseUnlockTestFixture.controller_for(profile, repository)
	var no_prereqs: Array[StringName] = []
	var grants: Array[StringName] = [&"commander.mike"]
	var unlock := PurchaseUnlockTestFixture.make_unlock_def(
		&"unlock.commander_mike", 120, no_prereqs, grants
	)

	var result := controller.dispatch(PurchaseUnlockCommand.new(unlock))

	assert_false(result.ok)
	assert_eq(result.error.code, UnlockPurchaseError.UNLOCK_INSUFFICIENT_CURRENCY)
	_assert_unchanged(controller, repository, 50, [&"commander.alpha"])


func test_dispatch_rejects_already_owned_with_zero_persisted_change() -> void:
	var profile := PurchaseUnlockTestFixture.base_profile(500, [&"commander.alpha"])
	var storage := FakeSaveStorage.new()
	var repository := PurchaseUnlockTestFixture.repository_for(storage)
	add_child_autofree(repository)
	var controller := PurchaseUnlockTestFixture.controller_for(profile, repository)
	var no_prereqs: Array[StringName] = []
	var grants: Array[StringName] = [&"commander.alpha"]
	var unlock := PurchaseUnlockTestFixture.make_unlock_def(
		&"unlock.commander_alpha_again", 10, no_prereqs, grants
	)

	var result := controller.dispatch(PurchaseUnlockCommand.new(unlock))

	assert_false(result.ok)
	assert_eq(result.error.code, UnlockPurchaseError.UNLOCK_ALREADY_OWNED)
	_assert_unchanged(controller, repository, 500, [&"commander.alpha"])


func test_dispatch_rejects_unmet_prerequisite_with_zero_persisted_change() -> void:
	var profile := PurchaseUnlockTestFixture.base_profile(500, [&"commander.alpha"])
	var storage := FakeSaveStorage.new()
	var repository := PurchaseUnlockTestFixture.repository_for(storage)
	add_child_autofree(repository)
	var controller := PurchaseUnlockTestFixture.controller_for(profile, repository)
	var prereqs: Array[StringName] = [&"commander.gamma"]
	var grants: Array[StringName] = [&"commander.mike"]
	var unlock := PurchaseUnlockTestFixture.make_unlock_def(
		&"unlock.commander_mike", 100, prereqs, grants
	)

	var result := controller.dispatch(PurchaseUnlockCommand.new(unlock))

	assert_false(result.ok)
	assert_eq(result.error.code, UnlockPurchaseError.UNLOCK_PREREQUISITE_UNMET)
	_assert_unchanged(controller, repository, 500, [&"commander.alpha"])


func test_dispatch_rejects_missing_unlock_def_as_invalid_command_without_touching_store() -> void:
	var profile := PurchaseUnlockTestFixture.base_profile(500, [&"commander.alpha"])
	var storage := FakeSaveStorage.new()
	var repository := PurchaseUnlockTestFixture.repository_for(storage)
	add_child_autofree(repository)
	var controller := PurchaseUnlockTestFixture.controller_for(profile, repository)

	var result := controller.dispatch(PurchaseUnlockCommand.new(null))

	assert_false(result.ok)
	assert_eq(result.error.code, CampCommandError.INVALID_COMMAND)
	_assert_unchanged(controller, repository, 500, [&"commander.alpha"])


func test_dispatch_rejects_invalid_profile_from_command_before_saving() -> void:
	# design.md SS4.1's "clone→validate→SaveRepository.save→swap": the
	# validate step must be real and independently observable, not merely
	# SaveRepository.save()'s own internal validate_root() call. This double
	# reports ok=true with an out-of-range meta_currency, so only an explicit
	# pre-save RunStateValidator.validate_profile() call can catch it as
	# VALIDATION_FAILED rather than SAVE_FAILED.
	var profile := PurchaseUnlockTestFixture.base_profile(500, [&"commander.alpha"])
	var storage := FakeSaveStorage.new()
	var repository := PurchaseUnlockTestFixture.repository_for(storage)
	add_child_autofree(repository)
	var controller := PurchaseUnlockTestFixture.controller_for(profile, repository)
	var no_prereqs: Array[StringName] = []
	var grants: Array[StringName] = [&"commander.mike"]
	var unlock := PurchaseUnlockTestFixture.make_unlock_def(
		&"unlock.commander_mike", 50, no_prereqs, grants
	)
	var command := PurchaseUnlockCommand.new(unlock, FakeInvalidatingUnlockPurchaseService.new())

	var result := controller.dispatch(command)

	assert_false(result.ok)
	assert_eq(result.error.code, CampCommandError.VALIDATION_FAILED)
	_assert_unchanged(controller, repository, 500, [&"commander.alpha"])


func test_dispatch_save_failure_leaves_canonical_profile_and_store_unchanged() -> void:
	var profile := PurchaseUnlockTestFixture.base_profile(500, [&"commander.alpha"])
	var storage := FakeSaveStorage.new()
	var repository := PurchaseUnlockTestFixture.repository_for(storage)
	add_child_autofree(repository)
	# controller_for() performs one seed save (occurrence 0 of the
	# DIRECTORY/MAIN fault counter); occurrence 1 is this test's own dispatch
	# save attempt -- mirrors
	# test_forge_equipment_command_transaction.gd's DIRECTORY-fault precedent.
	var controller := PurchaseUnlockTestFixture.controller_for(profile, repository)
	storage.inject_fault(StorageFaultKey.new(StorageFaultKey.DIRECTORY, StorageFaultKey.MAIN, 1))
	var no_prereqs: Array[StringName] = []
	var grants: Array[StringName] = [&"commander.mike"]
	var unlock := PurchaseUnlockTestFixture.make_unlock_def(
		&"unlock.commander_mike", 120, no_prereqs, grants
	)

	var result := controller.dispatch(PurchaseUnlockCommand.new(unlock))

	assert_false(result.ok)
	assert_eq(result.error.code, CampCommandError.SAVE_FAILED)
	_assert_unchanged(controller, repository, 500, [&"commander.alpha"])


func _assert_unchanged(
	controller: CampController,
	repository: SaveRepository,
	expected_currency: int,
	expected_ids: Array[StringName]
) -> void:
	assert_eq(controller.profile_snapshot().meta_currency, expected_currency)
	assert_eq(controller.profile_snapshot().unlocked_content_ids, expected_ids)
	var loaded := repository.load()
	assert_true(loaded.ok)
	if not loaded.ok:
		return
	assert_eq(loaded.run_status, LoadResult.RunStatus.NONE)
	assert_eq(loaded.profile.meta_currency, expected_currency)
	assert_eq(loaded.profile.unlocked_content_ids, expected_ids)
