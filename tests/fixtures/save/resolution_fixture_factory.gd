class_name ResolutionFixtureFactory
extends RefCounted

const BattleFixture = preload("res://tests/fixtures/canonical/battle_setup_fixture.gd")

const PAYLOAD_OWNER: String = "3333333333333333333333333333333333333333333333333333333333333333"
const PAYLOAD_TRANSACTION: String = "4444444444444444444444444444444444444444444444444444444444444444"
const PAYLOAD_CLAIM: String = "5555555555555555555555555555555555555555555555555555555555555555"
const PAYLOAD_SETTLEMENT: String = "6666666666666666666666666666666666666666666666666666666666666666"
const PAYLOAD_REWARD: String = "7777777777777777777777777777777777777777777777777777777777777777"
const PAYLOAD_PROPOSAL: String = "8888888888888888888888888888888888888888888888888888888888888888"
const PAYLOAD_NODE: String = "9999999999999999999999999999999999999999999999999999999999999999"
const PREVIOUS_RUN_ID: StringName = &"run_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

static func create_root(kind: int) -> SaveRoot:
	var root := SaveRootFixture.create_valid_root()
	_decorate_common_identity(root)
	root.run.resolution_state = _create_resolution(root.run, kind)
	match kind:
		ResolutionState.Kind.COMBAT_PENDING, ResolutionState.Kind.BATTLE_RESULT_PENDING:
			root.run.run_phase = RunState.RunPhase.COMBAT
		ResolutionState.Kind.REWARD_PENDING:
			root.run.run_phase = RunState.RunPhase.REWARD
		_:
			root.run.run_phase = RunState.RunPhase.MAP
	return root

static func create_battle_setup() -> BattleSetup:
	var inputs: BattleSetupInputs = BattleFixture.create_inputs()
	var encoded := CanonicalBattleCodecV1.new().encode(inputs)
	var setup := BattleSetup.new()
	setup.inputs = inputs
	setup.hash_version = 1
	setup.battle_setup_hash = StringName(BattleSetupHashBuilder.sha256_hex(encoded.canonical_bytes))
	setup.rng_version = 1
	setup.combat_rng_snapshot = RngSnapshot.create(
		1, _u64("0000000000000009"), _u64("0000000000000003"),
		_u64("0000000000000004")
	).snapshot
	return setup

static func create_all(run: RunState) -> Array[ResolutionState]:
	var values: Array[ResolutionState] = []
	for kind: int in [
		ResolutionState.Kind.IDLE,
		ResolutionState.Kind.COMBAT_PENDING,
		ResolutionState.Kind.BATTLE_RESULT_PENDING,
		ResolutionState.Kind.REWARD_PENDING,
	]:
		values.append(_create_resolution(run, kind))
	return values

static func _decorate_common_identity(root: SaveRoot) -> void:
	var run := root.run
	run.run_seed = _u64("0123456789abcdef")
	run.next_transaction_serial = _u64("0000000000000001")
	run.next_unit_serial = _u64("0000000000000007")
	run.next_item_serial = _u64("0000000000000008")

	var rng_states: Array[NamedRngState] = []
	for stream_index: int in range(4):
		var suffix := stream_index + 1
		var state := _u64("%016x" % suffix)
		var increment := _u64("%016x" % (suffix * 2 + 1))
		var counter := _u64("%016x" % (suffix * 10))
		rng_states.append(NamedRngState.new(
			stream_index, RngSnapshot.create(1, state, increment, counter).snapshot
		))
	run.rng_stream_states = rng_states

	var registry := RuntimeKeySchemaRegistry.new()
	var node_result := registry.build_node(
		StringName(run.run_id), 0, &"normal", 0, 0
	)
	var node_key := node_result.key_state as NodeKeyState
	var nodes: Array[MapNodeState] = [MapNodeState.new(
		String(node_key.digest), node_key, &"mapnode.fixture", 0, 0, 0,
		MapNodeState.NodeKind.NORMAL, PAYLOAD_NODE, null, false
	)]
	var edges: Array[MapEdgeState] = []
	var completed: Array[String] = []
	run.map_state = MapState.new(nodes, edges, null, completed)
	run.current_node_id = null

	var owners: Array[ReservationOwnerState] = []
	var offers: Array[ShopOffer] = []
	for slot_index: int in range(5):
		var owner_result := registry.build_reservation_owner(
			StringName(run.run_id), node_key.digest, &"shop", &"refresh_0", slot_index
		)
		var owner_key := owner_result.key_state as ReservationOwnerKeyState
		offers.append(ShopOffer.new(
			slot_index, String(owner_key.digest), &"unit.fixture", 1, 1, owner_key
		))
		owners.append(ReservationOwnerState.new(
			owner_key, &"unit.fixture", 1, ReservationOwnerState.Status.ACTIVE,
			PAYLOAD_OWNER
		))
	_sort_owners(owners)
	run.reservation_owners = owners
	run.economy_state.shop_offers = offers
	var pool_entries: Array[UnitPoolEntryState] = [
		UnitPoolEntryState.new(&"unit.fixture", 5, 0, 5, 0)
	]
	run.unit_pool_state = UnitPoolState.new(pool_entries)

	var committed_transaction := registry.build_transaction(
		StringName(run.run_id), node_key.digest, &"node_income", U64Bits.zero()
	)
	var transaction_receipts: Array[TransactionReceiptState] = [
		TransactionReceiptState.new(
			committed_transaction.key_state as TransactionKeyState, PAYLOAD_TRANSACTION
		)
	]
	run.transaction_receipts = transaction_receipts

	var committed_claim := registry.build_effect_claim(
		StringName(run.run_id), node_key.digest, &"run", &"slot_0",
		&"effect.fixture", 0
	)
	var claim_receipts: Array[ClaimReceiptState] = [
		ClaimReceiptState.new(committed_claim.key_state as EffectClaimKeyState, PAYLOAD_CLAIM)
	]
	run.claim_receipts = claim_receipts

	var settlement := registry.build_settlement_receipt(PREVIOUS_RUN_ID)
	var settlement_receipts: Array[SettlementReceiptState] = [
		SettlementReceiptState.new(
			settlement.key_state as SettlementReceiptKeyState,
			SettlementReceiptState.Outcome.COMPLETED, 3, PAYLOAD_SETTLEMENT
		)
	]
	root.profile.settlement_receipts = settlement_receipts

static func _create_resolution(run: RunState, kind: int) -> ResolutionState:
	match kind:
		ResolutionState.Kind.IDLE:
			return IdleResolutionState.new()
		ResolutionState.Kind.COMBAT_PENDING:
			return CombatPendingResolutionState.new(create_battle_setup())
		ResolutionState.Kind.BATTLE_RESULT_PENDING:
			return _create_battle_result_pending(run)
		ResolutionState.Kind.REWARD_PENDING:
			return _create_reward_pending(run)
	return IdleResolutionState.new()

static func _create_battle_result_pending(run: RunState) -> ResolutionState:
	var setup := create_battle_setup()
	var result := BattleResult.new()
	result.battle_setup_hash = setup.battle_setup_hash
	result.outcome = &"player_win"
	result.final_tick = 20
	result.survivor_instance_ids = [&"u_0000000000000001"]
	result.expedition_damage = 0
	result.summary_hash = &"0000000000000000000000000000000000000000000000000000000000000000"
	var proposal_result := RunMutationProposal.create(
		&"once_per_node",
		"u/u_0000000000000001",
		&"effect.fixture",
		1,
		&"add_gold",
		2
	)
	assert(proposal_result.ok)
	result.run_mutation_proposals.append(proposal_result.proposal)
	var sealed := BattleResultCodecV1.new().seal(result.to_record())
	assert(sealed.ok)
	return BattleResultPendingResolutionState.new(
		String(setup.battle_setup_hash), BattleResult.from_record(sealed.record)
	)

static func _create_reward_pending(run: RunState) -> ResolutionState:
	var registry := RuntimeKeySchemaRegistry.new()
	var node_id := run.map_state.nodes[0].node_key.digest
	run.current_node_id = OptionalStringValue.new(String(node_id))
	run.map_state.current_node_id = OptionalStringValue.new(String(node_id))
	var owner_result := registry.build_reservation_owner(
		StringName(run.run_id), node_id, &"reward", &"standard", 0
	)
	var owner_key := owner_result.key_state as ReservationOwnerKeyState
	run.reservation_owners.append(ReservationOwnerState.new(
		owner_key, &"unit.fixture", 1, ReservationOwnerState.Status.ACTIVE, PAYLOAD_REWARD
	))
	_sort_owners(run.reservation_owners)
	run.unit_pool_state.entries[0].total_copies = 6
	run.unit_pool_state.entries[0].reserved_copies = 6

	var transaction := registry.build_transaction(
		StringName(run.run_id), node_id, &"reward", run.next_transaction_serial
	)
	var offers: Array[RewardOfferState] = [
		RewardOfferState.new(
			"choice_0", RewardOfferState.RewardKind.UNIT,
			OptionalStringNameValue.of(&"unit.fixture"), 1, owner_key, PAYLOAD_REWARD
		),
		RewardOfferState.new(
			"choice_1", RewardOfferState.RewardKind.GOLD,
			null, 3, null, PAYLOAD_TRANSACTION
		),
		RewardOfferState.new(
			"choice_2", RewardOfferState.RewardKind.GOLD,
			null, 1, null, PAYLOAD_CLAIM
		),
	]
	var reserved: Array[ReservedCopyState] = [
		ReservedCopyState.new(&"unit.fixture", 1, owner_key)
	]
	var pending := PendingRewardState.new(
		String(node_id), PendingRewardState.StageId.STANDARD,
		PendingRewardState.Phase.CHOOSING, offers, reserved, null, null,
		transaction.key_state as TransactionKeyState
	)
	return RewardPendingResolutionState.new(pending)

static func _sort_owners(owners: Array[ReservationOwnerState]) -> void:
	for index: int in range(1, owners.size()):
		var current := owners[index]
		var insert_at := index
		while insert_at > 0 and String(owners[insert_at - 1].key.digest) > String(current.key.digest):
			owners[insert_at] = owners[insert_at - 1]
			insert_at -= 1
		owners[insert_at] = current

static func _u64(hex_value: String) -> U64Bits:
	return U64Bits.from_hex(hex_value).value
