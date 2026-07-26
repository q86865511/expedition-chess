extends GutTest

## T04 (specs/meta-progression/design.md SS4.3; requirements.md S5-AC-011;
## design.md SS12 test "test_purchase_unlock_success_and_named_failures" --
## unit half): UnlockPurchaseService.purchase() is the sole place the three
## named purchase-rejection errors are computed. See
## tests/fixtures/camp/purchase_unlock_test_fixture.gd's header for the full
## binding contract (validation clause order, sorted/unique merge semantics,
## "零變更" == the caller's original ProfileState argument is never mutated).

func test_purchase_succeeds_deducts_currency_and_appends_sorted_unique_ids() -> void:
	var unlocked: Array[StringName] = [&"commander.alpha", &"commander.zulu"]
	var profile := PurchaseUnlockTestFixture.base_profile(500, unlocked)
	var grants: Array[StringName] = [&"commander.mike"]
	var no_prereqs: Array[StringName] = []
	var unlock := PurchaseUnlockTestFixture.make_unlock_def(
		&"unlock.commander_mike", 120, no_prereqs, grants
	)

	var result := UnlockPurchaseService.new().purchase(profile, unlock)

	assert_true(result.ok)
	if not result.ok:
		return
	assert_eq(result.profile.meta_currency, 380)
	var expected: Array[StringName] = [
		&"commander.alpha", &"commander.mike", &"commander.zulu",
	]
	assert_eq(result.profile.unlocked_content_ids, expected)
	assert_true(
		RunStateValidator.new().validate_profile(result.profile).ok,
		"a successful purchase must produce a RunStateValidator-clean profile"
	)
	# the caller's original profile argument is untouched.
	assert_eq(profile.meta_currency, 500)
	assert_eq(profile.unlocked_content_ids, unlocked)


func test_purchase_appends_multiple_new_ids_into_canonical_sorted_order() -> void:
	# input grant order is deliberately NOT sorted, to prove the service
	# re-sorts rather than blindly appending in input/existing order.
	var unlocked: Array[StringName] = [&"commander.alpha"]
	var profile := PurchaseUnlockTestFixture.base_profile(500, unlocked)
	var grants: Array[StringName] = [&"unit.bravo_2", &"unit.bravo_1"]
	var no_prereqs: Array[StringName] = []
	var unlock := PurchaseUnlockTestFixture.make_unlock_def(
		&"unlock.squad_bravo", 50, no_prereqs, grants
	)

	var result := UnlockPurchaseService.new().purchase(profile, unlock)

	assert_true(result.ok)
	if not result.ok:
		return
	var expected: Array[StringName] = [
		&"commander.alpha", &"unit.bravo_1", &"unit.bravo_2",
	]
	assert_eq(result.profile.unlocked_content_ids, expected)


func test_purchase_rejects_insufficient_currency_and_leaves_profile_unchanged() -> void:
	var unlocked: Array[StringName] = [&"commander.alpha"]
	var profile := PurchaseUnlockTestFixture.base_profile(50, unlocked)
	var grants: Array[StringName] = [&"commander.mike"]
	var no_prereqs: Array[StringName] = []
	var unlock := PurchaseUnlockTestFixture.make_unlock_def(
		&"unlock.commander_mike", 120, no_prereqs, grants
	)

	var result := UnlockPurchaseService.new().purchase(profile, unlock)

	assert_false(result.ok)
	assert_eq(result.error.code, UnlockPurchaseError.UNLOCK_INSUFFICIENT_CURRENCY)
	assert_null(result.profile)
	assert_eq(profile.meta_currency, 50)
	assert_eq(profile.unlocked_content_ids, unlocked)


func test_purchase_rejects_already_owned_and_leaves_profile_unchanged() -> void:
	var unlocked: Array[StringName] = [&"commander.alpha"]
	var profile := PurchaseUnlockTestFixture.base_profile(500, unlocked)
	# this unlock's own grant is already present in unlocked_content_ids.
	var grants: Array[StringName] = [&"commander.alpha"]
	var no_prereqs: Array[StringName] = []
	var unlock := PurchaseUnlockTestFixture.make_unlock_def(
		&"unlock.commander_alpha_again", 10, no_prereqs, grants
	)

	var result := UnlockPurchaseService.new().purchase(profile, unlock)

	assert_false(result.ok)
	assert_eq(result.error.code, UnlockPurchaseError.UNLOCK_ALREADY_OWNED)
	assert_null(result.profile)
	assert_eq(profile.meta_currency, 500)
	assert_eq(profile.unlocked_content_ids, unlocked)


func test_purchase_rejects_unmet_prerequisite_and_leaves_profile_unchanged() -> void:
	var unlocked: Array[StringName] = [&"commander.alpha"]
	var profile := PurchaseUnlockTestFixture.base_profile(500, unlocked)
	var grants: Array[StringName] = [&"commander.mike"]
	# &"commander.gamma" has not been unlocked yet.
	var prereqs: Array[StringName] = [&"commander.gamma"]
	var unlock := PurchaseUnlockTestFixture.make_unlock_def(
		&"unlock.commander_mike", 100, prereqs, grants
	)

	var result := UnlockPurchaseService.new().purchase(profile, unlock)

	assert_false(result.ok)
	assert_eq(result.error.code, UnlockPurchaseError.UNLOCK_PREREQUISITE_UNMET)
	assert_null(result.profile)
	assert_eq(profile.meta_currency, 500)
	assert_eq(profile.unlocked_content_ids, unlocked)


func test_purchase_succeeds_when_prerequisite_is_already_unlocked() -> void:
	var unlocked: Array[StringName] = [&"commander.alpha", &"commander.gamma"]
	var profile := PurchaseUnlockTestFixture.base_profile(500, unlocked)
	var grants: Array[StringName] = [&"commander.mike"]
	var prereqs: Array[StringName] = [&"commander.gamma"]
	var unlock := PurchaseUnlockTestFixture.make_unlock_def(
		&"unlock.commander_mike", 100, prereqs, grants
	)

	var result := UnlockPurchaseService.new().purchase(profile, unlock)

	assert_true(result.ok)
	if not result.ok:
		return
	assert_eq(result.profile.meta_currency, 400)
	var expected: Array[StringName] = [
		&"commander.alpha", &"commander.gamma", &"commander.mike",
	]
	assert_eq(result.profile.unlocked_content_ids, expected)


func test_purchase_rejects_null_unlock_def() -> void:
	var profile := PurchaseUnlockTestFixture.base_profile()
	var result := UnlockPurchaseService.new().purchase(profile, null)
	assert_false(result.ok)
	assert_eq(result.error.code, UnlockPurchaseError.INPUT_INVALID)
