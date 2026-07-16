class_name ResolutionRetryHarness
extends RefCounted

func run_case(kind: int) -> ResolutionRetryResult:
	var storage := FakeSaveStorage.new()
	var repository := SaveRootFixture.create_repository(storage)
	var codec := SaveRootFixture.create_codec()
	var root := ResolutionFixtureFactory.create_root(kind)
	var validation := RunStateValidator.new().validate_root(root)
	if not validation.ok:
		repository.free()
		return ResolutionRetryResult.failure(validation.error.field_path)
	var before := codec.encode(root)
	if not before.ok:
		repository.free()
		return ResolutionRetryResult.failure(before.error.field_path)
	var before_key_count := _key_count(root)
	var first_save := repository.save(root)
	if not first_save.ok:
		repository.free()
		return ResolutionRetryResult.failure(
			first_save.error.field_path, before.json_text.value, "", before_key_count, -1
		)
	var first_load := repository.load()
	if not first_load.ok or first_load.run == null:
		repository.free()
		return ResolutionRetryResult.failure(
			&"first_load", before.json_text.value, "", before_key_count, -1
		)
	var retry_root := SaveRoot.new(
		root.schema_version, root.content_version, root.app_version,
		root.rng_version, root.hash_version, root.saved_at_utc,
		first_load.profile, first_load.run
	)
	var first_identity_error := _identity_error(root, retry_root)
	if not first_identity_error.is_empty():
		repository.free()
		return ResolutionRetryResult.failure(
			first_identity_error, before.json_text.value, "", before_key_count,
			_key_count(retry_root)
		)
	var second_save := repository.save(retry_root)
	if not second_save.ok:
		repository.free()
		return ResolutionRetryResult.failure(
			second_save.error.field_path, before.json_text.value, "", before_key_count,
			_key_count(retry_root)
		)
	var second_load := repository.load()
	if not second_load.ok or second_load.run == null:
		repository.free()
		return ResolutionRetryResult.failure(
			&"second_load", before.json_text.value, "", before_key_count, -1
		)
	var after_root := SaveRoot.new(
		root.schema_version, root.content_version, root.app_version,
		root.rng_version, root.hash_version, root.saved_at_utc,
		second_load.profile, second_load.run
	)
	var after := codec.encode(after_root)
	if not after.ok:
		repository.free()
		return ResolutionRetryResult.failure(
			after.error.field_path, before.json_text.value, "", before_key_count,
			_key_count(after_root)
		)
	if before.json_text.value != after.json_text.value:
		repository.free()
		return ResolutionRetryResult.failure(
			&"canonical_bytes", before.json_text.value, after.json_text.value,
			before_key_count, _key_count(after_root)
		)
	var identity_error := _identity_error(root, after_root)
	if not identity_error.is_empty():
		repository.free()
		return ResolutionRetryResult.failure(
			identity_error, before.json_text.value, after.json_text.value,
			before_key_count, _key_count(after_root)
		)
	var result := ResolutionRetryResult.success(
		before.json_text.value, after.json_text.value,
		before_key_count, _key_count(after_root)
	)
	repository.free()
	return result

func _identity_error(before: SaveRoot, after: SaveRoot) -> StringName:
	if before.run.run_seed.to_hex() != after.run.run_seed.to_hex():
		return &"seed"
	if _candidate_identity(before.run) != _candidate_identity(after.run):
		return &"candidate"
	if _reservation_identity(before.run) != _reservation_identity(after.run):
		return &"reservation"
	if _transaction_identity(before.run) != _transaction_identity(after.run):
		return &"transaction"
	if _claim_identity(before.run) != _claim_identity(after.run):
		return &"claim"
	if _receipt_identity(before.profile) != _receipt_identity(after.profile):
		return &"receipt"
	if _serial_identity(before.run) != _serial_identity(after.run):
		return &"serial"
	if _rng_identity(before.run) != _rng_identity(after.run):
		return &"rng_counter"
	if _key_count(before) != _key_count(after):
		return &"key_count"
	return &""

func _candidate_identity(run: RunState) -> Array[String]:
	var values: Array[String] = []
	for offer: ShopOffer in run.economy_state.shop_offers:
		values.append("shop|%d|%s|%s|%d|%d|%s" % [
			offer.slot_index, offer.offer_id, String(offer.unit_def_id), offer.cost,
			offer.reserved_copies, _key_fingerprint(offer.reservation_owner_key)
		])
	if run.resolution_state is RewardPendingResolutionState:
		var reward := run.resolution_state as RewardPendingResolutionState
		for offer: RewardOfferState in reward.pending_reward.offers:
			values.append("reward|%s|%d|%s|%d|%s|%s" % [
				offer.choice_id, offer.reward_kind,
				String(offer.content_id.value) if offer.content_id != null else "null",
				offer.amount,
				_key_fingerprint(offer.reservation_owner_key), offer.payload_digest
			])
	return values

func _reservation_identity(run: RunState) -> Array[String]:
	var values: Array[String] = []
	for owner: ReservationOwnerState in run.reservation_owners:
		values.append("owner|%s|%s|%d|%d|%s" % [
			_key_fingerprint(owner.key), String(owner.unit_def_id),
			owner.reserved_copies, owner.status, owner.payload_digest
		])
	if run.resolution_state is RewardPendingResolutionState:
		var reward := run.resolution_state as RewardPendingResolutionState
		for reserved: ReservedCopyState in reward.pending_reward.reserved_copies:
			values.append("reserved|%s|%d|%s" % [
				String(reserved.unit_def_id), reserved.copies,
				_key_fingerprint(reserved.reservation_owner_key)
			])
		if reward.pending_reward.selected_unit_reservation != null:
			values.append("selected|%s" % _key_fingerprint(
				reward.pending_reward.selected_unit_reservation
			))
	return values

func _transaction_identity(run: RunState) -> Array[String]:
	var values: Array[String] = []
	for receipt: TransactionReceiptState in run.transaction_receipts:
		values.append("receipt|%s|%s" % [
			_key_fingerprint(receipt.key), receipt.payload_digest
		])
	if run.resolution_state is RewardPendingResolutionState:
		var reward := run.resolution_state as RewardPendingResolutionState
		values.append("pending|%s" % _key_fingerprint(reward.pending_reward.transaction_id))
	return values

func _claim_identity(run: RunState) -> Array[String]:
	var values: Array[String] = []
	for receipt: ClaimReceiptState in run.claim_receipts:
		values.append("receipt|%s|%s" % [
			_key_fingerprint(receipt.key), receipt.payload_digest
		])
	if run.resolution_state is BattleResultPendingResolutionState:
		var battle := run.resolution_state as BattleResultPendingResolutionState
		for proposal: RunMutationProposal in battle.battle_result.run_mutation_proposals:
			values.append("proposal|%s|%s|%s|%d|%s|%d|%s" % [
				String(proposal.claim_scope), proposal.source_instance_or_slot,
				String(proposal.effect_id), proposal.operation_index,
				String(proposal.operation_kind), proposal.amount, proposal.payload_digest
			])
	return values

func _receipt_identity(profile: ProfileState) -> Array[String]:
	var values: Array[String] = []
	for receipt: SettlementReceiptState in profile.settlement_receipts:
		values.append("%s|%d|%d|%s" % [
			_key_fingerprint(receipt.key), receipt.outcome,
			receipt.currency_delta, receipt.payload_digest
		])
	return values

func _serial_identity(run: RunState) -> Array[String]:
	return [
		run.next_transaction_serial.to_hex(),
		run.next_unit_serial.to_hex(),
		run.next_item_serial.to_hex(),
	]

func _rng_identity(run: RunState) -> Array[String]:
	var values: Array[String] = []
	for named: NamedRngState in run.rng_stream_states:
		values.append("%d|%d|%s|%s|%s" % [
			named.stream_name, named.snapshot.rng_version,
			named.snapshot.state.to_hex(), named.snapshot.inc.to_hex(),
			named.snapshot.counter.to_hex()
		])
	return values

func _key_count(root: SaveRoot) -> int:
	var digests: Array[String] = []
	_append_key(digests, root.run.run_key)
	for node: MapNodeState in root.run.map_state.nodes:
		_append_key(digests, node.node_key)
	for owner: ReservationOwnerState in root.run.reservation_owners:
		_append_key(digests, owner.key)
	for receipt: TransactionReceiptState in root.run.transaction_receipts:
		_append_key(digests, receipt.key)
	for receipt: ClaimReceiptState in root.run.claim_receipts:
		_append_key(digests, receipt.key)
	for receipt: SettlementReceiptState in root.profile.settlement_receipts:
		_append_key(digests, receipt.key)
	if root.run.resolution_state is RewardPendingResolutionState:
		var reward := root.run.resolution_state as RewardPendingResolutionState
		_append_key(digests, reward.pending_reward.transaction_id)
		for offer: RewardOfferState in reward.pending_reward.offers:
			_append_key(digests, offer.reservation_owner_key)
		for reserved: ReservedCopyState in reward.pending_reward.reserved_copies:
			_append_key(digests, reserved.reservation_owner_key)
	return digests.size()

func _append_key(digests: Array[String], key: RuntimeKeyState) -> void:
	if key == null:
		return
	var digest := String(key.digest)
	if not digests.has(digest):
		digests.append(digest)

func _key_fingerprint(key: RuntimeKeyState) -> String:
	if key == null:
		return "null"
	if key is RunKeyState:
		var typed := key as RunKeyState
		return "run|%s|%s|%s" % [
			typed.profile_id, typed.next_run_serial.to_hex(), String(typed.digest)
		]
	if key is NodeKeyState:
		var typed := key as NodeKeyState
		return "node|%s|%d|%s|%d|%d|%s" % [
			String(typed.run_id), typed.act_index, String(typed.node_kind),
			typed.layer_index, typed.slot_index, String(typed.digest)
		]
	if key is ReservationOwnerKeyState:
		var typed := key as ReservationOwnerKeyState
		return "reservation_owner|%s|%s|%s|%s|%d|%s" % [
			String(typed.run_id), String(typed.node_id), String(typed.source_kind),
			String(typed.stage_or_refresh_id), typed.slot_index, String(typed.digest)
		]
	if key is TransactionKeyState:
		var typed := key as TransactionKeyState
		return "transaction|%s|%s|%s|%s|%s" % [
			String(typed.run_id), String(typed.node_id_or_camp),
			String(typed.command_kind), typed.next_transaction_serial.to_hex(),
			String(typed.digest)
		]
	if key is EffectClaimKeyState:
		var typed := key as EffectClaimKeyState
		return "effect_claim|%s|%s|%s|%s|%s|%d|%s" % [
			String(typed.run_id), String(typed.node_id), String(typed.claim_scope),
			String(typed.source_instance_or_slot), String(typed.effect_id),
			typed.operation_index, String(typed.digest)
		]
	if key is SettlementReceiptKeyState:
		var typed := key as SettlementReceiptKeyState
		return "settlement_receipt|%s|%s" % [
			String(typed.run_id), String(typed.digest)
		]
	return "%s|%s" % [String(key.kind), String(key.digest)]
