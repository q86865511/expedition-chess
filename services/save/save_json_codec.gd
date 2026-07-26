class_name SaveJsonCodec
extends RefCounted

const SCHEMA_VERSION: int = SaveSchemaContract.CURRENT

var _receipt_port: PinnedCatalogReceiptPort
var _migration_port: ContentIdMigrationPort
var _validator: RunStateValidator
var _decode_error_path: StringName = &""
var _run_incompatible_content_ids: Array[StringName] = []
var _migration_diagnostics: Array[LoadDiagnostic] = []
var _active_receipt_ids: Array[StringName] = []

func _init(
	receipt_port: PinnedCatalogReceiptPort,
	migration_port: ContentIdMigrationPort
) -> void:
	_receipt_port = receipt_port
	_migration_port = migration_port
	_validator = RunStateValidator.new()

func encode(root: SaveRoot) -> SaveEncodeResult:
	var validation := _validator.validate_root(root)
	if not validation.ok:
		return SaveEncodeResult.failure(SaveCodecError.new(validation.error.field_path))
	var text := _encode_root(root)
	var bytes := text.to_utf8_buffer()
	return SaveEncodeResult.success(text, bytes, _sha256(bytes))

func decode_text(text: String) -> SaveDecodeResult:
	var parser := JSON.new()
	if parser.parse(text) != OK or not parser.data is Dictionary:
		return _decode_failure(&"root")
	var decoded := _decode_root(parser.data)
	if not decoded.ok or decoded.root == null:
		return decoded
	var reencoded := encode(decoded.root)
	if not reencoded.ok or reencoded.json_text.value != text:
		return _decode_failure(&"root.canonical_bytes")
	return decoded

func decode_bytes(bytes: PackedByteArray) -> SaveDecodeResult:
	var text := bytes.get_string_from_utf8()
	if text.to_utf8_buffer() != bytes:
		return SaveDecodeResult.failure(SaveCodecError.new(
			&"bytes", [], SaveCodecError.UTF8_INVALID
		))
	return decode_text(text)

func _encode_root(root: SaveRoot) -> String:
	var fields: Array[String] = []
	fields.append(_field("schema_version", str(root.schema_version)))
	fields.append(_field("content_version", _quote(root.content_version)))
	fields.append(_field("app_version", _quote(root.app_version)))
	fields.append(_field("rng_version", str(root.rng_version)))
	fields.append(_field("hash_version", str(root.hash_version)))
	fields.append(_field("saved_at_utc", _quote(root.saved_at_utc)))
	fields.append(_field("profile", _encode_profile(root.profile)))
	fields.append(_field("run", _encode_run(root.run) if root.run != null else "null"))
	return _object(fields)

func _encode_profile(profile: ProfileState) -> String:
	var fields: Array[String] = []
	fields.append(_field("profile_id", _quote(profile.profile_id)))
	fields.append(_field("next_run_serial", _quote(profile.next_run_serial.to_hex())))
	fields.append(_field("meta_currency", str(profile.meta_currency)))
	fields.append(_field("unlocked_content_ids", _name_array(profile.unlocked_content_ids)))
	fields.append(_field("discovered_content_ids", _name_array(profile.discovered_content_ids)))
	fields.append(_field("highest_challenge_level", str(profile.highest_challenge_level)))
	var receipts: Array[String] = []
	for receipt: SettlementReceiptState in profile.settlement_receipts:
		receipts.append(_encode_settlement_receipt(receipt))
	fields.append(_field("settlement_receipts", _array(receipts)))
	fields.append(_field("settings_ref", _quote(String(profile.settings_ref))))
	fields.append(_field(
		"last_selection",
		_encode_last_selection(profile.last_selection) if profile.last_selection != null else "null"
	))
	var records: Array[String] = []
	for record: CommanderChallengeRecordState in profile.commander_challenge_records:
		records.append(_encode_commander_challenge_record(record))
	fields.append(_field("commander_challenge_records", _array(records)))
	return _object(fields)

func _encode_last_selection(selection: ProfileLastSelectionState) -> String:
	return _object([
		_field("commander_id", _quote(String(selection.commander_id))),
		_field("challenge_level", str(selection.challenge_level)),
	])

func _encode_commander_challenge_record(record: CommanderChallengeRecordState) -> String:
	return _object([
		_field("commander_id", _quote(String(record.commander_id))),
		_field("highest_cleared_level", str(record.highest_cleared_level)),
	])

func _encode_settlement_receipt(receipt: SettlementReceiptState) -> String:
	return _object([
		_field("key", _encode_settlement_key(receipt.key)),
		_field("outcome", _quote(["completed", "failed", "abandoned"][receipt.outcome])),
		_field("currency_delta", str(receipt.currency_delta)),
		_field("payload_digest", _quote(receipt.payload_digest)),
	])

func _encode_run(run: RunState) -> String:
	var fields: Array[String] = []
	fields.append(_field("run_id", _quote(run.run_id)))
	fields.append(_field("run_key", _encode_run_key(run.run_key)))
	fields.append(_field("run_seed", _quote(run.run_seed.to_hex())))
	fields.append(_field("content_snapshot", _encode_content_snapshot(run.content_snapshot)))
	fields.append(_field("next_transaction_serial", _quote(run.next_transaction_serial.to_hex())))
	fields.append(_field("next_unit_serial", _quote(run.next_unit_serial.to_hex())))
	fields.append(_field("next_item_serial", _quote(run.next_item_serial.to_hex())))
	fields.append(_field("commander_id", _quote(String(run.commander_id))))
	fields.append(_field("challenge_level", str(run.challenge_level)))
	fields.append(_field("act_index", str(run.act_index)))
	fields.append(_field("map_state", _encode_map(run.map_state)))
	fields.append(_field("current_node_id", _optional_string(run.current_node_id)))
	fields.append(_field("run_phase", _quote(["MAP", "PREPARE", "COMBAT", "REWARD", "RESULTS"][run.run_phase])))
	fields.append(_field("expedition_hp", str(run.expedition_hp)))
	fields.append(_field("economy_state", _encode_economy(run.economy_state)))
	fields.append(_field("unit_pool_state", _encode_pool(run.unit_pool_state)))
	fields.append(_field("roster_state", _encode_roster(run.roster_state)))
	fields.append(_field("cleared_normal_count", str(run.cleared_normal_count)))
	fields.append(_field("cleared_elite_count", str(run.cleared_elite_count)))
	fields.append(_field("defeated_boss_count", str(run.defeated_boss_count)))
	var rng_values: Array[String] = []
	for named: NamedRngState in run.rng_stream_states:
		rng_values.append(_encode_named_rng(named))
	fields.append(_field("rng_stream_states", _array(rng_values)))
	fields.append(_field("income_claimed_node_ids", _string_array(run.income_claimed_node_ids)))
	fields.append(_field("loss_stipend_claimed_act_ids", _int_array(run.loss_stipend_claimed_act_ids)))
	var owners: Array[String] = []
	for owner: ReservationOwnerState in run.reservation_owners:
		owners.append(_encode_reservation_owner(owner))
	fields.append(_field("reservation_owners", _array(owners)))
	var transactions: Array[String] = []
	for receipt: TransactionReceiptState in run.transaction_receipts:
		transactions.append(_encode_transaction_receipt(receipt))
	fields.append(_field("transaction_receipts", _array(transactions)))
	var claims: Array[String] = []
	for receipt: ClaimReceiptState in run.claim_receipts:
		claims.append(_encode_claim_receipt(receipt))
	fields.append(_field("claim_receipts", _array(claims)))
	fields.append(_field("resolution_state", _encode_resolution(run.resolution_state)))
	fields.append(_field("discovered_content_ids", _name_array(run.discovered_content_ids)))
	return _object(fields)

func _encode_content_snapshot(snapshot: ContentSnapshotState) -> String:
	return _object([
		_field("content_version", _quote(snapshot.content_version_value())),
		_field("enabled_content_ids", _name_array(snapshot.enabled_content_ids_copy())),
		_field("economy_config_id", _quote(String(snapshot.economy_config_id_value()))),
		_field("combat_config_id", _quote(String(snapshot.combat_config_id_value()))),
		_field("reward_table_ids", _name_array(snapshot.reward_table_ids_copy())),
		_field("map_node_def_ids", _name_array(snapshot.map_node_def_ids_copy())),
		_field("challenge_unlock_def_ids", _name_array(snapshot.challenge_unlock_def_ids_copy())),
		_field("meta_reward_table_id", _quote(String(snapshot.meta_reward_table_id_value()))),
		_field("manifest_digest", _quote(snapshot.manifest_digest_value())),
	])

func _encode_map(map: MapState) -> String:
	var nodes: Array[String] = []
	for node: MapNodeState in map.nodes:
		nodes.append(_encode_map_node(node))
	var edges: Array[String] = []
	for edge: MapEdgeState in map.edges:
		edges.append(_object([
			_field("from_node_id", _quote(edge.from_node_id)),
			_field("to_node_id", _quote(edge.to_node_id)),
		]))
	return _object([
		_field("nodes", _array(nodes)),
		_field("edges", _array(edges)),
		_field("current_node_id", _optional_string(map.current_node_id)),
		_field("completed_node_ids", _string_array(map.completed_node_ids)),
	])

func _encode_map_node(node: MapNodeState) -> String:
	return _object([
		_field("node_id", _quote(node.node_id)),
		_field("node_key", _encode_node_key(node.node_key)),
		_field("def_id", _quote(String(node.def_id))),
		_field("act_index", str(node.act_index)),
		_field("layer_index", str(node.layer_index)),
		_field("slot_index", str(node.slot_index)),
		_field("node_kind", _quote(String(MapNodeState.node_kind_to_token(node.node_kind)))),
		_field("generated_payload_digest", _quote(node.generated_payload_digest)),
		_field("encounter_preview", _encode_preview(node.encounter_preview) if node.encounter_preview != null else "null"),
		_field("completed", "true" if node.completed else "false"),
	])

func _encode_economy(economy: EconomyState) -> String:
	var offers: Array[String] = []
	for offer: ShopOffer in economy.shop_offers:
		offers.append(_object([
			_field("slot_index", str(offer.slot_index)),
			_field("offer_id", _quote(offer.offer_id)),
			_field("unit_def_id", _quote(String(offer.unit_def_id))),
			_field("cost", str(offer.cost)),
			_field("reserved_copies", str(offer.reserved_copies)),
			_field("reservation_owner_key", _encode_reservation_key(offer.reservation_owner_key)),
		]))
	return _object([
		_field("gold", str(economy.gold)),
		_field("level", str(economy.level)),
		_field("xp", str(economy.xp)),
		_field("win_streak", str(economy.win_streak)),
		_field("loss_streak", str(economy.loss_streak)),
		_field("shop_refresh_index", str(economy.shop_refresh_index)),
		_field("shop_offers", _array(offers)),
	])

func _encode_pool(pool: UnitPoolState) -> String:
	var entries: Array[String] = []
	for entry: UnitPoolEntryState in pool.entries:
		entries.append(_object([
			_field("unit_def_id", _quote(String(entry.unit_def_id))),
			_field("total_copies", str(entry.total_copies)),
			_field("remaining_copies", str(entry.remaining_copies)),
			_field("reserved_copies", str(entry.reserved_copies)),
			_field("held_copies", str(entry.held_copies)),
		]))
	return _object([_field("entries", _array(entries))])

func _encode_roster(roster: RosterState) -> String:
	var placements: Array[String] = []
	for placement: BoardPlacementState in roster.board.placements:
		placements.append(_object([
			_field("logical_y", str(placement.logical_y)),
			_field("logical_x", str(placement.logical_x)),
			_field("unit_instance_id", _quote(placement.unit_instance_id)),
		]))
	var units: Array[String] = []
	for unit: UnitInstance in roster.unit_instances:
		units.append(_object([
			_field("instance_id", _quote(unit.instance_id)),
			_field("def_id", _quote(String(unit.def_id))),
			_field("star", str(unit.star)),
			_field("equipment_instance_ids", _string_array(unit.equipment_instance_ids)),
			_field("acquired_serial", _quote(unit.acquired_serial.to_hex())),
		]))
	var items: Array[String] = []
	for item: ItemInstanceState in roster.item_instances:
		items.append(_object([
			_field("instance_id", _quote(item.instance_id)),
			_field("def_id", _quote(String(item.def_id))),
			_field("bound_unit_instance_id", _optional_string(item.bound_unit_instance_id)),
			_field("acquired_serial", _quote(item.acquired_serial.to_hex())),
		]))
	var relics: Array[String] = []
	for relic: RelicSlotState in roster.active_relic_slots:
		relics.append(_object([
			_field("slot_index", str(relic.slot_index)),
			_field("relic_id", _quote(String(relic.relic_id.value)) if relic.relic_id != null else "null"),
		]))
	return _object([
		_field("board", _object([_field("placements", _array(placements))])),
		_field("bench_unit_instance_ids", _string_array(roster.bench_unit_instance_ids)),
		_field("unit_instances", _array(units)),
		_field("item_instances", _array(items)),
		_field("inventory_item_instance_ids", _string_array(roster.inventory_item_instance_ids)),
		_field("pending_item_overflow", _string_array(roster.pending_item_overflow)),
		_field("active_relic_slots", _array(relics)),
	])

func _encode_named_rng(named: NamedRngState) -> String:
	return _object([
		_field("stream_name", _quote(["map", "shop", "reward", "combat"][named.stream_name])),
		_field("snapshot", _encode_rng_snapshot(named.snapshot)),
	])

func _encode_rng_snapshot(snapshot: RngSnapshot) -> String:
	return _object([
		_field("rng_version", str(snapshot.rng_version)),
		_field("state", _quote(snapshot.state.to_hex())),
		_field("inc", _quote(snapshot.inc.to_hex())),
		_field("counter", _quote(snapshot.counter.to_hex())),
	])

func _encode_run_key(key: RunKeyState) -> String:
	return _object([
		_field("kind", _quote("run")),
		_field("profile_id", _quote(key.profile_id)),
		_field("next_run_serial", _quote(key.next_run_serial.to_hex())),
		_field("digest", _quote(String(key.digest))),
	])

func _encode_node_key(key: NodeKeyState) -> String:
	return _object([
		_field("kind", _quote("node")),
		_field("run_id", _quote(String(key.run_id))),
		_field("act_index", str(key.act_index)),
		_field("node_kind", _quote(String(key.node_kind))),
		_field("layer_index", str(key.layer_index)),
		_field("slot_index", str(key.slot_index)),
		_field("digest", _quote(String(key.digest))),
	])

func _encode_reservation_key(key: ReservationOwnerKeyState) -> String:
	return _object([
		_field("kind", _quote("reservation_owner")),
		_field("run_id", _quote(String(key.run_id))),
		_field("node_id", _quote(String(key.node_id))),
		_field("source_kind", _quote(String(key.source_kind))),
		_field("stage_or_refresh_id", _quote(String(key.stage_or_refresh_id))),
		_field("slot_index", str(key.slot_index)),
		_field("digest", _quote(String(key.digest))),
	])

func _encode_transaction_key(key: TransactionKeyState) -> String:
	return _object([
		_field("kind", _quote("transaction")),
		_field("run_id", _quote(String(key.run_id))),
		_field("node_id_or_camp", _quote(String(key.node_id_or_camp))),
		_field("command_kind", _quote(String(key.command_kind))),
		_field("next_transaction_serial", _quote(key.next_transaction_serial.to_hex())),
		_field("digest", _quote(String(key.digest))),
	])

func _encode_claim_key(key: EffectClaimKeyState) -> String:
	return _object([
		_field("kind", _quote("effect_claim")),
		_field("run_id", _quote(String(key.run_id))),
		_field("node_id", _quote(String(key.node_id))),
		_field("claim_scope", _quote(String(key.claim_scope))),
		_field("source_instance_or_slot", _quote(String(key.source_instance_or_slot))),
		_field("effect_id", _quote(String(key.effect_id))),
		_field("operation_index", str(key.operation_index)),
		_field("digest", _quote(String(key.digest))),
	])

func _encode_settlement_key(key: SettlementReceiptKeyState) -> String:
	return _object([
		_field("kind", _quote("settlement_receipt")),
		_field("run_id", _quote(String(key.run_id))),
		_field("digest", _quote(String(key.digest))),
	])

func _encode_reservation_owner(owner: ReservationOwnerState) -> String:
	return _object([
		_field("key", _encode_reservation_key(owner.key)),
		_field("unit_def_id", _quote(String(owner.unit_def_id))),
		_field("reserved_copies", str(owner.reserved_copies)),
		_field("status", _quote(["active", "consumed", "released"][owner.status])),
		_field("payload_digest", _quote(owner.payload_digest)),
	])

func _encode_transaction_receipt(receipt: TransactionReceiptState) -> String:
	return _object([
		_field("key", _encode_transaction_key(receipt.key)),
		_field("payload_digest", _quote(receipt.payload_digest)),
	])

func _encode_claim_receipt(receipt: ClaimReceiptState) -> String:
	return _object([
		_field("key", _encode_claim_key(receipt.key)),
		_field("payload_digest", _quote(receipt.payload_digest)),
	])

func _encode_resolution(resolution: ResolutionState) -> String:
	if resolution is IdleResolutionState:
		return _object([_field("kind", _quote("idle"))])
	if resolution is CombatPendingResolutionState:
		var combat: CombatPendingResolutionState = resolution
		return _object([
			_field("kind", _quote("combat_pending")),
			_field("battle_setup", _encode_battle_setup(combat.battle_setup)),
		])
	if resolution is BattleResultPendingResolutionState:
		var battle: BattleResultPendingResolutionState = resolution
		return _object([
			_field("kind", _quote("battle_result_pending")),
			_field("battle_setup_hash", _quote(battle.battle_setup_hash)),
			_field("battle_result", _encode_battle_result(battle.battle_result)),
		])
	var reward: RewardPendingResolutionState = resolution
	return _object([
		_field("kind", _quote("reward_pending")),
		_field("pending_reward", _encode_pending_reward(reward.pending_reward)),
	])

func _encode_battle_setup(setup: BattleSetup) -> String:
	return _object([
		_field("inputs", _encode_battle_inputs(setup.inputs)),
		_field("hash_version", str(setup.hash_version)),
		_field("battle_setup_hash", _quote(String(setup.battle_setup_hash))),
		_field("rng_version", str(setup.rng_version)),
		_field("combat_rng_snapshot", _encode_rng_snapshot(setup.combat_rng_snapshot)),
		_field("battle_setup_envelope_digest", _quote(String(setup.battle_setup_envelope_digest))),
	])

func _encode_battle_inputs(inputs: BattleSetupInputs) -> String:
	if inputs != null and inputs.setup_schema_version == 2:
		var encoded_v2: BattleCodecResult = CanonicalBattleCodecV2.new().encode(inputs)
		return encoded_v2.canonical_bytes.get_string_from_utf8() if encoded_v2.ok else "null"
	var units: Array[String] = []
	for unit: UnitBattleSnapshot in inputs.player_units:
		units.append(_encode_unit_battle(unit, 1))
	var traits: Array[String] = []
	for trait_snapshot: TraitBattleSnapshot in inputs.player_active_traits:
		traits.append(_encode_trait_battle(trait_snapshot, 1))
	var equipment: Array[String] = []
	for effect: BattleEffectSnapshot in inputs.player_equipment_effects:
		equipment.append(_encode_battle_effect(effect, 1))
	var relics: Array[String] = []
	for effect: BattleEffectSnapshot in inputs.player_relic_effects:
		relics.append(_encode_battle_effect(effect, 1))
	var commander: Array[String] = []
	for effect: BattleEffectSnapshot in inputs.commander_effects:
		commander.append(_encode_battle_effect(effect, 1))
	var challenge: Array[String] = []
	for effect: BattleEffectSnapshot in inputs.challenge_modifiers:
		challenge.append(_encode_battle_effect(effect, 1))
	return _object([
		_field("setup_schema_version", str(inputs.setup_schema_version)),
		_field("content_version", _quote(inputs.content_version)),
		_field("manifest_digest", _quote(String(inputs.manifest_digest))),
		_field("encounter_snapshot", _encode_preview(inputs.encounter_snapshot, 1)),
		_field("player_units", _array(units)),
		_field("player_active_traits", _array(traits)),
		_field("player_equipment_effects", _array(equipment)),
		_field("player_relic_effects", _array(relics)),
		_field("commander_effects", _array(commander)),
		_field("challenge_modifiers", _array(challenge)),
		_field("battle_rules", _object([
			_field("tick_rate", str(inputs.battle_rules.tick_rate)),
			_field("board_width", str(inputs.battle_rules.board_width)),
			_field("board_height", str(inputs.battle_rules.board_height)),
			_field("soft_limit_ticks", str(inputs.battle_rules.soft_limit_ticks)),
			_field("hard_limit_ticks", str(inputs.battle_rules.hard_limit_ticks)),
		])),
	])

func _encode_battle_result(result: BattleResult) -> String:
	if result == null:
		return "null"
	var encoded := BattleResultCodecV1.new().encode(result.to_record())
	return encoded.canonical_bytes.get_string_from_utf8() if encoded.ok else "null"

func _encode_pending_reward(pending: PendingRewardState) -> String:
	var offers: Array[String] = []
	for offer: RewardOfferState in pending.offers:
		offers.append(_object([
			_field("choice_id", _quote(offer.choice_id)),
			_field("reward_kind", _quote(["unit", "item", "relic", "gold", "event"][offer.reward_kind])),
			_field("content_id", _quote(String(offer.content_id.value)) if offer.content_id != null else "null"),
			_field("amount", str(offer.amount)),
			_field("reservation_owner_key", _encode_reservation_key(offer.reservation_owner_key) if offer.reservation_owner_key != null else "null"),
			_field("payload_digest", _quote(offer.payload_digest)),
		]))
	var reserved_values: Array[String] = []
	for reserved: ReservedCopyState in pending.reserved_copies:
		reserved_values.append(_object([
			_field("unit_def_id", _quote(String(reserved.unit_def_id))),
			_field("copies", str(reserved.copies)),
			_field("reservation_owner_key", _encode_reservation_key(reserved.reservation_owner_key)),
		]))
	return _object([
		_field("node_id", _quote(pending.node_id)),
		_field("stage_id", _quote(["standard", "relic", "event_grant"][pending.stage_id])),
		_field("phase", _quote(["choosing", "unit_resolution", "item_resolution", "relic_resolution", "ready_to_advance"][pending.phase])),
		_field("offers", _array(offers)),
		_field("reserved_copies", _array(reserved_values)),
		_field("selected_choice_id", _optional_string(pending.selected_choice_id)),
		_field("selected_unit_reservation", _encode_reservation_key(pending.selected_unit_reservation) if pending.selected_unit_reservation != null else "null"),
		_field("transaction_id", _encode_transaction_key(pending.transaction_id)),
	])

func _encode_preview(preview: EncounterPreviewSnapshot, schema_version: int = 2) -> String:
	var units: Array[String] = []
	for unit: UnitBattleSnapshot in preview.enemy_units:
		units.append(_encode_unit_battle(unit, schema_version))
	var traits: Array[String] = []
	for trait_snapshot: TraitBattleSnapshot in preview.active_traits:
		traits.append(_encode_trait_battle(trait_snapshot, schema_version))
	var effects: Array[String] = []
	for effect: BattleEffectSnapshot in preview.affix_effects:
		effects.append(_encode_battle_effect(effect, schema_version))
	var phases: Array[String] = []
	for phase: BossPhaseSnapshot in preview.boss_phases:
		var phase_fields: Array[String] = [
			_field("phase_index", str(phase.phase_index)),
			_field("hp_threshold_bps", str(phase.hp_threshold_bps)),
		]
		if schema_version == 2:
			phase_fields.append(_field("source_instance_id", _quote(String(phase.source_instance_id))))
		phase_fields.append(_field("effect_ids", _name_array(phase.effect_ids)))
		phases.append(_object(phase_fields))
	return _object([
		_field("preview_schema_version", str(preview.preview_schema_version)),
		_field("encounter_id", _quote(String(preview.encounter_id))),
		_field("manifest_digest", _quote(String(preview.manifest_digest))),
		_field("enemy_units", _array(units)),
		_field("active_traits", _array(traits)),
		_field("affix_effects", _array(effects)),
		_field("boss_phases", _array(phases)),
	])

func _encode_unit_battle(unit: UnitBattleSnapshot, schema_version: int = 2) -> String:
	var fields: Array[String] = [
		_field("instance_id", _quote(String(unit.instance_id))),
		_field("unit_id", _quote(String(unit.unit_id))),
		_field("side", _quote(String(unit.side))),
		_field("logical_y", str(unit.logical_y)),
		_field("logical_x", str(unit.logical_x)),
		_field("star", str(unit.star)),
		_field("health", str(unit.health)),
		_field("attack", str(unit.attack)),
		_field("armor", str(unit.armor)),
		_field("magic_resist", str(unit.magic_resist)),
		_field("attack_speed_milli", str(unit.attack_speed_milli)),
		_field("attack_range_cells", str(unit.attack_range_cells)),
		_field("start_mana", str(unit.start_mana)),
		_field("max_mana", str(unit.max_mana)),
		_field("move_speed_milli", str(unit.move_speed_milli)),
		_field("ability_id", _quote(String(unit.ability_id.value)) if unit.ability_id != null else "null"),
		_field("effect_ids", _name_array(unit.effect_ids)),
	]
	if schema_version == 2:
		fields.insert(fields.size() - 2, _field(
			"basic_attack_profile", _quote(String(unit.basic_attack_profile))
		))
		var assignments: Array[String] = []
		for assignment: BattleEffectSnapshot in unit.effect_assignments:
			assignments.append(_encode_battle_effect(assignment, 2))
		fields.append(_field("effect_assignments", _array(assignments)))
	return _object(fields)

func _encode_trait_battle(trait_snapshot: TraitBattleSnapshot, schema_version: int = 2) -> String:
	var fields: Array[String] = [
		_field("trait_id", _quote(String(trait_snapshot.trait_id))),
		_field("tier", str(trait_snapshot.tier)),
		_field("member_instance_ids", _name_array(trait_snapshot.member_instance_ids)),
	]
	if schema_version == 2:
		var assignments: Array[String] = []
		for assignment: BattleEffectSnapshot in trait_snapshot.effect_assignments:
			assignments.append(_encode_battle_effect(assignment, 2))
		fields.append(_field("effect_assignments", _array(assignments)))
	return _object(fields)

func _encode_battle_effect(effect: BattleEffectSnapshot, schema_version: int = 2) -> String:
	var ints: Array[String] = []
	for parameter: BattleIntParam in effect.integer_params:
		ints.append(_object([
			_field("key", _quote(String(parameter.key))),
			_field("value", str(parameter.value)),
		]))
	var ids: Array[String] = []
	for parameter: BattleIdParam in effect.id_params:
		ids.append(_object([
			_field("key", _quote(String(parameter.key))),
			_field("value", _quote(String(parameter.value))),
		]))
	var fields: Array[String] = [
		_field("priority", str(effect.priority)),
	]
	if schema_version == 2:
		fields.append(_field("source_category", _quote(String(effect.source_category))))
		fields.append(_field("source_side", _quote(String(effect.source_side))))
	fields.append(_field("source_stable_id", _quote(String(effect.source_stable_id))))
	fields.append(_field("source_instance_id", _quote(String(effect.source_instance_id.value)) if effect.source_instance_id != null else "null"))
	if schema_version == 2:
		fields.append(_field("source_slot", str(effect.source_slot)))
	fields.append_array([
		_field("effect_index", str(effect.effect_index)),
		_field("effect_id", _quote(String(effect.effect_id))),
		_field("target_ids", _name_array(effect.target_ids)),
		_field("integer_params", _array(ints)),
		_field("id_params", _array(ids)),
	])
	return _object(fields)

func _field(key: String, encoded_value: String) -> String:
	return _quote(key) + ":" + encoded_value

func _object(fields: Array[String]) -> String:
	return "{" + ",".join(fields) + "}"

func _array(values: Array[String]) -> String:
	return "[" + ",".join(values) + "]"

func _quote(value: String) -> String:
	return JSON.stringify(value)

func _optional_string(value: OptionalStringValue) -> String:
	return _quote(value.value) if value != null else "null"

func _string_array(values: Array[String]) -> String:
	var output: Array[String] = []
	for value: String in values:
		output.append(_quote(value))
	return _array(output)

func _name_array(values: Array[StringName]) -> String:
	var output: Array[String] = []
	for value: StringName in values:
		output.append(_quote(String(value)))
	return _array(output)

func _int_array(values: Array[int]) -> String:
	var output: Array[String] = []
	for value: int in values:
		output.append(str(value))
	return _array(output)

func _sha256(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	context.update(bytes)
	return context.finish().hex_encode()

func _decode_root(data: Dictionary) -> SaveDecodeResult:
	_decode_error_path = &""
	_run_incompatible_content_ids.clear()
	_migration_diagnostics.clear()
	_active_receipt_ids.clear()
	if not _exact_keys(data, [
		"schema_version", "content_version", "app_version", "rng_version",
		"hash_version", "saved_at_utc", "profile", "run"
	], &"root"):
		return _current_decode_failure()
	var schema_version := _read_int(data, "schema_version", &"schema_version")
	var content_version := _read_string(data, "content_version", &"content_version")
	var app_version := _read_string(data, "app_version", &"app_version")
	var rng_version := _read_int(data, "rng_version", &"rng_version")
	var hash_version := _read_int(data, "hash_version", &"hash_version")
	var saved_at_utc := _read_string(data, "saved_at_utc", &"saved_at_utc")
	var profile := _decode_profile(data["profile"])
	if not _decode_error_path.is_empty() or profile == null:
		return _current_decode_failure()
	if data["run"] == null:
		var root := SaveRoot.new(
			schema_version, content_version, app_version, rng_version, hash_version,
			saved_at_utc, profile, null
		)
		var validation := _validator.validate_root(root)
		if not validation.ok:
			return _decode_failure(validation.error.field_path)
		return SaveDecodeResult.success(root, LoadResult.RunStatus.NONE)
	if not data["run"] is Dictionary:
		return _decode_failure(&"run")
	var run_data: Dictionary = data["run"]
	var probe := _inspect_run_content_snapshot(run_data)
	if probe == null:
		return _current_decode_failure()
	if _receipt_port == null:
		return _decode_failure(&"run.content_snapshot.receipt_port")
	var receipt_result := _receipt_port.compile_or_lookup(probe)
	if not receipt_result.ok:
		var diagnostic := LoadDiagnostic.new(
			receipt_result.error.code,
			receipt_result.error.field_path,
			receipt_result.error.diagnostic_values
		)
		return SaveDecodeResult.incompatible(profile, [], [diagnostic])
	if not _receipt_matches_probe(receipt_result.receipt, probe):
		var mismatch := LoadDiagnostic.new(
			PinnedCatalogReceiptError.MANIFEST_MISMATCH,
			&"run.content_snapshot"
		)
		return SaveDecodeResult.incompatible(profile, [], [mismatch])
	var run := _decode_run(run_data, receipt_result.receipt)
	if not _decode_error_path.is_empty() or run == null:
		return _current_decode_failure()
	if not _run_incompatible_content_ids.is_empty():
		_run_incompatible_content_ids.sort_custom(func(left: StringName, right: StringName) -> bool:
			return String(left) < String(right)
		)
		return SaveDecodeResult.incompatible(
			profile, _run_incompatible_content_ids, _migration_diagnostics
		)
	var root := SaveRoot.new(
		schema_version, content_version, app_version, rng_version, hash_version,
		saved_at_utc, profile, run
	)
	var validation := _validator.validate_root(root)
	if not validation.ok:
		return _decode_failure(validation.error.field_path)
	return SaveDecodeResult.success(root)

func _decode_profile(value: Variant) -> ProfileState:
	var data := _read_object(value, &"profile")
	if data == null or not _exact_keys(data, [
		"profile_id", "next_run_serial", "meta_currency", "unlocked_content_ids",
		"discovered_content_ids", "highest_challenge_level", "settlement_receipts", "settings_ref",
		"last_selection", "commander_challenge_records"
	], &"profile"):
		return null
	var unlocked := _migrate_profile_names(
		_read_name_array(data["unlocked_content_ids"], &"profile.unlocked_content_ids"),
		&"profile.unlocked_content_ids"
	)
	var discovered := _migrate_profile_names(
		_read_name_array(data["discovered_content_ids"], &"profile.discovered_content_ids"),
		&"profile.discovered_content_ids"
	)
	var receipts: Array[SettlementReceiptState] = []
	var receipt_values := _read_array(data["settlement_receipts"], &"profile.settlement_receipts")
	if receipt_values == null:
		return null
	for index: int in range(receipt_values.size()):
		var receipt := _decode_settlement_receipt(receipt_values[index], StringName("profile.settlement_receipts.%d" % index))
		if receipt == null:
			return null
		receipts.append(receipt)
	var next_serial := _read_u64(data["next_run_serial"], &"profile.next_run_serial")
	if next_serial == null:
		return null
	var last_selection: ProfileLastSelectionState = null
	if data["last_selection"] != null:
		last_selection = _decode_last_selection(data["last_selection"], &"profile.last_selection")
		if last_selection == null:
			return null
	var record_values := _read_array(data["commander_challenge_records"], &"profile.commander_challenge_records")
	if record_values == null:
		return null
	var records: Array[CommanderChallengeRecordState] = []
	for index: int in range(record_values.size()):
		var record := _decode_commander_challenge_record(
			record_values[index], StringName("profile.commander_challenge_records.%d" % index)
		)
		if record == null:
			return null
		records.append(record)
	return ProfileState.new(
		_read_string(data, "profile_id", &"profile.profile_id"),
		next_serial,
		_read_int(data, "meta_currency", &"profile.meta_currency"),
		unlocked,
		discovered,
		_read_int(data, "highest_challenge_level", &"profile.highest_challenge_level"),
		receipts,
		StringName(_read_string(data, "settings_ref", &"profile.settings_ref")),
		last_selection,
		records
	)

func _decode_last_selection(value: Variant, path: StringName) -> ProfileLastSelectionState:
	var data := _read_object(value, path)
	if data == null or not _exact_keys(data, ["commander_id", "challenge_level"], path):
		return null
	return ProfileLastSelectionState.new(
		StringName(_read_string(data, "commander_id", StringName(String(path) + ".commander_id"))),
		_read_int(data, "challenge_level", StringName(String(path) + ".challenge_level"))
	)

func _decode_commander_challenge_record(value: Variant, path: StringName) -> CommanderChallengeRecordState:
	var data := _read_object(value, path)
	if data == null or not _exact_keys(data, ["commander_id", "highest_cleared_level"], path):
		return null
	return CommanderChallengeRecordState.new(
		StringName(_read_string(data, "commander_id", StringName(String(path) + ".commander_id"))),
		_read_int(data, "highest_cleared_level", StringName(String(path) + ".highest_cleared_level"))
	)

func _decode_settlement_receipt(value: Variant, path: StringName) -> SettlementReceiptState:
	var data := _read_object(value, path)
	if data == null or not _exact_keys(data, ["key", "outcome", "currency_delta", "payload_digest"], path):
		return null
	var key := _decode_settlement_key(data["key"], StringName(String(path) + ".key"))
	var outcome_text := _read_string(data, "outcome", StringName(String(path) + ".outcome"))
	var outcome := _enum_index(outcome_text, ["completed", "failed", "abandoned"], StringName(String(path) + ".outcome"))
	if key == null or outcome < 0:
		return null
	return SettlementReceiptState.new(
		key, outcome,
		_read_int(data, "currency_delta", StringName(String(path) + ".currency_delta")),
		_read_string(data, "payload_digest", StringName(String(path) + ".payload_digest"))
	)

func _inspect_run_content_snapshot(run_data: Dictionary) -> ContentSnapshotProbe:
	if not run_data.has("content_snapshot"):
		_set_decode_error(&"run.content_snapshot")
		return null
	var value: Variant = run_data["content_snapshot"]
	var data := _read_object(value, &"run.content_snapshot")
	if data == null or not _exact_keys(data, [
		"content_version", "enabled_content_ids", "economy_config_id", "reward_table_ids",
		"combat_config_id", "map_node_def_ids", "challenge_unlock_def_ids",
		"meta_reward_table_id", "manifest_digest"
	], &"run.content_snapshot"):
		return null
	return ContentSnapshotProbe.new(
		_read_string(data, "content_version", &"run.content_snapshot.content_version"),
		_read_name_array(data["enabled_content_ids"], &"run.content_snapshot.enabled_content_ids"),
		StringName(_read_string(data, "economy_config_id", &"run.content_snapshot.economy_config_id")),
		StringName(_read_string(data, "combat_config_id", &"run.content_snapshot.combat_config_id")),
		_read_name_array(data["reward_table_ids"], &"run.content_snapshot.reward_table_ids"),
		_read_name_array(data["map_node_def_ids"], &"run.content_snapshot.map_node_def_ids"),
		_read_name_array(data["challenge_unlock_def_ids"], &"run.content_snapshot.challenge_unlock_def_ids"),
		StringName(_read_string(data, "meta_reward_table_id", &"run.content_snapshot.meta_reward_table_id")),
		_read_string(data, "manifest_digest", &"run.content_snapshot.manifest_digest")
	)

func _receipt_matches_probe(receipt: PinnedCatalogBuildReceipt, probe: ContentSnapshotProbe) -> bool:
	if receipt == null or receipt.content_version != probe.content_version:
		return false
	var exact := receipt.manifest_digest == probe.manifest_digest \
		and receipt.economy_config_id == probe.economy_config_id \
		and receipt.combat_config_id == probe.combat_config_id \
		and receipt.meta_reward_table_id == probe.meta_reward_table_id \
		and _same_names(receipt.active_entry_ids, probe.enabled_content_ids) \
		and _same_names(receipt.reward_table_ids, probe.reward_table_ids) \
		and _same_names(receipt.map_node_def_ids, probe.map_node_def_ids) \
		and _same_names(receipt.challenge_unlock_def_ids, probe.challenge_unlock_def_ids)
	if exact:
		return true
	var mapped_active := _migrate_comparison_names(probe.enabled_content_ids)
	var mapped_rewards := _migrate_comparison_names(probe.reward_table_ids)
	var mapped_nodes := _migrate_comparison_names(probe.map_node_def_ids)
	var mapped_challenges := _migrate_comparison_names(probe.challenge_unlock_def_ids)
	var mapped_economy := _migrate_comparison_id(probe.economy_config_id)
	var mapped_combat := _migrate_comparison_id(probe.combat_config_id)
	var mapped_meta := _migrate_comparison_id(probe.meta_reward_table_id)
	var changed := not _same_names(mapped_active, probe.enabled_content_ids) \
		or mapped_economy != probe.economy_config_id \
		or mapped_combat != probe.combat_config_id \
		or mapped_meta != probe.meta_reward_table_id \
		or not _same_names(mapped_rewards, probe.reward_table_ids) \
		or not _same_names(mapped_nodes, probe.map_node_def_ids) \
		or not _same_names(mapped_challenges, probe.challenge_unlock_def_ids)
	return changed and receipt.economy_config_id == mapped_economy \
		and receipt.combat_config_id == mapped_combat \
		and receipt.meta_reward_table_id == mapped_meta \
		and _same_names(receipt.active_entry_ids, mapped_active) \
		and _same_names(receipt.reward_table_ids, mapped_rewards) \
		and _same_names(receipt.map_node_def_ids, mapped_nodes) \
		and _same_names(receipt.challenge_unlock_def_ids, mapped_challenges)

func _decode_run_key(value: Variant, path: StringName) -> RunKeyState:
	var data := _read_object(value, path)
	if data == null or not _exact_keys(data, ["kind", "profile_id", "next_run_serial", "digest"], path):
		return null
	if _read_string(data, "kind", StringName(String(path) + ".kind")) != "run":
		_set_decode_error(StringName(String(path) + ".kind"))
		return null
	var serial := _read_u64(data["next_run_serial"], StringName(String(path) + ".next_run_serial"))
	if serial == null:
		return null
	var built := RuntimeKeySchemaRegistry.new().build_run(
		_read_string(data, "profile_id", StringName(String(path) + ".profile_id")), serial
	)
	return _verified_key(built, _read_string(data, "digest", StringName(String(path) + ".digest")), path) as RunKeyState

func _decode_node_key(value: Variant, path: StringName) -> NodeKeyState:
	var data := _read_object(value, path)
	if data == null or not _exact_keys(data, [
		"kind", "run_id", "act_index", "node_kind", "layer_index", "slot_index", "digest"
	], path):
		return null
	if _read_string(data, "kind", StringName(String(path) + ".kind")) != "node":
		_set_decode_error(StringName(String(path) + ".kind"))
		return null
	var built := RuntimeKeySchemaRegistry.new().build_node(
		StringName(_read_string(data, "run_id", StringName(String(path) + ".run_id"))),
		_read_int(data, "act_index", StringName(String(path) + ".act_index")),
		StringName(_read_string(data, "node_kind", StringName(String(path) + ".node_kind"))),
		_read_int(data, "layer_index", StringName(String(path) + ".layer_index")),
		_read_int(data, "slot_index", StringName(String(path) + ".slot_index"))
	)
	return _verified_key(built, _read_string(data, "digest", StringName(String(path) + ".digest")), path) as NodeKeyState

func _decode_reservation_key(value: Variant, path: StringName) -> ReservationOwnerKeyState:
	var data := _read_object(value, path)
	if data == null or not _exact_keys(data, [
		"kind", "run_id", "node_id", "source_kind", "stage_or_refresh_id", "slot_index", "digest"
	], path):
		return null
	if _read_string(data, "kind", StringName(String(path) + ".kind")) != "reservation_owner":
		_set_decode_error(StringName(String(path) + ".kind"))
		return null
	var built := RuntimeKeySchemaRegistry.new().build_reservation_owner(
		StringName(_read_string(data, "run_id", StringName(String(path) + ".run_id"))),
		StringName(_read_string(data, "node_id", StringName(String(path) + ".node_id"))),
		StringName(_read_string(data, "source_kind", StringName(String(path) + ".source_kind"))),
		StringName(_read_string(data, "stage_or_refresh_id", StringName(String(path) + ".stage_or_refresh_id"))),
		_read_int(data, "slot_index", StringName(String(path) + ".slot_index"))
	)
	return _verified_key(built, _read_string(data, "digest", StringName(String(path) + ".digest")), path) as ReservationOwnerKeyState

func _decode_transaction_key(value: Variant, path: StringName) -> TransactionKeyState:
	var data := _read_object(value, path)
	if data == null or not _exact_keys(data, [
		"kind", "run_id", "node_id_or_camp", "command_kind", "next_transaction_serial", "digest"
	], path):
		return null
	if _read_string(data, "kind", StringName(String(path) + ".kind")) != "transaction":
		_set_decode_error(StringName(String(path) + ".kind"))
		return null
	var serial := _read_u64(data["next_transaction_serial"], StringName(String(path) + ".next_transaction_serial"))
	if serial == null:
		return null
	var built := RuntimeKeySchemaRegistry.new().build_transaction(
		StringName(_read_string(data, "run_id", StringName(String(path) + ".run_id"))),
		StringName(_read_string(data, "node_id_or_camp", StringName(String(path) + ".node_id_or_camp"))),
		StringName(_read_string(data, "command_kind", StringName(String(path) + ".command_kind"))),
		serial
	)
	return _verified_key(built, _read_string(data, "digest", StringName(String(path) + ".digest")), path) as TransactionKeyState

func _decode_claim_key(value: Variant, path: StringName) -> EffectClaimKeyState:
	var data := _read_object(value, path)
	if data == null or not _exact_keys(data, [
		"kind", "run_id", "node_id", "claim_scope", "source_instance_or_slot",
		"effect_id", "operation_index", "digest"
	], path):
		return null
	if _read_string(data, "kind", StringName(String(path) + ".kind")) != "effect_claim":
		_set_decode_error(StringName(String(path) + ".kind"))
		return null
	var built := RuntimeKeySchemaRegistry.new().build_effect_claim(
		StringName(_read_string(data, "run_id", StringName(String(path) + ".run_id"))),
		StringName(_read_string(data, "node_id", StringName(String(path) + ".node_id"))),
		StringName(_read_string(data, "claim_scope", StringName(String(path) + ".claim_scope"))),
		StringName(_read_string(data, "source_instance_or_slot", StringName(String(path) + ".source_instance_or_slot"))),
		StringName(_read_string(data, "effect_id", StringName(String(path) + ".effect_id"))),
		_read_int(data, "operation_index", StringName(String(path) + ".operation_index"))
	)
	return _verified_key(built, _read_string(data, "digest", StringName(String(path) + ".digest")), path) as EffectClaimKeyState

func _decode_settlement_key(value: Variant, path: StringName) -> SettlementReceiptKeyState:
	var data := _read_object(value, path)
	if data == null or not _exact_keys(data, ["kind", "run_id", "digest"], path):
		return null
	if _read_string(data, "kind", StringName(String(path) + ".kind")) != "settlement_receipt":
		_set_decode_error(StringName(String(path) + ".kind"))
		return null
	var built := RuntimeKeySchemaRegistry.new().build_settlement_receipt(
		StringName(_read_string(data, "run_id", StringName(String(path) + ".run_id")))
	)
	return _verified_key(built, _read_string(data, "digest", StringName(String(path) + ".digest")), path) as SettlementReceiptKeyState

func _verified_key(built: RuntimeKeyEncodeResult, persisted_digest: String, path: StringName) -> RuntimeKeyState:
	if built == null or not built.ok or String(built.key_state.digest) != persisted_digest:
		_set_decode_error(StringName(String(path) + ".digest"))
		return null
	return built.key_state

func _decode_run(data: Dictionary, receipt: PinnedCatalogBuildReceipt) -> RunState:
	if not _exact_keys(data, [
		"run_id", "run_key", "run_seed", "content_snapshot", "next_transaction_serial",
		"next_unit_serial", "next_item_serial", "commander_id", "challenge_level", "act_index",
		"map_state", "current_node_id", "run_phase", "expedition_hp", "economy_state",
		"unit_pool_state", "roster_state", "cleared_normal_count", "cleared_elite_count",
		"defeated_boss_count", "rng_stream_states", "income_claimed_node_ids",
		"loss_stipend_claimed_act_ids", "reservation_owners", "transaction_receipts",
		"claim_receipts", "resolution_state", "discovered_content_ids"
	], &"run"):
		return null
	_active_receipt_ids.assign(receipt.active_entry_ids)
	var key := _decode_run_key(data["run_key"], &"run.run_key")
	var seed := _read_u64(data["run_seed"], &"run.run_seed")
	var transaction_serial := _read_u64(data["next_transaction_serial"], &"run.next_transaction_serial")
	var unit_serial := _read_u64(data["next_unit_serial"], &"run.next_unit_serial")
	var item_serial := _read_u64(data["next_item_serial"], &"run.next_item_serial")
	var map := _decode_map(data["map_state"])
	var economy := _decode_economy(data["economy_state"])
	var pool := _decode_pool(data["unit_pool_state"])
	var roster := _decode_roster(data["roster_state"])
	var resolution := _decode_resolution(data["resolution_state"])
	var phase_text := _read_string(data, "run_phase", &"run.run_phase")
	var phase := _enum_index(phase_text, ["MAP", "PREPARE", "COMBAT", "REWARD", "RESULTS"], &"run.run_phase")
	var rng_states := _decode_named_rng_array(data["rng_stream_states"], &"run.rng_stream_states")
	var owners := _decode_reservation_owners(data["reservation_owners"])
	var transactions := _decode_transaction_receipts(data["transaction_receipts"])
	var claims := _decode_claim_receipts(data["claim_receipts"])
	if not _decode_error_path.is_empty() or key == null or seed == null or transaction_serial == null \
		or unit_serial == null or item_serial == null or map == null or economy == null \
		or pool == null or roster == null or resolution == null or phase < 0:
		return null
	var snapshot_result := ContentSnapshotState.from_pinned_receipt(receipt)
	if not snapshot_result.ok:
		_set_decode_error(StringName("run.%s" % snapshot_result.error.field_path))
		return null
	var snapshot := snapshot_result.snapshot
	return RunState.new(
		_read_string(data, "run_id", &"run.run_id"), key, seed, snapshot,
		transaction_serial, unit_serial, item_serial,
		_migrate_required_id(
			StringName(_read_string(data, "commander_id", &"run.commander_id")),
			&"commander", &"run.commander_id"
		),
		_read_int(data, "challenge_level", &"run.challenge_level"),
		_read_int(data, "act_index", &"run.act_index"),
		map, _read_optional_string(data["current_node_id"], &"run.current_node_id"),
		phase, _read_int(data, "expedition_hp", &"run.expedition_hp"),
		economy, pool, roster,
		_read_int(data, "cleared_normal_count", &"run.cleared_normal_count"),
		_read_int(data, "cleared_elite_count", &"run.cleared_elite_count"),
		_read_int(data, "defeated_boss_count", &"run.defeated_boss_count"),
		rng_states,
		_read_string_array(data["income_claimed_node_ids"], &"run.income_claimed_node_ids"),
		_read_int_array(data["loss_stipend_claimed_act_ids"], &"run.loss_stipend_claimed_act_ids"),
		owners, transactions, claims, resolution,
		_read_name_array(data["discovered_content_ids"], &"run.discovered_content_ids")
	)

func _decode_map(value: Variant) -> MapState:
	var data := _read_object(value, &"run.map_state")
	if data == null or not _exact_keys(data, ["nodes", "edges", "current_node_id", "completed_node_ids"], &"run.map_state"):
		return null
	var node_values := _read_array(data["nodes"], &"run.map_state.nodes")
	var nodes: Array[MapNodeState] = []
	for index: int in range(node_values.size()):
		var node := _decode_map_node(node_values[index], StringName("run.map_state.nodes.%d" % index))
		if node == null:
			return null
		nodes.append(node)
	var edge_values := _read_array(data["edges"], &"run.map_state.edges")
	var edges: Array[MapEdgeState] = []
	for index: int in range(edge_values.size()):
		var path := StringName("run.map_state.edges.%d" % index)
		var edge_data := _read_object(edge_values[index], path)
		if edge_data == null or not _exact_keys(edge_data, ["from_node_id", "to_node_id"], path):
			return null
		edges.append(MapEdgeState.new(
			_read_string(edge_data, "from_node_id", StringName(String(path) + ".from_node_id")),
			_read_string(edge_data, "to_node_id", StringName(String(path) + ".to_node_id"))
		))
	return MapState.new(
		nodes, edges, _read_optional_string(data["current_node_id"], &"run.map_state.current_node_id"),
		_read_string_array(data["completed_node_ids"], &"run.map_state.completed_node_ids")
	)

func _decode_map_node(value: Variant, path: StringName) -> MapNodeState:
	var data := _read_object(value, path)
	if data == null or not _exact_keys(data, [
		"node_id", "node_key", "def_id", "act_index", "layer_index", "slot_index",
		"node_kind", "generated_payload_digest", "encounter_preview", "completed"
	], path):
		return null
	var key := _decode_node_key(data["node_key"], StringName(String(path) + ".node_key"))
	var kind_text := _read_string(data, "node_kind", StringName(String(path) + ".node_kind"))
	var kind := _enum_index(kind_text, ["normal", "elite", "merchant", "event", "rest", "treasure", "boss"], StringName(String(path) + ".node_kind"))
	var preview: EncounterPreviewSnapshot = null
	if data["encounter_preview"] != null:
		preview = _decode_preview(data["encounter_preview"], StringName(String(path) + ".encounter_preview"))
	if key == null or kind < 0:
		return null
	return MapNodeState.new(
		_read_string(data, "node_id", StringName(String(path) + ".node_id")), key,
		StringName(_read_string(data, "def_id", StringName(String(path) + ".def_id"))),
		_read_int(data, "act_index", StringName(String(path) + ".act_index")),
		_read_int(data, "layer_index", StringName(String(path) + ".layer_index")),
		_read_int(data, "slot_index", StringName(String(path) + ".slot_index")),
		kind,
		_read_string(data, "generated_payload_digest", StringName(String(path) + ".generated_payload_digest")),
		preview,
		_read_bool(data, "completed", StringName(String(path) + ".completed"))
	)

func _decode_economy(value: Variant) -> EconomyState:
	var data := _read_object(value, &"run.economy_state")
	if data == null or not _exact_keys(data, [
		"gold", "level", "xp", "win_streak", "loss_streak", "shop_refresh_index", "shop_offers"
	], &"run.economy_state"):
		return null
	var values := _read_array(data["shop_offers"], &"run.economy_state.shop_offers")
	var offers: Array[ShopOffer] = []
	for index: int in range(values.size()):
		var path := StringName("run.economy_state.shop_offers.%d" % index)
		var offer_data := _read_object(values[index], path)
		if offer_data == null or not _exact_keys(offer_data, [
			"slot_index", "offer_id", "unit_def_id", "cost", "reserved_copies", "reservation_owner_key"
		], path):
			return null
		var key := _decode_reservation_key(offer_data["reservation_owner_key"], StringName(String(path) + ".reservation_owner_key"))
		if key == null:
			return null
		offers.append(ShopOffer.new(
			_read_int(offer_data, "slot_index", StringName(String(path) + ".slot_index")),
			_read_string(offer_data, "offer_id", StringName(String(path) + ".offer_id")),
			_migrate_required_id(
				StringName(_read_string(offer_data, "unit_def_id", StringName(String(path) + ".unit_def_id"))),
				&"unit", StringName(String(path) + ".unit_def_id")
			),
			_read_int(offer_data, "cost", StringName(String(path) + ".cost")),
			_read_int(offer_data, "reserved_copies", StringName(String(path) + ".reserved_copies")),
			key
		))
	return EconomyState.new(
		_read_int(data, "gold", &"run.economy_state.gold"),
		_read_int(data, "level", &"run.economy_state.level"),
		_read_int(data, "xp", &"run.economy_state.xp"),
		_read_int(data, "win_streak", &"run.economy_state.win_streak"),
		_read_int(data, "loss_streak", &"run.economy_state.loss_streak"),
		_read_int(data, "shop_refresh_index", &"run.economy_state.shop_refresh_index"),
		offers
	)

func _decode_pool(value: Variant) -> UnitPoolState:
	var data := _read_object(value, &"run.unit_pool_state")
	if data == null or not _exact_keys(data, ["entries"], &"run.unit_pool_state"):
		return null
	var values := _read_array(data["entries"], &"run.unit_pool_state.entries")
	var entries: Array[UnitPoolEntryState] = []
	for index: int in range(values.size()):
		var path := StringName("run.unit_pool_state.entries.%d" % index)
		var entry := _read_object(values[index], path)
		if entry == null or not _exact_keys(entry, [
			"unit_def_id", "total_copies", "remaining_copies", "reserved_copies", "held_copies"
		], path):
			return null
		entries.append(UnitPoolEntryState.new(
			_migrate_required_id(
				StringName(_read_string(entry, "unit_def_id", StringName(String(path) + ".unit_def_id"))),
				&"unit", StringName(String(path) + ".unit_def_id")
			),
			_read_int(entry, "total_copies", StringName(String(path) + ".total_copies")),
			_read_int(entry, "remaining_copies", StringName(String(path) + ".remaining_copies")),
			_read_int(entry, "reserved_copies", StringName(String(path) + ".reserved_copies")),
			_read_int(entry, "held_copies", StringName(String(path) + ".held_copies"))
		))
	return UnitPoolState.new(entries)

func _decode_roster(value: Variant) -> RosterState:
	var data := _read_object(value, &"run.roster_state")
	if data == null or not _exact_keys(data, [
		"board", "bench_unit_instance_ids", "unit_instances", "item_instances",
		"inventory_item_instance_ids", "pending_item_overflow", "active_relic_slots"
	], &"run.roster_state"):
		return null
	var board_data := _read_object(data["board"], &"run.roster_state.board")
	if board_data == null or not _exact_keys(board_data, ["placements"], &"run.roster_state.board"):
		return null
	var placement_values := _read_array(board_data["placements"], &"run.roster_state.board.placements")
	var placements: Array[BoardPlacementState] = []
	for index: int in range(placement_values.size()):
		var path := StringName("run.roster_state.board.placements.%d" % index)
		var placement := _read_object(placement_values[index], path)
		if placement == null or not _exact_keys(placement, ["logical_y", "logical_x", "unit_instance_id"], path):
			return null
		placements.append(BoardPlacementState.new(
			_read_int(placement, "logical_y", StringName(String(path) + ".logical_y")),
			_read_int(placement, "logical_x", StringName(String(path) + ".logical_x")),
			_read_string(placement, "unit_instance_id", StringName(String(path) + ".unit_instance_id"))
		))
	var unit_values := _read_array(data["unit_instances"], &"run.roster_state.unit_instances")
	var units: Array[UnitInstance] = []
	for index: int in range(unit_values.size()):
		var path := StringName("run.roster_state.unit_instances.%d" % index)
		var unit := _read_object(unit_values[index], path)
		if unit == null or not _exact_keys(unit, [
			"instance_id", "def_id", "star", "equipment_instance_ids", "acquired_serial"
		], path):
			return null
		var serial := _read_u64(unit["acquired_serial"], StringName(String(path) + ".acquired_serial"))
		if serial == null:
			return null
		units.append(UnitInstance.new(
			_read_string(unit, "instance_id", StringName(String(path) + ".instance_id")),
			_migrate_required_id(
				StringName(_read_string(unit, "def_id", StringName(String(path) + ".def_id"))),
				&"unit", StringName(String(path) + ".def_id")
			),
			_read_int(unit, "star", StringName(String(path) + ".star")),
			_read_string_array(unit["equipment_instance_ids"], StringName(String(path) + ".equipment_instance_ids")),
			serial
		))
	var item_values := _read_array(data["item_instances"], &"run.roster_state.item_instances")
	var items: Array[ItemInstanceState] = []
	for index: int in range(item_values.size()):
		var path := StringName("run.roster_state.item_instances.%d" % index)
		var item := _read_object(item_values[index], path)
		if item == null or not _exact_keys(item, [
			"instance_id", "def_id", "bound_unit_instance_id", "acquired_serial"
		], path):
			return null
		var serial := _read_u64(item["acquired_serial"], StringName(String(path) + ".acquired_serial"))
		if serial == null:
			return null
		items.append(ItemInstanceState.new(
			_read_string(item, "instance_id", StringName(String(path) + ".instance_id")),
			_migrate_required_id(
				StringName(_read_string(item, "def_id", StringName(String(path) + ".def_id"))),
				&"item", StringName(String(path) + ".def_id")
			),
			_read_optional_string(item["bound_unit_instance_id"], StringName(String(path) + ".bound_unit_instance_id")),
			serial
		))
	var relic_values := _read_array(data["active_relic_slots"], &"run.roster_state.active_relic_slots")
	var relics: Array[RelicSlotState] = []
	for index: int in range(relic_values.size()):
		var path := StringName("run.roster_state.active_relic_slots.%d" % index)
		var relic := _read_object(relic_values[index], path)
		if relic == null or not _exact_keys(relic, ["slot_index", "relic_id"], path):
			return null
		var relic_id: OptionalStringNameValue = null
		if relic["relic_id"] != null:
			relic_id = OptionalStringNameValue.new(_migrate_required_id(
				StringName(_read_variant_string(relic["relic_id"], StringName(String(path) + ".relic_id"))),
				&"relic", StringName(String(path) + ".relic_id")
			))
		relics.append(RelicSlotState.new(
			_read_int(relic, "slot_index", StringName(String(path) + ".slot_index")), relic_id
		))
	return RosterState.new(
		BoardState.new(placements),
		_read_string_array(data["bench_unit_instance_ids"], &"run.roster_state.bench_unit_instance_ids"),
		units, items,
		_read_string_array(data["inventory_item_instance_ids"], &"run.roster_state.inventory_item_instance_ids"),
		_read_string_array(data["pending_item_overflow"], &"run.roster_state.pending_item_overflow"),
		relics
	)

func _decode_named_rng_array(value: Variant, path: StringName) -> Array[NamedRngState]:
	var values := _read_array(value, path)
	var output: Array[NamedRngState] = []
	for index: int in range(values.size()):
		var entry_path := StringName("%s.%d" % [String(path), index])
		var data := _read_object(values[index], entry_path)
		if data == null or not _exact_keys(data, ["stream_name", "snapshot"], entry_path):
			return []
		var stream := _enum_index(
			_read_string(data, "stream_name", StringName(String(entry_path) + ".stream_name")),
			["map", "shop", "reward", "combat"],
			StringName(String(entry_path) + ".stream_name")
		)
		var snapshot := _decode_rng_snapshot(data["snapshot"], StringName(String(entry_path) + ".snapshot"))
		if stream < 0 or snapshot == null:
			return []
		output.append(NamedRngState.new(stream, snapshot))
	return output

func _decode_rng_snapshot(value: Variant, path: StringName) -> RngSnapshot:
	var data := _read_object(value, path)
	if data == null or not _exact_keys(data, ["rng_version", "state", "inc", "counter"], path):
		return null
	var state := _read_u64(data["state"], StringName(String(path) + ".state"))
	var increment := _read_u64(data["inc"], StringName(String(path) + ".inc"))
	var counter := _read_u64(data["counter"], StringName(String(path) + ".counter"))
	if state == null or increment == null or counter == null:
		return null
	var result := RngSnapshot.create(
		_read_int(data, "rng_version", StringName(String(path) + ".rng_version")),
		state, increment, counter
	)
	if not result.ok:
		_set_decode_error(path)
		return null
	return result.snapshot

func _decode_reservation_owners(value: Variant) -> Array[ReservationOwnerState]:
	var values := _read_array(value, &"run.reservation_owners")
	var output: Array[ReservationOwnerState] = []
	for index: int in range(values.size()):
		var path := StringName("run.reservation_owners.%d" % index)
		var data := _read_object(values[index], path)
		if data == null or not _exact_keys(data, [
			"key", "unit_def_id", "reserved_copies", "status", "payload_digest"
		], path):
			return []
		var key := _decode_reservation_key(data["key"], StringName(String(path) + ".key"))
		var status := _enum_index(
			_read_string(data, "status", StringName(String(path) + ".status")),
			["active", "consumed", "released"], StringName(String(path) + ".status")
		)
		if key == null or status < 0:
			return []
		output.append(ReservationOwnerState.new(
			key,
			_migrate_required_id(
				StringName(_read_string(data, "unit_def_id", StringName(String(path) + ".unit_def_id"))),
				&"unit", StringName(String(path) + ".unit_def_id")
			),
			_read_int(data, "reserved_copies", StringName(String(path) + ".reserved_copies")),
			status,
			_read_string(data, "payload_digest", StringName(String(path) + ".payload_digest"))
		))
	return output

func _decode_transaction_receipts(value: Variant) -> Array[TransactionReceiptState]:
	var values := _read_array(value, &"run.transaction_receipts")
	var output: Array[TransactionReceiptState] = []
	for index: int in range(values.size()):
		var path := StringName("run.transaction_receipts.%d" % index)
		var data := _read_object(values[index], path)
		if data == null or not _exact_keys(data, ["key", "payload_digest"], path):
			return []
		var key := _decode_transaction_key(data["key"], StringName(String(path) + ".key"))
		if key == null:
			return []
		output.append(TransactionReceiptState.new(
			key, _read_string(data, "payload_digest", StringName(String(path) + ".payload_digest"))
		))
	return output

func _decode_claim_receipts(value: Variant) -> Array[ClaimReceiptState]:
	var values := _read_array(value, &"run.claim_receipts")
	var output: Array[ClaimReceiptState] = []
	for index: int in range(values.size()):
		var path := StringName("run.claim_receipts.%d" % index)
		var data := _read_object(values[index], path)
		if data == null or not _exact_keys(data, ["key", "payload_digest"], path):
			return []
		var key := _decode_claim_key(data["key"], StringName(String(path) + ".key"))
		if key == null:
			return []
		output.append(ClaimReceiptState.new(
			key, _read_string(data, "payload_digest", StringName(String(path) + ".payload_digest"))
		))
	return output

func _decode_resolution(value: Variant) -> ResolutionState:
	var data := _read_object(value, &"run.resolution_state")
	if data == null or not data.has("kind") or not data["kind"] is String:
		_set_decode_error(&"run.resolution_state.kind")
		return null
	match String(data["kind"]):
		"idle":
			if not _exact_keys(data, ["kind"], &"run.resolution_state"):
				return null
			return IdleResolutionState.new()
		"combat_pending":
			if not _exact_keys(data, ["kind", "battle_setup"], &"run.resolution_state"):
				return null
			var setup := _decode_battle_setup(data["battle_setup"], &"run.resolution_state.battle_setup")
			return CombatPendingResolutionState.new(setup) if setup != null else null
		"battle_result_pending":
			if not _exact_keys(data, ["kind", "battle_setup_hash", "battle_result"], &"run.resolution_state"):
				return null
			var result := _decode_battle_result(data["battle_result"], &"run.resolution_state.battle_result")
			return BattleResultPendingResolutionState.new(
				_read_string(data, "battle_setup_hash", &"run.resolution_state.battle_setup_hash"), result
			) if result != null else null
		"reward_pending":
			if not _exact_keys(data, ["kind", "pending_reward"], &"run.resolution_state"):
				return null
			var pending := _decode_pending_reward(data["pending_reward"])
			return RewardPendingResolutionState.new(pending) if pending != null else null
		_:
			_set_decode_error(&"run.resolution_state.kind")
			return null

func _decode_pending_reward(value: Variant) -> PendingRewardState:
	var data := _read_object(value, &"run.resolution_state.pending_reward")
	if data == null or not _exact_keys(data, [
		"node_id", "stage_id", "phase", "offers", "reserved_copies", "selected_choice_id",
		"selected_unit_reservation", "transaction_id"
	], &"run.resolution_state.pending_reward"):
		return null
	var stage := _enum_index(
		_read_string(data, "stage_id", &"run.resolution_state.pending_reward.stage_id"),
		["standard", "relic", "event_grant"], &"run.resolution_state.pending_reward.stage_id"
	)
	var phase := _enum_index(
		_read_string(data, "phase", &"run.resolution_state.pending_reward.phase"),
		["choosing", "unit_resolution", "item_resolution", "relic_resolution", "ready_to_advance"],
		&"run.resolution_state.pending_reward.phase"
	)
	var offer_values := _read_array(data["offers"], &"run.resolution_state.pending_reward.offers")
	var offers: Array[RewardOfferState] = []
	for index: int in range(offer_values.size()):
		var path := StringName("run.resolution_state.pending_reward.offers.%d" % index)
		var offer := _read_object(offer_values[index], path)
		if offer == null or not _exact_keys(offer, [
			"choice_id", "reward_kind", "content_id", "amount", "reservation_owner_key", "payload_digest"
		], path):
			return null
		var kind := _enum_index(
			_read_string(offer, "reward_kind", StringName(String(path) + ".reward_kind")),
			["unit", "item", "relic", "gold", "event"], StringName(String(path) + ".reward_kind")
		)
		var content_id: OptionalStringNameValue = null
		if offer["content_id"] != null:
			content_id = OptionalStringNameValue.new(_migrate_required_id(
				StringName(_read_variant_string(offer["content_id"], StringName(String(path) + ".content_id"))),
				&"", StringName(String(path) + ".content_id")
			))
		var reservation_key: ReservationOwnerKeyState = null
		if offer["reservation_owner_key"] != null:
			reservation_key = _decode_reservation_key(offer["reservation_owner_key"], StringName(String(path) + ".reservation_owner_key"))
		if kind < 0:
			return null
		offers.append(RewardOfferState.new(
			_read_string(offer, "choice_id", StringName(String(path) + ".choice_id")), kind,
			content_id, _read_int(offer, "amount", StringName(String(path) + ".amount")),
			reservation_key,
			_read_string(offer, "payload_digest", StringName(String(path) + ".payload_digest"))
		))
	var reserved_values := _read_array(data["reserved_copies"], &"run.resolution_state.pending_reward.reserved_copies")
	var reserved: Array[ReservedCopyState] = []
	for index: int in range(reserved_values.size()):
		var path := StringName("run.resolution_state.pending_reward.reserved_copies.%d" % index)
		var item := _read_object(reserved_values[index], path)
		if item == null or not _exact_keys(item, ["unit_def_id", "copies", "reservation_owner_key"], path):
			return null
		var key := _decode_reservation_key(item["reservation_owner_key"], StringName(String(path) + ".reservation_owner_key"))
		if key == null:
			return null
		reserved.append(ReservedCopyState.new(
			_migrate_required_id(
				StringName(_read_string(item, "unit_def_id", StringName(String(path) + ".unit_def_id"))),
				&"unit", StringName(String(path) + ".unit_def_id")
			),
			_read_int(item, "copies", StringName(String(path) + ".copies")), key
		))
	var selected_reservation: ReservationOwnerKeyState = null
	if data["selected_unit_reservation"] != null:
		selected_reservation = _decode_reservation_key(
			data["selected_unit_reservation"], &"run.resolution_state.pending_reward.selected_unit_reservation"
		)
	var transaction := _decode_transaction_key(
		data["transaction_id"], &"run.resolution_state.pending_reward.transaction_id"
	)
	if stage < 0 or phase < 0 or transaction == null:
		return null
	return PendingRewardState.new(
		_read_string(data, "node_id", &"run.resolution_state.pending_reward.node_id"),
		stage, phase, offers, reserved,
		_read_optional_string(data["selected_choice_id"], &"run.resolution_state.pending_reward.selected_choice_id"),
		selected_reservation, transaction
	)

func _decode_battle_setup(value: Variant, path: StringName) -> BattleSetup:
	var data := _read_object(value, path)
	if data == null or not _exact_keys(data, [
		"inputs", "hash_version", "battle_setup_hash", "rng_version", "combat_rng_snapshot",
		"battle_setup_envelope_digest"
	], path):
		return null
	if not data["inputs"] is Dictionary:
		_set_decode_error(StringName(String(path) + ".inputs"))
		return null
	var input_data: Dictionary = data["inputs"]
	var setup_schema_version := _read_int(
		input_data,
		"setup_schema_version",
		StringName(String(path) + ".inputs.setup_schema_version")
	)
	if setup_schema_version not in [1, 2]:
		_set_decode_error(StringName(String(path) + ".inputs.setup_schema_version"))
		return null
	var input_text := _canonicalize_variant(data["inputs"])
	var codec: CanonicalBattleCodecV1 = (
		CanonicalBattleCodecV2.new()
		if setup_schema_version == 2
		else CanonicalBattleCodecV1.new()
	)
	var codec_result: BattleCodecResult = codec.decode(input_text.to_utf8_buffer())
	if not codec_result.ok or codec_result.inputs == null:
		_set_decode_error(StringName(String(path) + ".inputs"))
		return null
	var snapshot := _decode_rng_snapshot(data["combat_rng_snapshot"], StringName(String(path) + ".combat_rng_snapshot"))
	if snapshot == null:
		return null
	var setup := BattleSetup.new()
	setup.inputs = codec_result.inputs.deep_clone()
	setup.hash_version = _read_int(data, "hash_version", StringName(String(path) + ".hash_version"))
	setup.battle_setup_hash = StringName(_read_string(data, "battle_setup_hash", StringName(String(path) + ".battle_setup_hash")))
	setup.rng_version = _read_int(data, "rng_version", StringName(String(path) + ".rng_version"))
	setup.combat_rng_snapshot = snapshot
	setup.battle_setup_envelope_digest = StringName(_read_string(
		data,
		"battle_setup_envelope_digest",
		StringName(String(path) + ".battle_setup_envelope_digest")
	))
	var encoded: BattleCodecResult = codec.encode(setup.inputs)
	if not encoded.ok or BattleSetupHashBuilder.sha256_hex(encoded.canonical_bytes) != String(setup.battle_setup_hash):
		_set_decode_error(StringName(String(path) + ".battle_setup_hash"))
		return null
	if setup_schema_version == 2:
		var expected_envelope := BattleSetupHashBuilder.envelope_digest(
			setup.hash_version,
			String(setup.battle_setup_hash),
			setup.rng_version,
			setup.combat_rng_snapshot
		)
		if expected_envelope.is_empty() \
			or expected_envelope != String(setup.battle_setup_envelope_digest):
			_set_decode_error(StringName(String(path) + ".battle_setup_envelope_digest"))
			return null
	elif not setup.battle_setup_envelope_digest.is_empty():
		_set_decode_error(StringName(String(path) + ".battle_setup_envelope_digest"))
		return null
	return setup

func _decode_battle_result(value: Variant, path: StringName) -> BattleResult:
	var data := _read_object(value, path)
	if data == null:
		return null
	var decoded := BattleResultCodecV1.new().decode(
		_canonicalize_variant(data).to_utf8_buffer()
	)
	if not decoded.ok or decoded.record == null:
		_set_decode_error(StringName(
			"%s.%s" % [
				String(path),
				String(decoded.error.field_path) if decoded.error != null else "result",
			]
		))
		return null
	return BattleResult.from_record(decoded.record)

func _decode_preview(value: Variant, path: StringName) -> EncounterPreviewSnapshot:
	var data := _read_object(value, path)
	if data == null or not _exact_keys(data, [
		"preview_schema_version", "encounter_id", "manifest_digest", "enemy_units",
		"active_traits", "affix_effects", "boss_phases"
	], path):
		return null
	var preview := EncounterPreviewSnapshot.new()
	preview.preview_schema_version = _read_int(
		data, "preview_schema_version", StringName(String(path) + ".preview_schema_version")
	)
	preview.encounter_id = StringName(_read_string(
		data, "encounter_id", StringName(String(path) + ".encounter_id")
	))
	preview.manifest_digest = StringName(_read_string(
		data, "manifest_digest", StringName(String(path) + ".manifest_digest")
	))
	var unit_values := _read_array(data["enemy_units"], StringName(String(path) + ".enemy_units"))
	for index: int in range(unit_values.size()):
		var unit := _decode_preview_unit(
			unit_values[index], StringName("%s.enemy_units.%d" % [String(path), index])
		)
		if unit == null:
			return null
		preview.enemy_units.append(unit)
	var trait_values := _read_array(data["active_traits"], StringName(String(path) + ".active_traits"))
	for index: int in range(trait_values.size()):
		var trait_snapshot := _decode_preview_trait(
			trait_values[index], StringName("%s.active_traits.%d" % [String(path), index])
		)
		if trait_snapshot == null:
			return null
		preview.active_traits.append(trait_snapshot)
	var effect_values := _read_array(data["affix_effects"], StringName(String(path) + ".affix_effects"))
	for index: int in range(effect_values.size()):
		var effect := _decode_preview_effect(
			effect_values[index], StringName("%s.affix_effects.%d" % [String(path), index])
		)
		if effect == null:
			return null
		preview.affix_effects.append(effect)
	var phase_values := _read_array(data["boss_phases"], StringName(String(path) + ".boss_phases"))
	for index: int in range(phase_values.size()):
		var phase := _decode_preview_phase(
			phase_values[index], StringName("%s.boss_phases.%d" % [String(path), index])
		)
		if phase == null:
			return null
		preview.boss_phases.append(phase)
	var validation := EncounterPreviewValidator.new().validate(preview)
	if not validation.ok:
		_set_decode_error(StringName("%s.%s" % [String(path), String(validation.error.field_path)]))
		return null
	return preview

func _decode_preview_unit(value: Variant, path: StringName) -> UnitBattleSnapshot:
	var data := _read_object(value, path)
	if data == null or not _exact_keys(data, [
		"instance_id", "unit_id", "side", "logical_y", "logical_x", "star",
		"health", "attack", "armor", "magic_resist", "attack_speed_milli",
		"attack_range_cells", "start_mana", "max_mana", "move_speed_milli",
		"basic_attack_profile", "ability_id", "effect_ids", "effect_assignments"
	], path):
		return null
	var unit := UnitBattleSnapshot.new()
	unit.instance_id = StringName(_read_string(data, "instance_id", StringName(String(path) + ".instance_id")))
	unit.unit_id = StringName(_read_string(data, "unit_id", StringName(String(path) + ".unit_id")))
	unit.side = StringName(_read_string(data, "side", StringName(String(path) + ".side")))
	unit.logical_y = _read_int(data, "logical_y", StringName(String(path) + ".logical_y"))
	unit.logical_x = _read_int(data, "logical_x", StringName(String(path) + ".logical_x"))
	unit.star = _read_int(data, "star", StringName(String(path) + ".star"))
	unit.health = _read_int(data, "health", StringName(String(path) + ".health"))
	unit.attack = _read_int(data, "attack", StringName(String(path) + ".attack"))
	unit.armor = _read_int(data, "armor", StringName(String(path) + ".armor"))
	unit.magic_resist = _read_int(data, "magic_resist", StringName(String(path) + ".magic_resist"))
	unit.attack_speed_milli = _read_int(data, "attack_speed_milli", StringName(String(path) + ".attack_speed_milli"))
	unit.attack_range_cells = _read_int(data, "attack_range_cells", StringName(String(path) + ".attack_range_cells"))
	unit.start_mana = _read_int(data, "start_mana", StringName(String(path) + ".start_mana"))
	unit.max_mana = _read_int(data, "max_mana", StringName(String(path) + ".max_mana"))
	unit.move_speed_milli = _read_int(data, "move_speed_milli", StringName(String(path) + ".move_speed_milli"))
	unit.basic_attack_profile = StringName(_read_string(
		data, "basic_attack_profile", StringName(String(path) + ".basic_attack_profile")
	))
	if data["ability_id"] != null:
		unit.ability_id = OptionalStringNameValue.of(StringName(_read_variant_string(
			data["ability_id"], StringName(String(path) + ".ability_id")
		)))
	unit.effect_ids = _read_name_array(data["effect_ids"], StringName(String(path) + ".effect_ids"))
	var assignment_values := _read_array(
		data["effect_assignments"], StringName(String(path) + ".effect_assignments")
	)
	for index: int in range(assignment_values.size()):
		var assignment := _decode_preview_effect(
			assignment_values[index], StringName("%s.effect_assignments.%d" % [String(path), index])
		)
		if assignment == null:
			return null
		unit.effect_assignments.append(assignment)
	return unit

func _decode_preview_trait(value: Variant, path: StringName) -> TraitBattleSnapshot:
	var data := _read_object(value, path)
	if data == null or not _exact_keys(data, [
		"trait_id", "tier", "member_instance_ids", "effect_assignments"
	], path):
		return null
	var trait_snapshot := TraitBattleSnapshot.new()
	trait_snapshot.trait_id = StringName(_read_string(
		data, "trait_id", StringName(String(path) + ".trait_id")
	))
	trait_snapshot.tier = _read_int(data, "tier", StringName(String(path) + ".tier"))
	trait_snapshot.member_instance_ids = _read_name_array(
		data["member_instance_ids"], StringName(String(path) + ".member_instance_ids")
	)
	var assignment_values := _read_array(
		data["effect_assignments"], StringName(String(path) + ".effect_assignments")
	)
	for index: int in range(assignment_values.size()):
		var assignment := _decode_preview_effect(
			assignment_values[index], StringName("%s.effect_assignments.%d" % [String(path), index])
		)
		if assignment == null:
			return null
		trait_snapshot.effect_assignments.append(assignment)
	return trait_snapshot

func _decode_preview_effect(value: Variant, path: StringName) -> BattleEffectSnapshot:
	var data := _read_object(value, path)
	if data == null or not _exact_keys(data, [
		"priority", "source_category", "source_side", "source_stable_id",
		"source_instance_id", "source_slot", "effect_index", "effect_id",
		"target_ids", "integer_params", "id_params"
	], path):
		return null
	var effect := BattleEffectSourceAssignmentSnapshot.new()
	effect.priority = _read_int(data, "priority", StringName(String(path) + ".priority"))
	effect.source_category = StringName(_read_string(
		data, "source_category", StringName(String(path) + ".source_category")
	))
	effect.source_side = StringName(_read_string(
		data, "source_side", StringName(String(path) + ".source_side")
	))
	effect.source_stable_id = StringName(_read_string(
		data, "source_stable_id", StringName(String(path) + ".source_stable_id")
	))
	if data["source_instance_id"] != null:
		effect.source_instance_id = OptionalStringNameValue.of(StringName(_read_variant_string(
			data["source_instance_id"], StringName(String(path) + ".source_instance_id")
		)))
	effect.source_slot = _read_int(data, "source_slot", StringName(String(path) + ".source_slot"))
	effect.effect_index = _read_int(data, "effect_index", StringName(String(path) + ".effect_index"))
	effect.effect_id = StringName(_read_string(data, "effect_id", StringName(String(path) + ".effect_id")))
	effect.target_ids = _read_name_array(data["target_ids"], StringName(String(path) + ".target_ids"))
	var int_values := _read_array(data["integer_params"], StringName(String(path) + ".integer_params"))
	for index: int in range(int_values.size()):
		var parameter_path := StringName("%s.integer_params.%d" % [String(path), index])
		var parameter_data := _read_object(int_values[index], parameter_path)
		if parameter_data == null or not _exact_keys(parameter_data, ["key", "value"], parameter_path):
			return null
		var int_parameter := BattleIntParam.new()
		int_parameter.key = StringName(_read_string(
			parameter_data, "key", StringName(String(parameter_path) + ".key")
		))
		int_parameter.value = _read_int(
			parameter_data, "value", StringName(String(parameter_path) + ".value")
		)
		effect.integer_params.append(int_parameter)
	var id_values := _read_array(data["id_params"], StringName(String(path) + ".id_params"))
	for index: int in range(id_values.size()):
		var parameter_path := StringName("%s.id_params.%d" % [String(path), index])
		var parameter_data := _read_object(id_values[index], parameter_path)
		if parameter_data == null or not _exact_keys(parameter_data, ["key", "value"], parameter_path):
			return null
		var id_parameter := BattleIdParam.new()
		id_parameter.key = StringName(_read_string(
			parameter_data, "key", StringName(String(parameter_path) + ".key")
		))
		id_parameter.value = StringName(_read_string(
			parameter_data, "value", StringName(String(parameter_path) + ".value")
		))
		effect.id_params.append(id_parameter)
	return effect

func _decode_preview_phase(value: Variant, path: StringName) -> BossPhaseSnapshot:
	var data := _read_object(value, path)
	if data == null or not _exact_keys(data, [
		"phase_index", "hp_threshold_bps", "source_instance_id", "effect_ids"
	], path):
		return null
	var phase := BossPhaseSnapshot.new()
	phase.phase_index = _read_int(data, "phase_index", StringName(String(path) + ".phase_index"))
	phase.hp_threshold_bps = _read_int(data, "hp_threshold_bps", StringName(String(path) + ".hp_threshold_bps"))
	phase.source_instance_id = StringName(_read_string(
		data, "source_instance_id", StringName(String(path) + ".source_instance_id")
	))
	phase.effect_ids = _read_name_array(data["effect_ids"], StringName(String(path) + ".effect_ids"))
	return phase

func _read_object(value: Variant, path: StringName) -> Dictionary:
	if not value is Dictionary:
		_set_decode_error(path)
		return {}
	return value

func _canonicalize_variant(value: Variant) -> String:
	if value == null:
		return "null"
	if value is String:
		return _quote(value)
	if value is bool:
		return "true" if value else "false"
	if value is int:
		return str(value)
	if value is float:
		return str(int(value)) if is_finite(value) and floor(value) == value else "null"
	if value is Array:
		var elements: Array[String] = []
		for element: Variant in value:
			elements.append(_canonicalize_variant(element))
		return _array(elements)
	if value is Dictionary:
		var fields: Array[String] = []
		for key: Variant in value.keys():
			if not key is String:
				return "null"
			fields.append(_field(key, _canonicalize_variant(value[key])))
		return _object(fields)
	return "null"

func _read_array(value: Variant, path: StringName) -> Array:
	if not value is Array:
		_set_decode_error(path)
		return []
	return value

func _read_string(data: Dictionary, key: String, path: StringName) -> String:
	if not data.has(key):
		_set_decode_error(path)
		return ""
	return _read_variant_string(data[key], path)

func _read_variant_string(value: Variant, path: StringName) -> String:
	if not value is String:
		_set_decode_error(path)
		return ""
	return value

func _read_int(data: Dictionary, key: String, path: StringName) -> int:
	if not data.has(key):
		_set_decode_error(path)
		return 0
	var value: Variant = data[key]
	if value is int:
		return value
	if value is float and is_finite(value) and floor(value) == value \
		and value >= -2147483648.0 and value <= 4294967295.0:
		return int(value)
	_set_decode_error(path)
	return 0

func _read_bool(data: Dictionary, key: String, path: StringName) -> bool:
	if not data.has(key) or not data[key] is bool:
		_set_decode_error(path)
		return false
	return data[key]

func _read_u64(value: Variant, path: StringName) -> U64Bits:
	if not value is String:
		_set_decode_error(path)
		return null
	var result := U64Bits.from_hex(value)
	if not result.ok:
		_set_decode_error(path)
		return null
	return result.value

func _read_optional_string(value: Variant, path: StringName) -> OptionalStringValue:
	if value == null:
		return null
	if not value is String:
		_set_decode_error(path)
		return null
	return OptionalStringValue.new(value)

func _read_string_array(value: Variant, path: StringName) -> Array[String]:
	var values := _read_array(value, path)
	var output: Array[String] = []
	for index: int in range(values.size()):
		if not values[index] is String:
			_set_decode_error(StringName("%s.%d" % [String(path), index]))
			return []
		output.append(values[index])
	return output

func _read_name_array(value: Variant, path: StringName) -> Array[StringName]:
	var strings := _read_string_array(value, path)
	var output: Array[StringName] = []
	for text: String in strings:
		output.append(StringName(text))
	return output

func _read_int_array(value: Variant, path: StringName) -> Array[int]:
	var values := _read_array(value, path)
	var output: Array[int] = []
	for index: int in range(values.size()):
		var holder: Dictionary = {"value": values[index]}
		output.append(_read_int(holder, "value", StringName("%s.%d" % [String(path), index])))
	return output

func _exact_keys(data: Dictionary, expected: Array[String], path: StringName) -> bool:
	if data.size() != expected.size():
		_set_decode_error(path)
		return false
	for key: String in expected:
		if not data.has(key):
			_set_decode_error(StringName("%s.%s" % [String(path), key]))
			return false
	return true

func _enum_index(value: String, allowed: Array[String], path: StringName) -> int:
	var index := allowed.find(value)
	if index < 0:
		_set_decode_error(path)
	return index

func _same_names(left: Array[StringName], right: Array[StringName]) -> bool:
	if left.size() != right.size():
		return false
	for index: int in range(left.size()):
		if left[index] != right[index]:
			return false
	return true

func _migrate_profile_names(values: Array[StringName], path: StringName) -> Array[StringName]:
	var output: Array[StringName] = []
	for index: int in range(values.size()):
		var original := values[index]
		if _migration_port == null:
			output.append(original)
			continue
		var result := _migration_port.resolve(ContentIdMigrationRequest.new(
			original, &"", false, StringName("%s.%d" % [String(path), index])
		))
		if not result.ok:
			output.append(original)
			continue
		if result.disposition == ContentIdMigrationResult.Disposition.SAFE_ABSENT:
			continue
		if result.resolved_id != null:
			output.append(result.resolved_id.value)
	output.sort_custom(func(left: StringName, right: StringName) -> bool:
		return String(left) < String(right)
	)
	var unique: Array[StringName] = []
	for value: StringName in output:
		if unique.is_empty() or unique[unique.size() - 1] != value:
			unique.append(value)
	return unique

func _migrate_comparison_names(values: Array[StringName]) -> Array[StringName]:
	var output: Array[StringName] = []
	for value: StringName in values:
		var mapped := _migrate_comparison_id(value)
		if not mapped.is_empty():
			output.append(mapped)
	output.sort_custom(func(left: StringName, right: StringName) -> bool:
		return String(left) < String(right)
	)
	return output

func _migrate_comparison_id(value: StringName) -> StringName:
	if _migration_port == null:
		return value
	var result := _migration_port.resolve(ContentIdMigrationRequest.new(
		value, &"", false, &"run.content_snapshot"
	))
	if not result.ok:
		return value
	if result.disposition == ContentIdMigrationResult.Disposition.SAFE_ABSENT:
		return &""
	return result.resolved_id.value if result.resolved_id != null else value

func _migrate_required_id(
	value: StringName,
	expected_category: StringName,
	path: StringName
) -> StringName:
	if _migration_port == null:
		_mark_run_incompatible(value, path, ContentIdMigrationError.TOMBSTONE_REQUIRED)
		return value
	var result := _migration_port.resolve(ContentIdMigrationRequest.new(
		value, expected_category, true, path
	))
	if not result.ok or result.resolved_id == null:
		var code := result.error.code if result.error != null else ContentIdMigrationError.TOMBSTONE_REQUIRED
		_mark_run_incompatible(value, path, code)
		return value
	var resolved := result.resolved_id.value
	if not _active_receipt_ids.is_empty() and not _active_receipt_ids.has(resolved):
		_mark_run_incompatible(value, path, ContentIdMigrationError.TOMBSTONE_REQUIRED)
		return value
	return resolved

func _mark_run_incompatible(value: StringName, path: StringName, code: StringName) -> void:
	if not _run_incompatible_content_ids.has(value):
		_run_incompatible_content_ids.append(value)
	_migration_diagnostics.append(LoadDiagnostic.new(
		code, path, [DiagnosticValue.from_string(&"content_id", String(value))]
	))

func _set_decode_error(path: StringName) -> void:
	if _decode_error_path.is_empty():
		_decode_error_path = path

func _current_decode_failure() -> SaveDecodeResult:
	return _decode_failure(_decode_error_path if not _decode_error_path.is_empty() else &"root")

func _decode_failure(path: StringName) -> SaveDecodeResult:
	return SaveDecodeResult.failure(SaveCodecError.new(path))
