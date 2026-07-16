extends RefCounted

const BattleFixture = preload("res://tests/fixtures/canonical/battle_setup_fixture.gd")

var _failures: Array[Dictionary] = []
var _assertion_count: int = 0
var _case_count: int = 0
var _current_case: String = ""

func run(case_filter: String = "") -> Dictionary:
	_failures.clear()
	_assertion_count = 0
	_case_count = 0
	var completed_scopes: Array[String] = []
	if _selected(case_filter, "U64"):
		_run_u64_and_ids()
		completed_scopes.append("U64Bits/stable-id")
	if _selected(case_filter, "RuntimeKey"):
		_run_runtime_keys()
		completed_scopes.append("RuntimeKeyCodec-v1")
	if _selected(case_filter, "RngV1"):
		_run_rng()
		completed_scopes.append("PCG32/RNG-v1")
	if _selected(case_filter, "BattleSetupV1"):
		_run_battle_codec()
		completed_scopes.append("CanonicalBattleCodec-v1")
	if _selected(case_filter, "BattleResultV1"):
		_run_battle_result()
		completed_scopes.append("BattleResult/EventCodec-v1")
	return {
		"case_count": _case_count,
		"assertion_count": _assertion_count,
		"failures": _failures.duplicate(true),
		"completed_scopes": completed_scopes,
		"deferred_scopes": [],
	}

func _selected(filter: String, name: String) -> bool:
	return filter.is_empty() or filter == name

func _begin_case(name: String) -> void:
	_current_case = name
	_case_count += 1

func _expect(condition: bool, message: String) -> void:
	_assertion_count += 1
	if not condition:
		_failures.append({"case": _current_case, "message": message})

func _run_u64_and_ids() -> void:
	_begin_case("U64")
	var boundaries: Array[String] = [
		"0000000000000000",
		"001fffffffffffff",
		"0020000000000000",
		"0020000000000001",
		"8000000000000000",
		"ffffffffffffffff",
	]
	for encoded: String in boundaries:
		var parsed := U64Bits.from_hex(encoded)
		_expect(parsed.ok and parsed.value.to_hex() == encoded, "u64 round-trip failed: %s" % encoded)
	_expect(not U64Bits.from_hex("FFFFFFFFFFFFFFFF").ok, "uppercase u64 must fail")
	_expect(not U64Bits.from_hex("0xffffffffffffffff").ok, "prefixed u64 must fail")
	_expect(not U64Bits.from_u32(-1, 0).ok, "negative high limb must fail")
	_expect(not U64Bits.from_u32(0, 4294967296).ok, "overflow low limb must fail")
	var maximum := U64Bits.max_value()
	_expect(maximum.add(U64Bits.one()).to_hex() == "0000000000000000", "u64 carry wrap failed")
	_expect(maximum.multiply(maximum).to_hex() == "0000000000000001", "16-bit limb multiply failed")
	var sample := U64Bits.from_hex("0123456789abcdef").value
	_expect(sample.shift_left(0).value.to_hex() == "0123456789abcdef", "shift-left 0 failed")
	_expect(sample.shift_left(31).value.to_hex() == "c4d5e6f780000000", "shift-left 31 failed")
	_expect(sample.shift_left(32).value.to_hex() == "89abcdef00000000", "shift-left 32 failed")
	_expect(sample.logical_shift_right(31).value.to_hex() == "0000000002468acf", "logical shift-right 31 failed")
	_expect(sample.logical_shift_right(32).value.to_hex() == "0000000001234567", "logical shift-right 32 failed")
	_expect(maximum.logical_shift_right(63).value.to_hex() == "0000000000000001", "logical shift-right 63 failed")
	_expect(not sample.shift_left(64).ok and not sample.logical_shift_right(-1).ok, "invalid shifts must fail")
	var id_validator := StableIdValidator.new()
	_expect(id_validator.is_valid(&"unit.ember_squire"), "valid stable ID rejected")
	_expect(not id_validator.is_valid(&"Unit.ember_squire"), "uppercase stable ID accepted")
	var ledger := PublishedIdLedger.new()
	_expect(ledger.add_active(&"unit.new_name").ok, "active ledger insert failed")
	_expect(ledger.add_alias(&"unit.old_name", &"unit.new_name").ok, "alias insert failed")
	_expect(ledger.resolve(&"unit.old_name").resolved_id == &"unit.new_name", "alias resolution failed")
	_expect(not ledger.add_tombstone(&"unit.old_name").ok, "published ID reuse accepted")
	var cyclic_records: Array[PublishedIdRecord] = [
		PublishedIdRecord.alias(&"unit.a", &"unit.b"),
		PublishedIdRecord.alias(&"unit.b", &"unit.a"),
	]
	_expect(not PublishedIdLedger.new().load_records(cyclic_records).ok, "alias cycle accepted")
	_expect(not InstanceIdFactory.new().create(&"u", U64Bits.max_value()).ok, "serial exhaustion wrapped")

func _run_runtime_keys() -> void:
	_begin_case("RuntimeKey")
	var schema := RuntimeKeySchemaRegistry.new()
	var serial := U64Bits.from_hex("000000000000002a").value
	var run_key := schema.build_run("00112233445566778899aabbccddeeff", serial)
	var expected_run_bytes := "000000056b3a72756e00000022683a303031313232333334343535363637373838393961616262636364646565666600000012753a30303030303030303030303030303261"
	var expected_run_id := &"run_ec13b8c584b94fc6d1fb15852ee35573bc8e02739b120f218ce91c361e947cbb"
	_expect(run_key.ok and run_key.canonical_bytes.hex_encode() == expected_run_bytes, "run golden bytes mismatch")
	_expect(run_key.ok and run_key.key_state.digest == expected_run_id, "run golden digest mismatch")
	var node_key := schema.build_node(expected_run_id, 2, &"boss", 5, 0)
	var expected_node_bytes := "000000066b3a6e6f646500000046733a72756e5f6563313362386335383462393466633664316662313538353265653335353733626338653032373339623132306632313863653931633336316539343763626200000003693a3200000006653a626f737300000003693a3500000003693a30"
	var expected_node_id := &"node_d94992320541276dfd384a614e280c0e1e0f804931a3ba6ec8e59fd467a033bc"
	_expect(node_key.ok and node_key.canonical_bytes.hex_encode() == expected_node_bytes, "node golden bytes mismatch")
	_expect(node_key.ok and node_key.key_state.digest == expected_node_id, "node golden digest mismatch")
	var reservation := schema.build_reservation_owner(expected_run_id, expected_node_id, &"shop", &"refresh0", 1)
	var transaction := schema.build_transaction(expected_run_id, expected_node_id, &"buy", U64Bits.zero())
	var claim := schema.build_effect_claim(expected_run_id, expected_node_id, &"once", &"u_0000000000000001", &"effect.test", 0)
	var settlement := schema.build_settlement_receipt(expected_run_id)
	_expect(reservation.ok and transaction.ok and claim.ok and settlement.ok, "one or more typed key builders failed")
	for result: RuntimeKeyEncodeResult in [run_key, node_key, reservation, transaction, claim, settlement]:
		var decoded := RuntimeKeyCodecV1.new().decode(result.canonical_bytes)
		_expect(decoded.ok, "runtime key decode failed for %s" % result.key_state.kind)
		_expect(schema.reencode_state(result.key_state).ok, "runtime key state re-encode failed for %s" % result.key_state.kind)
		if decoded.ok:
			var count_tokens := decoded.tuple.tokens_copy()
			count_tokens.remove_at(count_tokens.size() - 1)
			var count_result := RuntimeKeyCodecV1.new().encode(RuntimeKeyTuple._create(decoded.tuple.kind(), count_tokens))
			_expect(not count_result.ok and count_result.error.code == &"KEY_FIELD_COUNT", "%s wrong-count fixture mismatch" % result.key_state.kind)
			var tag_tokens := decoded.tuple.tokens_copy()
			var invalid_token := RuntimeKeyToken.new()
			invalid_token.tag = &"x"
			invalid_token.value = "invalid"
			tag_tokens[1] = invalid_token
			var tag_result := RuntimeKeyCodecV1.new().encode(RuntimeKeyTuple._create(decoded.tuple.kind(), tag_tokens))
			_expect(not tag_result.ok and tag_result.error.code == &"KEY_FIELD_TAG", "%s wrong-tag fixture mismatch" % result.key_state.kind)
			var order_tokens := decoded.tuple.tokens_copy()
			var first_token := order_tokens[0]
			order_tokens[0] = order_tokens[1]
			order_tokens[1] = first_token
			var order_result := RuntimeKeyCodecV1.new().encode(RuntimeKeyTuple._create(decoded.tuple.kind(), order_tokens))
			_expect(not order_result.ok and order_result.error.code == &"KEY_FIELD_ORDER", "%s wrong-order fixture mismatch" % result.key_state.kind)
	var wrong_count_tokens: Array[RuntimeKeyToken] = [KeyKindToken._from_value("run")]
	var wrong_count := RuntimeKeyCodecV1.new().encode(RuntimeKeyTuple._create(&"run", wrong_count_tokens))
	_expect(not wrong_count.ok and wrong_count.error.code == &"KEY_FIELD_COUNT", "wrong field count error mismatch")
	var wrong_tag_tokens: Array[RuntimeKeyToken] = [KeyKindToken._from_value("run"), StableAsciiToken._from_value("00112233445566778899aabbccddeeff"), U64Token._from_value(serial)]
	var wrong_tag := RuntimeKeyCodecV1.new().encode(RuntimeKeyTuple._create(&"run", wrong_tag_tokens))
	_expect(not wrong_tag.ok and wrong_tag.error.code == &"KEY_FIELD_TAG", "wrong tag error mismatch")
	var wrong_order_tokens: Array[RuntimeKeyToken] = [KeyKindToken._from_value("run"), U64Token._from_value(serial), FixedHexToken._from_value("00112233445566778899aabbccddeeff")]
	var wrong_order := RuntimeKeyCodecV1.new().encode(RuntimeKeyTuple._create(&"run", wrong_order_tokens))
	_expect(not wrong_order.ok and wrong_order.error.code == &"KEY_FIELD_ORDER", "wrong order error mismatch")
	var payload := &"0000000000000000000000000000000000000000000000000000000000000000"
	var ledger_entries: Array[RuntimeKeyLedgerEntry] = [RuntimeKeyLedgerEntry.create(run_key.key_state, payload)]
	_expect(RuntimeKeyLedgerValidator.new().validate(ledger_entries).ok, "valid key ledger rejected")
	ledger_entries.append(RuntimeKeyLedgerEntry.create(run_key.key_state, payload))
	_expect(not RuntimeKeyLedgerValidator.new().validate(ledger_entries).ok, "duplicate key tuple accepted")
	var tampered := run_key.key_state.deep_clone() as RunKeyState
	tampered.next_run_serial = U64Bits.one()
	_expect(not schema.reencode_state(tampered).ok, "tampered typed tuple digest accepted")
	_expect(RuntimeKeyLedgerValidator.new().validate_serial_transition(U64Bits.zero(), U64Bits.one(), 1, false).ok, "serial advance rejected")
	_expect(not RuntimeKeyLedgerValidator.new().validate_serial_transition(U64Bits.one(), U64Bits.zero(), 0, false).ok, "serial rollback accepted")
	_expect(RuntimeKeyLedgerValidator.new().validate_serial_transition(U64Bits.one(), U64Bits.one(), 0, true).ok, "retry did not preserve serial identity")
	_expect(not RuntimeKeyLedgerValidator.new().validate_serial_transition(U64Bits.one(), U64Bits.from_hex("0000000000000002").value, 0, true).ok, "retry advanced serial")
	_expect(not RuntimeKeyLedgerValidator.new().validate_serial_transition(U64Bits.max_value(), U64Bits.max_value(), 1, false).ok, "serial exhaustion wrapped")

func _run_rng() -> void:
	_begin_case("RngV1")
	var init_state := U64Bits.from_hex("000000000000002a").value
	var init_seq := U64Bits.from_hex("0000000000000036").value
	var seeded := Pcg32Stream.seed(init_state, init_seq)
	_expect(seeded.ok and seeded.stream.snapshot().inc.to_hex() == "000000000000006d", "PCG reference seed/inc mismatch")
	var expected: Array[String] = ["a15c02b7", "7b47f409", "ba1d3330", "83d2f293", "bfa4784b", "cbed606e"]
	for expected_hex: String in expected:
		var draw := seeded.stream.next_u32()
		_expect(draw.ok and "%08x" % draw.value_u32.low_u32() == expected_hex, "PCG reference output mismatch: %s" % expected_hex)
	_expect(seeded.stream.snapshot().counter.to_hex() == "0000000000000006", "PCG raw counter mismatch")
	var bounded_stream := Pcg32Stream.seed(init_state, init_seq).stream
	var bounds: Array[int] = [10, 100, 10000, 7, 4294967296]
	var bounded_expected: Array[int] = [3, 97, 5824, 0, 3215226955]
	for index: int in range(bounds.size()):
		var draw := bounded_stream.next_bounded(bounds[index])
		_expect(draw.ok and draw.value_u32.low_u32() == bounded_expected[index], "bounded vector mismatch at %d" % index)
	_expect(bounded_stream.snapshot().counter.to_hex() == "0000000000000005", "bounded raw counter mismatch")
	var before_invalid := bounded_stream.snapshot()
	var invalid := bounded_stream.next_bounded(0)
	_expect(not invalid.ok and before_invalid.equals(bounded_stream.snapshot()), "invalid bound consumed RNG state")
	var tuple_bytes := RngAlgorithms.encode_named_tuple(&"shop", &"act1.node3.refresh0")
	_expect(tuple_bytes.hex_encode() == "0000000473686f7000000013616374312e6e6f6465332e7265667265736830", "named tuple bytes mismatch")
	var name_hash := RngAlgorithms.fnv1a64(tuple_bytes)
	_expect(name_hash.to_hex() == "83fb29e4f4dc9cff", "FNV-1a vector mismatch")
	var derived_init_state := RngAlgorithms.splitmix64(init_state.bit_xor(name_hash))
	_expect(derived_init_state.to_hex() == "00d680f2ffcc2419", "derived init_state mismatch")
	var derive_xor := U64Bits.from_hex("da3e39cb94b95bdb").value
	var derived_init_seq := RngAlgorithms.splitmix64(derived_init_state.bit_xor(derive_xor))
	_expect(derived_init_seq.to_hex() == "0a2c20ee2cf89fc5", "derived init_seq mismatch")
	var derived := RngService.new().derive_stream(init_state, &"shop", &"act1.node3.refresh0")
	_expect(derived.ok and derived.snapshot.inc.to_hex() == "145841dc59f13f8b", "derived shop inc mismatch")
	var derived_expected: Array[String] = ["535f5c38", "2cb08b6d", "0319e6b0", "845361ca", "a6219ffd", "ada38359"]
	for expected_hex: String in derived_expected:
		_expect("%08x" % derived.stream.next_u32().value_u32.low_u32() == expected_hex, "derived shop output mismatch: %s" % expected_hex)
	var isolated_a := RngService.new().derive_stream(init_state, &"shop", &"same.context").stream
	var isolated_b := RngService.new().derive_stream(init_state, &"shop", &"same.context").stream
	var map_stream := RngService.new().derive_stream(init_state, &"map", &"act1").stream
	for _draw_index: int in range(20):
		map_stream.next_u32()
	_expect(isolated_a.next_u32().value_u32.equals(isolated_b.next_u32().value_u32), "map draws changed shop stream")
	var named_first_draws: Array[String] = []
	for stream_name: StringName in [&"map", &"shop", &"reward", &"combat"]:
		var named := RngService.new().derive_stream(init_state, stream_name, &"shared.context")
		_expect(named.ok, "named stream rejected: %s" % stream_name)
		if named.ok:
			named_first_draws.append(named.stream.next_u32().value_u32.to_hex())
	_expect(named_first_draws.size() == 4 and named_first_draws.duplicate().size() == 4, "named stream derivation incomplete")
	for left_index: int in range(named_first_draws.size()):
		for right_index: int in range(left_index + 1, named_first_draws.size()):
			_expect(named_first_draws[left_index] != named_first_draws[right_index], "named streams collided in fixture")
	_expect(not RngService.new().derive_stream(init_state, &"unknown", &"x").ok, "unknown stream accepted")
	_expect(not RngService.new().derive_stream(init_state, &"shop", &"").ok, "empty context accepted")
	var invalid_snapshot := RngSnapshot.create(1, U64Bits.zero(), U64Bits.zero(), U64Bits.zero())
	_expect(not invalid_snapshot.ok, "even PCG increment accepted")
	var restored := Pcg32Stream.from_snapshot(derived.stream.snapshot())
	_expect(restored.ok and restored.stream.snapshot().equals(derived.stream.snapshot()), "RNG snapshot restore changed state")

func _run_battle_codec() -> void:
	_begin_case("BattleSetupV1")
	var inputs: BattleSetupInputs = BattleFixture.create_inputs()
	var codec := CanonicalBattleCodecV1.new()
	var encoded := codec.encode(inputs)
	_expect(encoded.ok, "valid battle setup failed to encode")
	if not encoded.ok:
		return
	var digest := BattleSetupHashBuilder.sha256_hex(encoded.canonical_bytes)
	_expect(encoded.canonical_bytes.size() == BattleFixture.GOLDEN_SIZE, "battle golden byte count mismatch: %d" % encoded.canonical_bytes.size())
	_expect(digest == BattleFixture.GOLDEN_SHA256, "battle golden SHA-256 mismatch: %s" % digest)
	var decoded := codec.decode(encoded.canonical_bytes)
	_expect(decoded.ok, "canonical battle decode failed")
	if decoded.ok:
		var reencoded := codec.encode(decoded.inputs)
		_expect(reencoded.ok and reencoded.canonical_bytes == encoded.canonical_bytes, "battle decode/encode is not byte-identical")
	var validator := BattleSetupInputsValidator.new()
	var structural_validation := validator.validate(inputs)
	_expect(
		structural_validation.ok and structural_validation.receipt == null,
		"structural validation unexpectedly issued a build receipt"
	)
	var build_validation := validator.validate_for_build(inputs)
	_expect(
		build_validation.ok and build_validation.receipt != null,
		"trusted validator did not issue a build receipt"
	)
	var receipt: BattleSetupValidationReceipt = build_validation.receipt
	var seed := U64Bits.from_hex("000000000000002a").value
	var built := BattleSetupHashBuilder.new(seed).build_from_validated(inputs, receipt)
	_expect(built.ok and built.battle_setup.battle_setup_hash == StringName(digest), "battle setup builder/hash failed")
	var other_seed := U64Bits.from_hex("000000000000002b").value
	var other_seed_build := BattleSetupHashBuilder.new(other_seed).build_from_validated(inputs, receipt)
	_expect(other_seed_build.ok and other_seed_build.battle_setup.battle_setup_hash == StringName(digest), "run seed leaked into setup hash")
	_expect(other_seed_build.ok and not other_seed_build.battle_setup.combat_rng_snapshot.equals(built.battle_setup.combat_rng_snapshot), "combat seed did not derive after setup hash")
	var moved := inputs.deep_clone()
	moved.player_units[0].logical_x = 5
	var moved_encoded := codec.encode(moved)
	_expect(moved_encoded.ok and BattleSetupHashBuilder.sha256_hex(moved_encoded.canonical_bytes) != digest, "player position did not change setup hash")
	var faster := inputs.deep_clone()
	faster.player_units[0].move_speed_milli = 1001
	var faster_encoded := codec.encode(faster)
	_expect(faster_encoded.ok and BattleSetupHashBuilder.sha256_hex(faster_encoded.canonical_bytes) != digest, "effective move speed did not change setup hash")
	var identical := inputs.deep_clone()
	_expect(BattleSetupHashBuilder.sha256_hex(codec.encode(identical).canonical_bytes) == digest, "non-input state would change setup hash")
	var bad_preview := inputs.deep_clone()
	bad_preview.encounter_snapshot.manifest_digest = &"1111111111111111111111111111111111111111111111111111111111111111"
	var preview_result := codec.encode(bad_preview)
	_expect(not preview_result.ok and preview_result.error.code == &"BATTLE_PREVIEW_MISMATCH", "preview mismatch error not enforced")
	var tampered_rejected := BattleSetupHashBuilder.new(seed).build_from_validated(
		moved,
		receipt
	)
	_expect(
		not tampered_rejected.ok \
			and tampered_rejected.error.code == &"BATTLE_VALIDATION_RECEIPT_INVALID",
		"receipt was accepted after canonical inputs changed"
	)
	var foreign_authority := BattleSetupValidationAuthority.new()
	var foreign_receipt := foreign_authority._issue_validated(StringName(digest))
	var foreign_rejected := BattleSetupHashBuilder.new(seed).build_from_validated(
		inputs,
		foreign_receipt
	)
	_expect(not foreign_rejected.ok and foreign_rejected.error.code == &"BATTLE_VALIDATION_RECEIPT_INVALID", "foreign validation authority accepted")
	var forged_receipt := BattleSetupValidationReceipt.new(
		StringName(digest),
		RefCounted.new()
	)
	var forged_rejected := BattleSetupHashBuilder.new(seed).build_from_validated(
		inputs,
		forged_receipt
	)
	_expect(
		not forged_rejected.ok \
			and forged_rejected.error.code == &"BATTLE_VALIDATION_RECEIPT_INVALID",
		"directly forged validation receipt accepted"
	)
	var tampered_text := encoded.canonical_bytes.get_string_from_utf8().replace("\"setup_schema_version\":1", "\"unknown\":1,\"setup_schema_version\":1")
	_expect(not codec.decode(tampered_text.to_utf8_buffer()).ok, "unknown canonical field accepted")
	var float_text := encoded.canonical_bytes.get_string_from_utf8().replace("\"health\":120", "\"health\":120.0")
	_expect(not codec.decode(float_text.to_utf8_buffer()).ok, "float canonical integer accepted")
	var missing_text := encoded.canonical_bytes.get_string_from_utf8().replace("\"content_version\":\"fixture.1\",", "")
	_expect(not codec.decode(missing_text.to_utf8_buffer()).ok, "missing canonical field accepted")
	var duplicate_ids := inputs.deep_clone()
	duplicate_ids.player_units[0].effect_ids = [&"effect.test", &"effect.test"]
	_expect(not codec.encode(duplicate_ids).ok, "duplicate/sorted ID invariant not enforced")
	var invalid_speed := inputs.deep_clone()
	invalid_speed.player_units[0].move_speed_milli = 0
	_expect(not codec.encode(invalid_speed).ok, "zero move speed accepted")
	var extended := inputs.deep_clone()
	extended.content_version = "fixture.1\\\"quoted"
	var phase := BossPhaseSnapshot.new()
	phase.phase_index = 0
	phase.hp_threshold_bps = 5000
	phase.effect_ids = [&"effect.phase"]
	extended.encounter_snapshot.boss_phases.append(phase)
	var id_parameter := BattleIdParam.new()
	id_parameter.key = &"unit_id"
	id_parameter.value = &"unit.hero"
	var affix := BattleEffectSnapshot.new()
	affix.priority = 1
	affix.source_stable_id = &"affix.test"
	affix.effect_index = 0
	affix.effect_id = &"effect.affix"
	affix.target_ids = [&"e_0000000000000001"]
	affix.id_params.append(id_parameter)
	extended.encounter_snapshot.affix_effects.append(affix)
	var extended_encoded := codec.encode(extended)
	_expect(extended_encoded.ok, "non-empty boss phase/id-param fixture failed")
	if extended_encoded.ok:
		var extended_decoded := codec.decode(extended_encoded.canonical_bytes)
		_expect(extended_decoded.ok, "non-empty nested battle DTO decode failed")
		if extended_decoded.ok:
			_expect(extended_decoded.inputs.content_version == extended.content_version, "canonical JSON string escaping changed value")
			_expect(codec.encode(extended_decoded.inputs).canonical_bytes == extended_encoded.canonical_bytes, "non-empty nested DTO round-trip changed bytes")

func _run_battle_result() -> void:
	_begin_case("BattleResultV1")
	var inputs := BattleSimulationFixture.create_inputs()
	var player := inputs.player_units[0]
	var enemy := inputs.encounter_snapshot.enemy_units[0]
	player.logical_y = 3
	player.logical_x = 3
	enemy.logical_y = 4
	enemy.logical_x = 3
	player.health = 10
	enemy.health = 10
	player.attack = 20
	enemy.attack = 20
	player.max_mana = 0
	enemy.max_mana = 0
	var setup := BattleSimulationFixture.build_setup(inputs)
	_expect(setup != null, "simultaneous-death setup build failed")
	if setup == null:
		return
	var simulation := BattleSimulation.new()
	var initialized := simulation.initialize(setup)
	_expect(initialized.ok, "simultaneous-death initialize failed")
	if not initialized.ok:
		return
	var events: Array[BattleEvent] = []
	var stepped := simulation.step()
	_expect(stepped.ok and stepped.finished, "simultaneous-death tick did not finish")
	if not stepped.ok:
		return
	for event: BattleEvent in stepped.events:
		events.append(event.deep_clone())
	var queried := simulation.result()
	_expect(queried.ok, "simultaneous-death result unavailable")
	if not queried.ok:
		return
	var result := queried.result
	_expect(result.outcome == &"player_loss", "double death was not player loss")
	_expect(result.final_tick == 1, "simultaneous-death final tick drifted")
	_expect(
		String(result.summary_hash) == "6248075fcbe65a43cda15b2cd4efe0ee241a89f50c830d337d9871c8adc9bb6e",
		"summary golden mismatch: %s" % String(result.summary_hash)
	)
	_expect(
		String(result.result_hash) == "03d9decb4aa4e26f66fd6f92a1c4464c00e82bc621082c4176ed0f4c64838788",
		"result golden mismatch: %s" % String(result.result_hash)
	)
	var framed := BattleEventStreamHasher.new().framed_bytes(events)
	_expect(framed.ok, "event stream framing failed")
	if framed.ok:
		_expect(
			BattleSetupHashBuilder.sha256_hex(framed.canonical_bytes) == "3c0c01b94ca8c727763cd117402a610c82dcb39b402747b99ad346003e749617",
			"event stream golden mismatch: %s" % BattleSetupHashBuilder.sha256_hex(
				framed.canonical_bytes
			)
		)
