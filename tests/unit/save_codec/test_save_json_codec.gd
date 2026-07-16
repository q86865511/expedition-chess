extends GutTest

func test_schema_two_round_trip_is_byte_identical() -> void:
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
		"{\"schema_version\":2,",
		"{\"schema_version\":2,\"unknown\":0,"
	)
	assert_false(codec.decode_text(unknown).ok)
	var duplicate := encoded.json_text.value.replace(
		"{\"schema_version\":2,",
		"{\"schema_version\":2,\"schema_version\":2,"
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
	var profile_only := SaveRootFixture.create_valid_root()
	profile_only.run = null
	var schema_two := codec.encode(profile_only).json_text.value
	var schema_zero := schema_two.replace("\"schema_version\":2", "\"schema_version\":0")
	schema_zero = schema_zero.replace("\"hash_version\":1,", "")
	var registry := SaveMigrationRegistry.new(codec)
	var migrated := registry.migrate(schema_zero)
	assert_true(migrated.ok)
	assert_true(migrated.source_schema is KnownSourceSchemaVersion)
	assert_eq((migrated.source_schema as KnownSourceSchemaVersion).value, 0)
	assert_eq(migrated.target_schema_version, 2)
	assert_eq(migrated.canonical_json_text.value, schema_two)
	var second := registry.migrate(migrated.canonical_json_text.value)
	assert_true(second.ok)
	assert_eq(second.canonical_json_text.value, migrated.canonical_json_text.value)


func test_schema_one_prepare_and_pending_runs_preserve_profile_and_original_bytes() -> void:
	var codec := SaveRootFixture.create_codec()
	var prepare := SaveRootFixture.create_valid_root()
	prepare.run.run_phase = RunState.RunPhase.PREPARE
	_assert_schema_one_incompatible(codec, prepare, MigrationError.RUN_INCOMPATIBLE_PRESERVED)

	var pending := SaveRootFixture.create_valid_root()
	pending.run.run_phase = RunState.RunPhase.COMBAT
	pending.run.resolution_state = CombatPendingResolutionState.new(_battle_setup())
	_assert_schema_one_incompatible(codec, pending, MigrationError.RUN_INCOMPATIBLE_PRESERVED)


func test_schema_one_idle_map_requires_explicit_generation_migration_pack() -> void:
	var codec := SaveRootFixture.create_codec()
	var idle := SaveRootFixture.create_valid_root()
	_assert_schema_one_incompatible(
		codec,
		idle,
		ContentGenerationMigrationError.PORT_UNCONFIGURED
	)


func test_schema_one_idle_map_migrates_generation_atomically_and_is_idempotent() -> void:
	var target_receipt := _target_receipt()
	var codec := SaveJsonCodec.new(
		FakePinnedCatalogReceiptPort.new(target_receipt),
		FakeContentIdMigrationPort.new()
	)
	var generation_port := FakeContentGenerationMigrationPort.new(
		ContentGenerationMigrationResult.success(
			target_receipt,
			_generation_receipt(target_receipt.manifest_digest)
		)
	)
	var registry := SaveMigrationRegistry.new(codec, generation_port)
	var schema_one := _legacy_idle_text(1)
	var migrated := registry.migrate(schema_one)
	assert_true(migrated.ok)
	assert_not_null(migrated.root)
	assert_not_null(migrated.migration_receipt)
	assert_eq(migrated.root.schema_version, 2)
	assert_eq(migrated.root.content_version, "fixture.2")
	assert_eq(
		migrated.root.run.content_snapshot.combat_config_id_value(),
		&"config.combat_default"
	)
	assert_eq(migrated.root.run.content_snapshot.manifest_digest_value(), target_receipt.manifest_digest)
	assert_eq(generation_port.requests.size(), 1)
	assert_false(generation_port.requests[0].enabled_content_ids.has(&"config.combat_default"))
	assert_eq(migrated.diagnostics[0].code, SaveMigrationRegistry.MIGRATION_RECEIPT_DIAGNOSTIC)

	var second := registry.migrate(migrated.canonical_json_text.value)
	assert_true(second.ok)
	assert_eq(second.canonical_json_text.value, migrated.canonical_json_text.value)
	assert_eq(generation_port.requests.size(), 1)


func test_schema_zero_active_run_uses_ordered_zero_to_one_to_two_steps() -> void:
	var target_receipt := _target_receipt()
	var codec := SaveJsonCodec.new(
		FakePinnedCatalogReceiptPort.new(target_receipt),
		FakeContentIdMigrationPort.new()
	)
	var generation_port := FakeContentGenerationMigrationPort.new(
		ContentGenerationMigrationResult.success(
			target_receipt,
			_generation_receipt(target_receipt.manifest_digest)
		)
	)
	var migrated := SaveMigrationRegistry.new(codec, generation_port).migrate(_legacy_idle_text(0))
	assert_true(migrated.ok)
	assert_not_null(migrated.root)
	assert_eq((migrated.source_schema as KnownSourceSchemaVersion).value, 0)
	assert_eq(migrated.target_schema_version, 2)
	assert_eq(generation_port.requests.size(), 1)

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
		assert_true(
			decoded.ok,
			"decode resolution kind %d: %s" % [
				resolution.kind,
				String(decoded.error.field_path) if decoded.error != null else "unknown",
			]
		)
		if not decoded.ok or decoded.root == null:
			continue
		var after := codec.encode(decoded.root)
		assert_eq(after.json_text.value, before.json_text.value)
		assert_eq(decoded.root.run.next_transaction_serial.to_hex(), root.run.next_transaction_serial.to_hex())


func test_schema_two_combat_pending_round_trips_full_v2_setup_envelope() -> void:
	var root := SaveRootFixture.create_valid_root()
	var inputs := _battle_inputs_v2_for_save()
	var validation := BattleSetupInputsValidator.new().validate_for_build(inputs)
	assert_true(validation.ok)
	if not validation.ok:
		return
	var built := BattleSetupHashBuilder.new(root.run.run_seed).build_from_validated(
		inputs, validation.receipt
	)
	assert_true(built.ok)
	if not built.ok:
		return
	root.run.resolution_state = CombatPendingResolutionState.new(built.battle_setup)
	var codec := SaveRootFixture.create_codec()
	var encoded := codec.encode(root)
	assert_true(encoded.ok)
	if not encoded.ok:
		return
	assert_true(encoded.json_text.value.contains("\"battle_setup_envelope_digest\""))
	assert_true(encoded.json_text.value.contains("\"effect_assignments\""))
	var decoded := codec.decode_text(encoded.json_text.value)
	assert_true(
		decoded.ok,
		String(decoded.error.field_path) if decoded.error != null else "unknown"
	)
	assert_not_null(decoded.root)
	if not decoded.ok or decoded.root == null:
		return
	var pending := decoded.root.run.resolution_state as CombatPendingResolutionState
	assert_not_null(pending)
	assert_eq(pending.battle_setup.inputs.setup_schema_version, 2)
	assert_eq(
		pending.battle_setup.inputs.player_equipment_effects[0].source_category,
		&"equipment"
	)
	assert_eq(
		pending.battle_setup.battle_setup_envelope_digest,
		built.battle_setup.battle_setup_envelope_digest
	)
	assert_eq(codec.encode(decoded.root).json_text.value, encoded.json_text.value)


func test_schema_two_map_preview_round_trips_v2_source_fields() -> void:
	var root := SaveRootFixture.create_valid_root()
	var key_result := RuntimeKeySchemaRegistry.new().build_node(
		StringName(root.run.run_id), 0, &"normal", 0, 0
	)
	assert_true(key_result.ok)
	if not key_result.ok:
		return
	var node_key := key_result.key_state as NodeKeyState
	var inputs := _battle_inputs_v2_for_save()
	var nodes: Array[MapNodeState] = [MapNodeState.new(
		String(node_key.digest),
		node_key,
		&"mapnode.fixture",
		0,
		0,
		0,
		MapNodeState.NodeKind.NORMAL,
		"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
		inputs.encounter_snapshot,
		false
	)]
	var edges: Array[MapEdgeState] = []
	var completed: Array[String] = []
	root.run.map_state = MapState.new(nodes, edges, null, completed)
	var codec := SaveRootFixture.create_codec()
	var encoded := codec.encode(root)
	assert_true(encoded.ok)
	if not encoded.ok:
		return
	assert_true(encoded.json_text.value.contains("\"source_instance_id\""))
	assert_true(encoded.json_text.value.contains("\"effect_assignments\""))
	var decoded := codec.decode_text(encoded.json_text.value)
	assert_true(
		decoded.ok,
		String(decoded.error.field_path) if decoded.error != null else "unknown"
	)
	assert_not_null(decoded.root)
	if not decoded.ok or decoded.root == null:
		return
	var preview := decoded.root.run.map_state.nodes[0].encounter_preview
	assert_not_null(preview)
	assert_eq(preview.manifest_digest, StringName(SaveRootFixture.MANIFEST_DIGEST))
	assert_eq(preview.enemy_units[0].instance_id, &"e_0000000000000001")
	assert_eq(codec.encode(decoded.root).json_text.value, encoded.json_text.value)

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


func _battle_inputs_v2_for_save() -> BattleSetupInputs:
	var fixture = preload("res://tests/fixtures/canonical/battle_setup_fixture.gd")
	var inputs: BattleSetupInputs = fixture.create_inputs()
	inputs.setup_schema_version = 2
	inputs.content_version = SaveRootFixture.CONTENT_VERSION
	inputs.manifest_digest = StringName(SaveRootFixture.MANIFEST_DIGEST)
	inputs.encounter_snapshot.manifest_digest = StringName(SaveRootFixture.MANIFEST_DIGEST)
	var equipment := inputs.player_equipment_effects[0]
	equipment.source_category = &"equipment"
	equipment.source_side = &"player"
	equipment.source_instance_id = OptionalStringNameValue.of(&"u_0000000000000001")
	equipment.source_slot = 0
	var ability := BattleAbilityRuleSnapshot.new()
	ability.ability_id = &"ability.test"
	ability.target_rule = &"self"
	ability.cast_ticks = 1
	ability.effect_ids = [&"effect.test"]
	inputs.battle_rules.ability_rules.append(ability)
	var effect := BattleEffectRuleSnapshot.new()
	effect.effect_id = &"effect.test"
	effect.trigger = &"battle_start"
	effect.stacking = &"replace"
	effect.max_stacks = 1
	effect.duration_ticks = 1
	inputs.battle_rules.effect_rules.append(effect)
	var enemy := inputs.encounter_snapshot.enemy_units[0]
	enemy.effect_ids.append(&"effect.test")
	var enemy_assignment := BattleEffectSnapshot.new()
	enemy_assignment.source_category = &"unit"
	enemy_assignment.source_side = &"enemy"
	enemy_assignment.source_stable_id = enemy.unit_id
	enemy_assignment.source_instance_id = OptionalStringNameValue.of(enemy.instance_id)
	enemy_assignment.effect_id = &"effect.test"
	enemy.effect_assignments.append(enemy_assignment)
	return inputs

func _battle_result_resolution() -> ResolutionState:
	var setup := _battle_setup_v2_for_save()
	var result := BattleResult.new()
	result.battle_setup_hash = setup.battle_setup_hash
	result.outcome = &"player_win"
	result.final_tick = 20
	result.summary_hash = &"0000000000000000000000000000000000000000000000000000000000000000"
	var sealed := BattleResultCodecV1.new().seal(result.to_record())
	assert_true(sealed.ok)
	return BattleResultPendingResolutionState.new(
		String(setup.battle_setup_hash),
		BattleResult.from_record(sealed.record)
	)


func _battle_setup_v2_for_save() -> BattleSetup:
	var inputs := _battle_inputs_v2_for_save()
	var validation := BattleSetupInputsValidator.new().validate_for_build(inputs)
	assert_true(validation.ok)
	var built := BattleSetupHashBuilder.new(U64Bits.zero()).build_from_validated(
		inputs, validation.receipt
	)
	assert_true(built.ok)
	return built.battle_setup

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


func _assert_schema_one_incompatible(
	codec: SaveJsonCodec,
	root: SaveRoot,
	expected_diagnostic: StringName
) -> void:
	var encoded := codec.encode(root)
	assert_true(encoded.ok)
	if not encoded.ok:
		return
	var schema_one := encoded.json_text.value.replace(
		"\"schema_version\":2",
		"\"schema_version\":1"
	)
	schema_one = schema_one.replace(
		",\"combat_config_id\":\"config.combat_default\"",
		""
	)
	var migrated := SaveMigrationRegistry.new(codec).migrate(schema_one)
	assert_true(migrated.ok)
	assert_null(migrated.root)
	assert_not_null(migrated.profile)
	assert_eq(migrated.run_status, LoadResult.RunStatus.INCOMPATIBLE_PRESERVED)
	assert_eq(migrated.canonical_json_text.value, schema_one)
	assert_eq(migrated.diagnostics.size(), 1)
	if migrated.diagnostics.size() == 1:
		assert_eq(migrated.diagnostics[0].code, expected_diagnostic)


func _legacy_idle_text(schema: int) -> String:
	var encoded := SaveRootFixture.create_codec().encode(SaveRootFixture.create_valid_root())
	assert_true(encoded.ok)
	var text := encoded.json_text.value.replace(
		"\"schema_version\":2",
		"\"schema_version\":%d" % schema
	)
	text = text.replace(",\"combat_config_id\":\"config.combat_default\"", "")
	text = text.replace("\"config.combat_default\",", "")
	if schema == 0:
		text = text.replace("\"hash_version\":1,", "")
	return text


func _target_receipt() -> PinnedCatalogBuildReceipt:
	var source := SaveRootFixture.create_receipt()
	return PinnedCatalogBuildReceipt.new(
		1,
		2,
		"fixture.2",
		"4444444444444444444444444444444444444444444444444444444444444444",
		source.active_entry_ids,
		source.economy_config_id,
		&"config.combat_default",
		source.reward_table_ids,
		source.map_node_def_ids,
		source.challenge_unlock_def_ids,
		source.meta_reward_table_id,
		"3333333333333333333333333333333333333333333333333333333333333333"
	)


func _generation_receipt(target_manifest_digest: String) -> ContentGenerationMigrationReceipt:
	return ContentGenerationMigrationReceipt.new(
		SaveRootFixture.MANIFEST_DIGEST,
		target_manifest_digest,
		"463ac1f542a942fb1dc8c3dea7f7647295e4635f9b02c57be7c3ea0a15bcaaa6",
		"2f7b38387cf9a69a2f9fa03f20b690f0098f5411097a4f96aa259db21076d2b9",
		"20d34a4e5b489b1bad34f7d86005d757442f4922ef73b8369a703aedc1920b15",
		1,
		2,
		"7c2ef65221a2ad4a84b923786500b2a974e560b6068e5a83393e783ae1524f65"
	)
