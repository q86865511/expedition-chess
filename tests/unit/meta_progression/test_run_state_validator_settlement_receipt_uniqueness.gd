extends GutTest

## T02 (specs/meta-progression/tasks.md AC: "RunStateValidator 對 settlement_receipts
## 重編碼＋去重、重複 tuple 拒載") — S5-AC-007 / REQ-DATA-007 settlement receipt key
## uniqueness at the validator boundary.
##
## Scope note (read before editing): `RunStateValidator.validate_profile` already
## contains this exact check (domain/run/run_state_validator.gd:74-81) — the
## strictly-ascending-by-digest loop over `profile.settlement_receipts`, each
## entry re-encoded via `_runtime_key()` (which calls
## `RuntimeKeySchemaRegistry.reencode_state()` — the "重編碼" requirement) and
## format-checked via `_digest()`/`_is_i32()`. This file adds the test coverage
## that T02's acceptance list calls for; it intentionally does NOT touch
## run_state_validator.gd's implementation because the existing logic already
## satisfies the acceptance wording letter-for-letter (verified by reading the
## source before writing this file). These tests are expected to pass already —
## they are regression coverage for existing correct behavior, not the red
## target of this wave (that is MetaSettlementService/MetaSettlementCommand in
## test_meta_settlement_service.gd and test_meta_settlement_command.gd).
##
## Style mirrors the sibling T03 file
## tests/unit/meta_progression/test_run_state_validator_meta_progression_fields.gd
## (same fixture entry point, same &"profile.settlement_receipts" field-path
## convention, same strict sorted+unique assumption used for every other array
## field in this validator).

func test_profile_validates_with_empty_settlement_receipts() -> void:
	var profile := SaveRootFixture.create_valid_root().profile
	var empty: Array[SettlementReceiptState] = []
	profile.settlement_receipts = empty
	assert_true(RunStateValidator.new().validate_profile(profile).ok)


func test_profile_validates_with_single_well_formed_settlement_receipt() -> void:
	var profile := SaveRootFixture.create_valid_root().profile
	profile.settlement_receipts = [_receipt_for_run("run.fixture.alpha", 5)]
	var result := RunStateValidator.new().validate_profile(profile)
	assert_true(
		result.ok,
		String(result.error.field_path) if result.error != null else "none"
	)


func test_profile_validates_with_multiple_receipts_in_strict_digest_order() -> void:
	var profile := SaveRootFixture.create_valid_root().profile
	var first := _receipt_for_run("run.fixture.alpha", 5)
	var second := _receipt_for_run("run.fixture.beta", -3)
	var ordered := _sorted_by_digest([first, second])
	profile.settlement_receipts = ordered
	var result := RunStateValidator.new().validate_profile(profile)
	assert_true(
		result.ok,
		String(result.error.field_path) if result.error != null else "none"
	)
	# sanity: the two runs really do produce distinct digests, otherwise this
	# test would not be exercising the multi-entry path at all.
	assert_ne(ordered[0].key.digest, ordered[1].key.digest)


func test_profile_rejects_two_receipts_with_the_same_run_id_tuple() -> void:
	# S5-AC-007 / REQ-DATA-007: build_settlement_receipt(run_id) is keyed only on
	# run_id, so two receipts for the SAME run_id necessarily collide on digest
	# (the "重複 tuple" case) -- this is exactly the case the exactly-once
	# writer's idempotent guard exists to prevent from ever being persisted, and
	# the validator must reject it as a defensive backstop even if it were.
	var profile := SaveRootFixture.create_valid_root().profile
	var first := _receipt_for_run("run.fixture.duplicate", 5, SettlementReceiptState.Outcome.COMPLETED)
	var second := _receipt_for_run("run.fixture.duplicate", 0, SettlementReceiptState.Outcome.FAILED)
	profile.settlement_receipts = [first, second]
	var result := RunStateValidator.new().validate_profile(profile)
	assert_false(result.ok, "duplicate run_id settlement_receipt tuple must be rejected")
	assert_eq(result.error.field_path, &"profile.settlement_receipts")


func test_profile_rejects_settlement_receipts_out_of_canonical_digest_order() -> void:
	var profile := SaveRootFixture.create_valid_root().profile
	var first := _receipt_for_run("run.fixture.alpha", 5)
	var second := _receipt_for_run("run.fixture.beta", -3)
	var ordered := _sorted_by_digest([first, second])
	# deliberately reverse the canonical order.
	profile.settlement_receipts = [ordered[1], ordered[0]]
	var result := RunStateValidator.new().validate_profile(profile)
	assert_false(result.ok, "settlement_receipts must be strictly ascending by key digest")
	assert_eq(result.error.field_path, &"profile.settlement_receipts")


func test_profile_rejects_settlement_receipt_whose_key_does_not_reencode() -> void:
	# "重編碼" requirement: the stored key must be reproducible from its own
	# constituent field (run_id) via RuntimeKeySchemaRegistry -- a key whose
	## digest has been tampered with (does not match a fresh encode of its own
	## run_id) must be rejected, not merely format-checked.
	var profile := SaveRootFixture.create_valid_root().profile
	var receipt := _receipt_for_run("run.fixture.alpha", 5)
	var tampered_key := SettlementReceiptKeyState.create(
		receipt.key.run_id, StringName("f".repeat(64))
	)
	profile.settlement_receipts = [
		SettlementReceiptState.new(
			tampered_key, receipt.outcome, receipt.currency_delta, receipt.payload_digest
		)
	]
	var result := RunStateValidator.new().validate_profile(profile)
	assert_false(result.ok, "a settlement_receipt key that fails reencode must be rejected")
	assert_eq(result.error.field_path, &"profile.settlement_receipts")


func test_profile_rejects_settlement_receipt_with_malformed_payload_digest() -> void:
	var profile := SaveRootFixture.create_valid_root().profile
	var receipt := _receipt_for_run("run.fixture.alpha", 5)
	profile.settlement_receipts = [
		SettlementReceiptState.new(receipt.key, receipt.outcome, receipt.currency_delta, "not-a-digest")
	]
	var result := RunStateValidator.new().validate_profile(profile)
	assert_false(result.ok)
	assert_eq(result.error.field_path, &"profile.settlement_receipts")


func _receipt_for_run(
	run_id: String,
	currency_delta: int,
	outcome: SettlementReceiptState.Outcome = SettlementReceiptState.Outcome.COMPLETED
) -> SettlementReceiptState:
	var key_result := RuntimeKeySchemaRegistry.new().build_settlement_receipt(StringName(run_id))
	assert_true(key_result.ok, "fixture run_id must be a valid stable-ascii token")
	var key := key_result.key_state as SettlementReceiptKeyState
	return SettlementReceiptState.new(key, outcome, currency_delta, "b".repeat(64))


func _sorted_by_digest(
	receipts: Array[SettlementReceiptState]
) -> Array[SettlementReceiptState]:
	var ordered := receipts.duplicate()
	ordered.sort_custom(func(left: SettlementReceiptState, right: SettlementReceiptState) -> bool:
		return String(left.key.digest) < String(right.key.digest)
	)
	return ordered
