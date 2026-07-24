extends GutTest

## T04 (specs/meta-progression/design.md SS3 module diagram
## "PurchaseUnlockCommand → UnlockPurchaseService"; SS4.3): PurchaseUnlockCommand
## is a thin adapter binding one resolved UnlockDef to UnlockPurchaseService,
## exposing the RunCommand-family-shaped is_concrete()/apply_to() pair (see
## tests/fixtures/camp/purchase_unlock_test_fixture.gd's header for the exact
## contract and why apply_to() returns UnlockPurchaseResult directly rather
## than an extra generic wrapper).

func test_is_concrete_true_when_unlock_def_present() -> void:
	var no_prereqs: Array[StringName] = []
	var grants: Array[StringName] = [&"commander.mike"]
	var unlock := PurchaseUnlockTestFixture.make_unlock_def(
		&"unlock.commander_mike", 100, no_prereqs, grants
	)
	var command := PurchaseUnlockCommand.new(unlock)
	assert_true(command.is_concrete())


func test_is_concrete_false_when_unlock_def_missing() -> void:
	var command := PurchaseUnlockCommand.new(null)
	assert_false(command.is_concrete())


func test_apply_to_rejects_when_not_concrete_without_touching_profile() -> void:
	var profile := PurchaseUnlockTestFixture.base_profile(500)
	var before_currency := profile.meta_currency
	var command := PurchaseUnlockCommand.new(null)

	var result := command.apply_to(profile)

	assert_false(result.ok)
	assert_eq(result.error.code, UnlockPurchaseError.INPUT_INVALID)
	assert_eq(profile.meta_currency, before_currency)


func test_apply_to_delegates_to_default_service_and_returns_success() -> void:
	var no_prereqs: Array[StringName] = []
	var grants: Array[StringName] = [&"commander.mike"]
	var unlock := PurchaseUnlockTestFixture.make_unlock_def(
		&"unlock.commander_mike", 100, no_prereqs, grants
	)
	var profile := PurchaseUnlockTestFixture.base_profile(500, [&"commander.alpha"])
	var command := PurchaseUnlockCommand.new(unlock)

	var result := command.apply_to(profile)

	assert_true(result.ok)
	if not result.ok:
		return
	assert_eq(result.profile.meta_currency, 400)
	assert_true(result.profile.unlocked_content_ids.has(&"commander.mike"))


func test_apply_to_propagates_named_error_from_injected_service() -> void:
	# UnlockPurchaseService is the sole source of the three named errors;
	# this pins that PurchaseUnlockCommand does not swallow or remap them.
	var no_prereqs: Array[StringName] = []
	var grants: Array[StringName] = [&"commander.mike"]
	var unlock := PurchaseUnlockTestFixture.make_unlock_def(
		&"unlock.commander_mike", 1000, no_prereqs, grants
	)
	var profile := PurchaseUnlockTestFixture.base_profile(10, [&"commander.alpha"])
	var command := PurchaseUnlockCommand.new(unlock, UnlockPurchaseService.new())

	var result := command.apply_to(profile)

	assert_false(result.ok)
	assert_eq(result.error.code, UnlockPurchaseError.UNLOCK_INSUFFICIENT_CURRENCY)
	# zero mutation on the command's own draft-producing path either.
	assert_eq(profile.meta_currency, 10)
	assert_eq(profile.unlocked_content_ids, [&"commander.alpha"])


func test_apply_to_uses_injected_service_override() -> void:
	# proves the optional `service` constructor parameter is a real injection
	# seam (used by the CampController integration suite's
	# FakeInvalidatingUnlockPurchaseService to exercise the validate step).
	var no_prereqs: Array[StringName] = []
	var grants: Array[StringName] = [&"commander.mike"]
	var unlock := PurchaseUnlockTestFixture.make_unlock_def(
		&"unlock.commander_mike", 100, no_prereqs, grants
	)
	var profile := PurchaseUnlockTestFixture.base_profile(500, [&"commander.alpha"])
	var command := PurchaseUnlockCommand.new(unlock, FakeInvalidatingUnlockPurchaseService.new())

	var result := command.apply_to(profile)

	assert_true(result.ok)
	if not result.ok:
		return
	assert_eq(result.profile.meta_currency, -1)
