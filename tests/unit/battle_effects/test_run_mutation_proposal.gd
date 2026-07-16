extends GutTest

const RMP2_GOLDEN: String = "2070ff6f9833c0f122710ad42493a30a43d0b304a3b5de3be69739b4398ba9f9"


func test_proposal_source_codec_builds_every_canonical_source_shape() -> void:
	var codec := ProposalSourceCodecV1.new()
	assert_eq(codec.player_unit("u_0000000000000001").token.value, "u/u_0000000000000001")
	assert_eq(codec.commander(&"commander.fixture").token.value, "c/commander.fixture")
	assert_eq(codec.relic(4).token.value, "r/4")
	assert_eq(codec.trait_source(&"trait.fixture").token.value, "t/trait.fixture")
	assert_eq(
		codec.equipment("u_0000000000000001", 2).token.value,
		"eq/u_0000000000000001/2"
	)


func test_proposal_source_codec_rejects_enemy_summon_leading_zero_and_bad_slots() -> void:
	var codec := ProposalSourceCodecV1.new()
	for token: String in [
		"u/e_0000000000000001",
		"u/s_0000000000000001",
		"r/00",
		"r/5",
		"eq/u_0000000000000001/03",
		"eq/u_0000000000000001/3",
		"c/Commander.Bad",
		"t/trait.fixture/extra",
	]:
		var result := codec.validate(token)
		assert_false(result.ok, token)
		assert_eq(result.error.code, ProposalSourceError.TOKEN_INVALID, token)
	assert_false(codec.player_unit("e_0000000000000001").ok)
	assert_false(codec.relic(-1).ok)
	assert_false(codec.equipment("u_0000000000000001", 3).ok)


func test_rmp2_payload_digest_golden_and_restore_are_exact() -> void:
	var built := RunMutationProposal.create(
		&"once_per_node",
		"u/u_0000000000000001",
		&"effect.fixture",
		1,
		&"add_gold",
		2
	)
	assert_true(built.ok)
	assert_eq(built.proposal.payload_digest, RMP2_GOLDEN)
	var restored := RunMutationProposal.restore(
		built.proposal.claim_scope,
		built.proposal.source_instance_or_slot,
		built.proposal.effect_id,
		built.proposal.operation_index,
		built.proposal.operation_kind,
		built.proposal.amount,
		RMP2_GOLDEN
	)
	assert_true(restored.ok)
	assert_eq(restored.proposal.identity_key(), built.proposal.identity_key())
	var tampered := RunMutationProposal.restore(
		built.proposal.claim_scope,
		built.proposal.source_instance_or_slot,
		built.proposal.effect_id,
		built.proposal.operation_index,
		built.proposal.operation_kind,
		3,
		RMP2_GOLDEN
	)
	assert_false(tampered.ok)
	assert_eq(tampered.error.code, RunMutationProposalError.DIGEST_MISMATCH)


func test_rmp2_rejects_unknown_scope_operation_source_and_u32_overflow() -> void:
	var cases: Array[RunMutationProposalBuildResult] = [
		RunMutationProposal.create(&"per_battle", "r/0", &"effect.fixture", 0, &"add_gold", 1),
		RunMutationProposal.create(&"once_per_node", "e_0000000000000001", &"effect.fixture", 0, &"add_gold", 1),
		RunMutationProposal.create(&"once_per_node", "r/0", &"Effect.Bad", 0, &"add_gold", 1),
		RunMutationProposal.create(&"once_per_node", "r/0", &"effect.fixture", 0, &"grant_relic", 1),
		RunMutationProposal.create(&"once_per_node", "r/0", &"effect.fixture", -1, &"add_gold", 1),
		RunMutationProposal.create(&"once_per_node", "r/0", &"effect.fixture", 0, &"add_gold", 0x100000000),
	]
	for result: RunMutationProposalBuildResult in cases:
		assert_false(result.ok)
		assert_not_null(result.error)
