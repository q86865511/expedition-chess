class_name RunBootstrapService
extends RefCounted

## T05 (specs/meta-progression/design.md SS4.2; requirements.md S5-AC-002,
## S5-AC-009 前置檢查段): the sole producer of a fresh RunState from
## (profile, commander_def, challenge_level, pinned_receipt, catalog).
## Pure/deterministic given its inputs -- no wall-clock, no Object-id entropy,
## no new RNG stream (design.md SS2). The commander is locked onto the run and
## its starting_pack is dealt to the bench OUT OF the shared catalog unit pool;
## business validation (commander unlocked / challenge prerequisite) is
## StartExpeditionCommand's job and happens BEFORE build().
## See tests/fixtures/camp/start_expedition_test_fixture.gd's header for the full
## pinned wire contract this construction satisfies.

const STARTING_ECONOMY_LEVEL: int = 1
const _SHA256_HEX_LENGTH: int = 64

func build(
	profile: ProfileState,
	commander_def: CommanderDef,
	challenge_level: int,
	pinned_receipt: PinnedCatalogBuildReceipt,
	catalog: EconomyExpeditionCatalog
) -> RunBootstrapResult:
	if profile == null:
		return _failure(&"profile")
	if commander_def == null:
		return _failure(&"commander_def")
	if pinned_receipt == null:
		return _failure(&"pinned_receipt")
	if catalog == null:
		return _failure(&"catalog")
	# The pool below is the catalog's; it may only be pinned onto a run whose
	# content_snapshot is the SAME generation (same guard shape as
	# commit_board_layout_command.gd:35-40 and shop_service.gd:183-185).
	if catalog.manifest_digest_value() != pinned_receipt.manifest_digest:
		return _failure(&"catalog.manifest_digest")
	# design.md SS4.2's "population cap 於此套用 commander.population_bonus": a
	# NEGATIVE bonus has no valid meaning (PopulationCalculator only accepts
	# sources with amount > 0), so it is rejected here by name instead of
	# silently shrinking the player's capacity later.
	if commander_def.population_bonus < 0:
		return _failure(&"commander_def.population_bonus")
	# a. content_snapshot pinned to the current generation.
	var snapshot_result := ContentSnapshotState.from_pinned_receipt(pinned_receipt)
	if not snapshot_result.ok:
		return _failure(&"content_snapshot")
	var content_snapshot := snapshot_result.snapshot
	# b. run_key freezes the PRE-increment serial (StartExpeditionCommand bumps
	#    profile' to the NEXT one; RunStateValidator's invariant is
	#    run_key.next_run_serial.add(one) == profile.next_run_serial).
	var key_result := RuntimeKeySchemaRegistry.new().build_run(
		profile.profile_id, profile.next_run_serial
	)
	if not key_result.ok:
		return _failure(&"run_key")
	var run_key: RunKeyState = key_result.key_state as RunKeyState
	# c. run_id.
	var run_id := String(run_key.digest)
	# d. run_seed: deterministic, zero-entropy derivation from the run_key digest
	#    (already the canonical SHA-256 encoding of profile_id + next_run_serial).
	#    The digest is formatted "<kind>_<64 lowercase hex>" (RuntimeKeyCodecV1),
	#    so the SHA-256 hex is the trailing 64 chars -- take its first 16 hex chars
	#    (the fixture header's substr(0, 16) omitted the "run_" kind prefix; its
	#    stated intent is "the digest's first 16 hex chars", which is this).
	var digest_hex := run_id.substr(run_id.length() - _SHA256_HEX_LENGTH)
	var seed_result := U64Bits.from_hex(digest_hex.substr(0, 16))
	if not seed_result.ok:
		return _failure(&"run_seed")
	var run_seed := seed_result.value
	# e. 4 named rng streams, in RngService.STREAMS order (map/shop/reward/combat).
	var rng_service := RngService.new()
	var rng_states: Array[NamedRngState] = []
	for index: int in range(RngService.STREAMS.size()):
		var stream_name := RngService.STREAMS[index]
		var derive := rng_service.derive_stream(run_seed, stream_name, StringName(run_id))
		if not derive.ok:
			return _failure(&"rng_stream")
		rng_states.append(NamedRngState.new(index, derive.stream.snapshot()))
	# f. roster seeded from starting_pack; commander itself never becomes a unit.
	#    Bench guard: every seeded unit goes to the bench, so an oversized
	#    starting_pack must be rejected by name here rather than surfacing as the
	#    generic VALIDATION_FAILED that RunStateValidator's bench bound would raise
	#    only once the player presses "start expedition".
	var canonical_starting_pack: Array[ContentAmountDef] = []
	var seeded_total := 0
	for entry: ContentAmountDef in commander_def.starting_pack:
		if entry == null or entry.count_u32 < 0:
			return _failure(&"commander_def.starting_pack")
		canonical_starting_pack.append(entry)
		seeded_total += entry.count_u32
	if seeded_total > BoardPreparationValidator.BENCH_CAPACITY:
		return _failure(&"commander_def.starting_pack")
	canonical_starting_pack.sort_custom(
		func(left: ContentAmountDef, right: ContentAmountDef) -> bool:
			if left.content_id != right.content_id:
				return String(left.content_id) < String(right.content_id)
			return left.count_u32 < right.count_u32
	)
	var empty_equipment: Array[String] = []
	var units: Array[UnitInstance] = []
	var bench_ids: Array[String] = []
	var running_serial := 0
	for entry: ContentAmountDef in canonical_starting_pack:
		for _copy_index: int in range(entry.count_u32):
			var instance_id := "u_%016x" % running_serial
			var acquired := U64Bits.from_u32(0, running_serial)
			units.append(UnitInstance.new(
				instance_id, entry.content_id, 1, empty_equipment, acquired.value
			))
			bench_ids.append(instance_id)
			running_serial += 1
	var next_unit_serial := U64Bits.from_u32(0, running_serial).value
	# g. unit_pool_state: the WHOLE catalog pool (EconomyExpeditionCatalog
	#    .create_initial_pool()), with the starting_pack's copies moved from
	#    `remaining` to `held` -- the player already holds them, so the shop and
	#    the reward tables must not be able to hand the same copies out again.
	#    Per-def total is conserved, satisfying both RunStateValidator invariants
	#    (_validate_pool's remaining+reserved+held == total and
	#    _validate_pool_roster_conservation's held == star-weighted roster copies).
	#    Seeding ONLY the starting_pack defs (with remaining == 0) would leave every
	#    catalog entry empty: the shop would silently return zero offers for the
	#    whole run and the first unit reward would fail with UNIT_POOL_INVALID.
	var held_by_def: Dictionary = {}
	var distinct_ids: Array[StringName] = []
	for unit: UnitInstance in units:
		if not held_by_def.has(unit.def_id):
			held_by_def[unit.def_id] = 0
			distinct_ids.append(unit.def_id)
		held_by_def[unit.def_id] = int(held_by_def[unit.def_id]) + 1
	var pool_entries: Array[UnitPoolEntryState] = catalog.create_initial_pool().entries
	for def_id: StringName in distinct_ids:
		var held := int(held_by_def[def_id])
		var pool_entry := _find_pool_entry(pool_entries, def_id)
		if pool_entry == null:
			# A commander-exclusive starting unit has no ShopUnitRule and therefore no
			# catalog pool entry, but a roster unit whose def_id has no entry at all
			# fails _validate_pool_roster_conservation. It gets a player-only entry
			# (total == held, nothing left to draw) -- the shape the pre-catalog
			# implementation used for every def, now narrowed to exactly this case.
			pool_entries.append(UnitPoolEntryState.new(def_id, held, 0, 0, held))
			continue
		if pool_entry.remaining_copies < held:
			# The starting_pack wants more copies than the catalog pool holds;
			# inventing copies would break the per-def total, so reject by name.
			return _failure(&"commander_def.starting_pack.count_u32")
		pool_entry.remaining_copies -= held
		pool_entry.held_copies += held
	pool_entries.sort_custom(func(left: UnitPoolEntryState, right: UnitPoolEntryState) -> bool:
		return String(left.unit_def_id) < String(right.unit_def_id)
	)
	# h. economy_state: the starting level is STARTING_ECONOMY_LEVEL, WITHOUT
	#    commander_def.population_bonus. economy_state.level is simultaneously the
	#    shop tier-odds key (shop_service.gd:203) and the XP ladder
	#    (battle_settlement_service.gd:308), so folding the bonus in would hand out
	#    shop power and free levels on top of the population cap design.md SS4.2
	#    authorises -- REQ-META-002's "只加選項不加基礎戰力" red line. The bonus
	#    travels as a population SOURCE instead; see try_commander_population_source().
	var empty_offers: Array[ShopOffer] = []
	var economy := EconomyState.new(
		0, STARTING_ECONOMY_LEVEL, 0, 0, 0, 0, empty_offers
	)
	# i. map_state: no map generated yet.
	var empty_nodes: Array[MapNodeState] = []
	var empty_edges: Array[MapEdgeState] = []
	var empty_completed: Array[String] = []
	var map := MapState.new(empty_nodes, empty_edges, null, empty_completed)
	# k. 5 empty relic slots + roster assembly.
	var empty_placements: Array[BoardPlacementState] = []
	var empty_items: Array[ItemInstanceState] = []
	var empty_inventory: Array[String] = []
	var empty_overflow: Array[String] = []
	var relic_slots: Array[RelicSlotState] = []
	for slot_index: int in range(5):
		relic_slots.append(RelicSlotState.new(slot_index, null))
	var roster := RosterState.new(
		BoardState.new(empty_placements),
		bench_ids,
		units,
		empty_items,
		empty_inventory,
		empty_overflow,
		relic_slots
	)
	var zero := U64Bits.zero()
	var empty_income: Array[String] = []
	var empty_stipend: Array[int] = []
	var empty_owners: Array[ReservationOwnerState] = []
	var empty_transactions: Array[TransactionReceiptState] = []
	var empty_claims: Array[ClaimReceiptState] = []
	var empty_discovered: Array[StringName] = []
	var run := RunState.new(
		run_id,
		run_key,
		run_seed,
		content_snapshot,
		zero,
		next_unit_serial,
		zero,
		commander_def.id,
		challenge_level,
		0,
		map,
		null,
		RunState.RunPhase.MAP,
		100,
		economy,
		UnitPoolState.new(pool_entries),
		roster,
		0,
		0,
		0,
		rng_states,
		empty_income,
		empty_stipend,
		empty_owners,
		empty_transactions,
		empty_claims,
		IdleResolutionState.new(),
		empty_discovered
	)
	return RunBootstrapResult.success(run)

## design.md SS4.2's "population cap 於此套用 commander.population_bonus", expressed
## the way the population model actually works: capacity == base_level + sources
## (population_calculator.gd:8-51), so the commander bonus is an EXTRA source, not
## part of base_level -- which is also how the content budget model counts it
## (content_validator.gd:752-769 adds the commander bonus on top of
## base_population_cap). RunState carries no persisted population-source ledger
## (see commit_board_layout_command.gd's note), so the source is rebuilt
## deterministically by whoever constructs the PREPARE-phase command, from
## (run.commander_id, the pinned CommanderDef). This is the single definition both
## the producer and the consumer share.
## Returns null when there is no bonus: PopulationCalculator only accepts sources
## with amount > 0, and "no bonus" is correctly expressed as "no source".
static func try_commander_population_source(
	commander_id: StringName,
	population_bonus: int
) -> PopulationSourceSnapshot:
	if population_bonus <= 0:
		return null
	return PopulationSourceSnapshot.new(
		PopulationSourceSnapshot.SourceKind.COMMANDER,
		commander_id,
		"commander",
		population_bonus
	)

func _find_pool_entry(
	entries: Array[UnitPoolEntryState],
	def_id: StringName
) -> UnitPoolEntryState:
	for entry: UnitPoolEntryState in entries:
		if entry.unit_def_id == def_id:
			return entry
	return null

func _failure(field_path: StringName) -> RunBootstrapResult:
	return RunBootstrapResult.failure(
		RunBootstrapError.new(RunBootstrapError.INPUT_INVALID, field_path)
	)
