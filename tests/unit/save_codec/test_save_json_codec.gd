extends GutTest

func test_schema_one_round_trip_is_byte_identical() -> void:
	var codec := SaveRootFixture.create_codec()
	var encoded := codec.encode(SaveRootFixture.create_valid_root())
	assert_true(encoded.ok)
	var decoded := codec.decode_text(encoded.json_text.value)
	assert_true(decoded.ok)
	assert_not_null(decoded.root)
	var reencoded := codec.encode(decoded.root)
	assert_eq(reencoded.json_text.value, encoded.json_text.value)

func test_unknown_duplicate_and_noncanonical_fields_are_rejected() -> void:
	var codec := SaveRootFixture.create_codec()
	var encoded := codec.encode(SaveRootFixture.create_valid_root())
	var unknown := encoded.json_text.value.replace(
		"{\"schema_version\":1,",
		"{\"schema_version\":1,\"unknown\":0,"
	)
	assert_false(codec.decode_text(unknown).ok)
	var duplicate := encoded.json_text.value.replace(
		"{\"schema_version\":1,",
		"{\"schema_version\":1,\"schema_version\":1,"
	)
	assert_false(codec.decode_text(duplicate).ok)
	var float_number := encoded.json_text.value.replace("\"meta_currency\":0", "\"meta_currency\":0.0")
	assert_false(codec.decode_text(float_number).ok)

func test_decode_bytes_rejects_non_round_trip_utf8_with_named_error() -> void:
	var invalid_utf8 := PackedByteArray([0x80, 0x61])
	var decoded := SaveRootFixture.create_codec().decode_bytes(invalid_utf8)
	assert_false(decoded.ok)
	assert_not_null(decoded.error)
	assert_eq(decoded.error.code, SaveCodecError.UTF8_INVALID)
	assert_eq(decoded.error.field_path, &"bytes")

func test_every_u64_boundary_uses_fixed_lowercase_hex() -> void:
	var values: Array[String] = [
		"0000000000000000", "001fffffffffffff", "0020000000000000",
		"0020000000000001", "8000000000000000", "ffffffffffffffff"
	]
	var codec := SaveRootFixture.create_codec()
	for value: String in values:
		var root := SaveRootFixture.create_valid_root()
		root.run = null
		root.profile.next_run_serial = U64Bits.from_hex(value).value
		var encoded := codec.encode(root)
		assert_true(encoded.ok, value)
		assert_true(encoded.json_text.value.contains("\"next_run_serial\":\"%s\"" % value), value)
		var decoded := codec.decode_text(encoded.json_text.value)
		assert_true(decoded.ok, value)
		assert_eq(decoded.root.profile.next_run_serial.to_hex(), value)

func test_schema_zero_to_one_is_idempotent() -> void:
	var codec := SaveRootFixture.create_codec()
	var schema_one := codec.encode(SaveRootFixture.create_valid_root()).json_text.value
	var schema_zero := schema_one.replace("\"schema_version\":1", "\"schema_version\":0")
	schema_zero = schema_zero.replace("\"hash_version\":1,", "")
	var registry := SaveMigrationRegistry.new(codec)
	var migrated := registry.migrate(schema_zero)
	assert_true(migrated.ok)
	assert_true(migrated.source_schema is KnownSourceSchemaVersion)
	assert_eq((migrated.source_schema as KnownSourceSchemaVersion).value, 0)
	assert_eq(migrated.canonical_json_text.value, schema_one)
	var second := registry.migrate(migrated.canonical_json_text.value)
	assert_true(second.ok)
	assert_eq(second.canonical_json_text.value, migrated.canonical_json_text.value)

func test_receipt_failure_preserves_profile_and_marks_run_incompatible() -> void:
	var receipt_port := FakePinnedCatalogReceiptPort.new(SaveRootFixture.create_receipt())
	receipt_port.inject_error(PinnedCatalogReceiptError.new(
		PinnedCatalogReceiptError.PACK_MISSING, &"run.content_snapshot"
	))
	var good_codec := SaveRootFixture.create_codec()
	var text := good_codec.encode(SaveRootFixture.create_valid_root()).json_text.value
	var codec := SaveJsonCodec.new(receipt_port, FakeContentIdMigrationPort.new())
	var decoded := codec.decode_text(text)
	assert_true(decoded.ok)
	assert_null(decoded.root)
	assert_not_null(decoded.profile)
	assert_eq(decoded.run_status, LoadResult.RunStatus.INCOMPATIBLE_PRESERVED)

func test_four_resolution_shapes_round_trip_without_new_identity() -> void:
	var variants: Array[ResolutionState] = [
		IdleResolutionState.new(),
		CombatPendingResolutionState.new(_battle_setup()),
		_battle_result_resolution(),
		_reward_resolution(),
	]
	var codec := SaveRootFixture.create_codec()
	for resolution: ResolutionState in variants:
		var root := SaveRootFixture.create_valid_root()
		root.run.resolution_state = resolution
		var before := codec.encode(root)
		assert_true(before.ok, "encode resolution kind %d" % resolution.kind)
		if not before.ok:
			continue
		var decoded := codec.decode_text(before.json_text.value)
		assert_true(decoded.ok, "decode resolution kind %d" % resolution.kind)
		if not decoded.ok or decoded.root == null:
			continue
		var after := codec.encode(decoded.root)
		assert_eq(after.json_text.value, before.json_text.value)
		assert_eq(decoded.root.run.next_transaction_serial.to_hex(), root.run.next_transaction_serial.to_hex())

func _battle_setup() -> BattleSetup:
	var fixture = preload("res://tests/fixtures/canonical/battle_setup_fixture.gd")
	var inputs: BattleSetupInputs = fixture.create_inputs()
	var encoded := CanonicalBattleCodecV1.new().encode(inputs)
	var setup := BattleSetup.new()
	setup.inputs = inputs
	setup.hash_version = 1
	setup.battle_setup_hash = StringName(BattleSetupHashBuilder.sha256_hex(encoded.canonical_bytes))
	setup.rng_version = 1
	setup.combat_rng_snapshot = RngSnapshot.create(1, U64Bits.zero(), U64Bits.one(), U64Bits.zero()).snapshot
	return setup

func _battle_result_resolution() -> ResolutionState:
	var result := BattleResult.new()
	result.outcome = &"win"
	result.final_tick = 20
	result.summary_hash = &"0000000000000000000000000000000000000000000000000000000000000000"
	return BattleResultPendingResolutionState.new(String(_battle_setup().battle_setup_hash), result)

func _reward_resolution() -> ResolutionState:
	var root := SaveRootFixture.create_valid_root()
	var transaction := RuntimeKeySchemaRegistry.new().build_transaction(
		StringName(root.run.run_id), &"camp", &"reward", root.run.next_transaction_serial
	)
	var offers: Array[RewardOfferState] = []
	var reserved: Array[ReservedCopyState] = []
	var pending := PendingRewardState.new(
		"node_test", PendingRewardState.StageId.STANDARD, PendingRewardState.Phase.CHOOSING,
		offers, reserved, null, null, transaction.key_state as TransactionKeyState
	)
	return RewardPendingResolutionState.new(pending)
