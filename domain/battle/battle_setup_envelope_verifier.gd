class_name BattleSetupEnvelopeVerifier
extends RefCounted

var _rng_service := RngService.new()

func verify(setup: BattleSetup, run_seed: U64Bits) -> BattleSetupEnvelopeResult:
	if setup == null or setup.inputs == null or setup.inputs.setup_schema_version != 2 \
		or setup.hash_version != 1 or setup.rng_version != 1 or run_seed == null \
		or setup.combat_rng_snapshot == null:
		return BattleSetupEnvelopeResult.failure(
			BattleSetupEnvelopeError.INPUT_INVALID,
			&"battle_setup"
		)
	var encoded := CanonicalBattleCodecV2.new().encode(setup.inputs)
	if not encoded.ok:
		return BattleSetupEnvelopeResult.failure(
			BattleSetupEnvelopeError.INPUT_INVALID,
			encoded.error.field_path
		)
	var recomputed_hash := BattleSetupHashBuilder.sha256_hex(encoded.canonical_bytes)
	if recomputed_hash != String(setup.battle_setup_hash):
		return BattleSetupEnvelopeResult.failure(
			BattleSetupEnvelopeError.HASH_MISMATCH,
			&"battle_setup_hash"
		)
	var context := StringName("%s:%s" % [
		String(setup.inputs.encounter_snapshot.encounter_id),
		recomputed_hash,
	])
	var derived := _rng_service.derive_stream(run_seed, &"combat", context)
	if not derived.ok or not derived.snapshot.equals(setup.combat_rng_snapshot):
		return BattleSetupEnvelopeResult.failure(
			BattleSetupEnvelopeError.RNG_MISMATCH,
			&"combat_rng_snapshot"
		)
	var digest := BattleSetupHashBuilder.envelope_digest(
		setup.hash_version,
		recomputed_hash,
		setup.rng_version,
		derived.snapshot
	)
	if digest != String(setup.battle_setup_envelope_digest):
		return BattleSetupEnvelopeResult.failure(
			BattleSetupEnvelopeError.DIGEST_MISMATCH,
			&"battle_setup_envelope_digest"
		)
	return BattleSetupEnvelopeResult.success(derived.snapshot)
