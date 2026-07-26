extends GutTest

## T04 (specs/meta-progression/design.md SS4.1 "run=null SaveRoot 寫讀通過";
## tasks.md T04 acceptance "run=null SaveRoot 寫讀通過"): CampSaveRootFactory
## is the only factory capable of building a profile-only (run == null)
## SaveRoot -- RunSaveRootFactory cannot, because it reads
## run.content_snapshot.content_version_value() (domain/run/controller/
## run_save_root_factory.gd:14). This suite pins both the built shape and a
## real SaveRepository.save()/load() round trip landing as
## LoadResult.RunStatus.NONE.

func test_build_produces_null_run_root_with_current_schema_and_versions() -> void:
	var profile := PurchaseUnlockTestFixture.base_profile()
	var factory := CampSaveRootFactory.new("0.2.0", FixedRunCommitClock.new())

	var root := factory.build(profile, PurchaseUnlockTestFixture.CONTENT_VERSION)

	assert_null(root.run)
	assert_eq(root.schema_version, SaveSchemaContract.CURRENT)
	assert_eq(root.content_version, PurchaseUnlockTestFixture.CONTENT_VERSION)
	assert_eq(root.rng_version, 1)
	assert_eq(root.hash_version, 1)
	assert_eq(root.profile.meta_currency, profile.meta_currency)


func test_build_accepts_an_arbitrary_content_version_string_when_run_is_null() -> void:
	# RunStateValidator.validate_root() only cross-checks content_version
	# against run.content_snapshot when run != null (run_state_validator.gd:45-52);
	# with run == null this field is unconstrained.
	var profile := PurchaseUnlockTestFixture.base_profile()
	var factory := CampSaveRootFactory.new()

	var root := factory.build(profile, "anything.goes")

	assert_eq(root.content_version, "anything.goes")
	assert_true(RunStateValidator.new().validate_root(root).ok)


func test_build_round_trips_through_save_repository_as_run_status_none() -> void:
	var unlocked: Array[StringName] = [&"commander.alpha", &"commander.mike"]
	var profile := PurchaseUnlockTestFixture.base_profile(280, unlocked)
	var factory := CampSaveRootFactory.new("0.2.0", FixedRunCommitClock.new())
	var root := factory.build(profile, PurchaseUnlockTestFixture.CONTENT_VERSION)
	var storage := FakeSaveStorage.new()
	var repository := PurchaseUnlockTestFixture.repository_for(storage)
	add_child_autofree(repository)

	var save_result := repository.save(root)
	assert_true(save_result.ok)
	if not save_result.ok:
		return

	var loaded := repository.load()
	assert_true(loaded.ok)
	if not loaded.ok:
		return
	assert_eq(loaded.run_status, LoadResult.RunStatus.NONE)
	assert_null(loaded.run)
	assert_eq(loaded.profile.meta_currency, 280)
	assert_eq(loaded.profile.unlocked_content_ids, unlocked)
