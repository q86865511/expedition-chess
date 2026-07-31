class_name EconomyCommandSupport
extends RefCounted

static func current_node_id(draft: RunState) -> StringName:
	return StringName(draft.current_node_id.value) if draft != null and draft.current_node_id != null else &""

static func try_named_rng(
	draft: RunState, stream_name: NamedRngState.StreamName
) -> RngSnapshot:
	for state: NamedRngState in draft.rng_stream_states:
		if state.stream_name == stream_name:
			return state.snapshot.deep_clone()
	return null

static func try_shop_rng(draft: RunState) -> RngSnapshot:
	return try_named_rng(draft, NamedRngState.StreamName.SHOP)

static func try_reward_rng(draft: RunState) -> RngSnapshot:
	return try_named_rng(draft, NamedRngState.StreamName.REWARD)

static func set_shop_rng(draft: RunState, snapshot: RngSnapshot) -> void:
	set_named_rng(draft, NamedRngState.StreamName.SHOP, snapshot)

static func set_reward_rng(draft: RunState, snapshot: RngSnapshot) -> void:
	set_named_rng(draft, NamedRngState.StreamName.REWARD, snapshot)

static func append_transaction_receipt(
	draft: RunState,
	receipt: TransactionReceiptState
) -> void:
	draft.transaction_receipts.append(receipt.deep_clone())
	draft.transaction_receipts.sort_custom(func(
		left: TransactionReceiptState,
		right: TransactionReceiptState
	) -> bool:
		return String(left.key.digest) < String(right.key.digest)
	)

static func sort_owners(owners: Array[ReservationOwnerState]) -> void:
	owners.sort_custom(func(
		left: ReservationOwnerState,
		right: ReservationOwnerState
	) -> bool:
		return String(left.key.digest) < String(right.key.digest)
	)

static func set_named_rng(
	draft: RunState, stream_name: NamedRngState.StreamName,
	snapshot: RngSnapshot
) -> void:
	for state: NamedRngState in draft.rng_stream_states:
		if state.stream_name == stream_name:
			state.snapshot = snapshot.deep_clone()
			return
	draft.rng_stream_states.append(NamedRngState.new(stream_name, snapshot))
	draft.rng_stream_states.sort_custom(func(left: NamedRngState, right: NamedRngState) -> bool:
		return left.stream_name < right.stream_name
	)

static func apply_shop_transaction(draft: RunState, transaction: ShopTransaction) -> void:
	draft.economy_state = transaction.economy_state.deep_clone()
	draft.unit_pool_state = transaction.unit_pool_state.deep_clone()
	draft.roster_state = transaction.roster_state.deep_clone()
	draft.reservation_owners.clear()
	for owner: ReservationOwnerState in transaction.reservation_owners:
		draft.reservation_owners.append(owner.deep_clone())
	draft.next_transaction_serial = transaction.next_transaction_serial.deep_clone()
	draft.next_unit_serial = transaction.next_unit_serial.deep_clone()
	set_shop_rng(draft, transaction.next_shop_rng_snapshot)
	append_transaction_receipt(draft, transaction.receipt)
