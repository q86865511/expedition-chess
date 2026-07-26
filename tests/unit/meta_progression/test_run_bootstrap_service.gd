extends GutTest

## T05 (specs/meta-progression/design.md SS4.2; requirements.md S5-AC-002,
## S5-AC-009 前置檢查段; design.md SS12 row 002
## "test_start_expedition_locks_commander_and_excludes_from_board" -- pure
## construction half): RunBootstrapService.build() is the sole producer of a
## fresh RunState from (profile, commander_def, challenge_level, pinned_receipt,
## catalog). See tests/fixtures/camp/start_expedition_test_fixture.gd's header
## for the full pinned contract these assertions check against.

func test_build_rejects_null_inputs() -> void:
	var service := StartExpeditionTestFixture.bootstrap_service()
	var profile := StartExpeditionTestFixture.base_profile()
	var commander := StartExpeditionTestFixture.commander_alpha()
	var receipt := StartExpeditionTestFixture.receipt()
	var catalog := StartExpeditionTestFixture.catalog()

	assert_false(service.build(null, commander, 0, receipt, catalog).ok)
	assert_false(service.build(profile, null, 0, receipt, catalog).ok)
	assert_false(service.build(profile, commander, 0, null, catalog).ok)
	assert_false(service.build(profile, commander, 0, receipt, null).ok)


func test_build_rejects_catalog_from_a_different_pinned_generation() -> void:
	var result := StartExpeditionTestFixture.bootstrap_service().build(
		StartExpeditionTestFixture.base_profile(),
		StartExpeditionTestFixture.commander_alpha(),
		0,
		StartExpeditionTestFixture.receipt(),
		StartExpeditionTestFixture.foreign_catalog()
	)

	assert_false(result.ok, "a pool may only come from the run's own pinned generation")
	assert_eq(result.error.code, RunBootstrapError.INPUT_INVALID)
	assert_eq(result.error.field_path, &"catalog.manifest_digest")


func test_build_locks_commander_id_and_challenge_level_on_run() -> void:
	var service := StartExpeditionTestFixture.bootstrap_service()
	var profile := StartExpeditionTestFixture.base_profile()
	var commander := StartExpeditionTestFixture.commander_alpha()

	var result := service.build(
		profile, commander, 3, StartExpeditionTestFixture.receipt(),
		StartExpeditionTestFixture.catalog()
	)

	assert_true(result.ok)
	if not result.ok:
		return
	assert_eq(result.run.commander_id, StartExpeditionTestFixture.COMMANDER_ALPHA_ID)
	assert_eq(result.run.challenge_level, 3)
	assert_eq(result.run.run_phase, RunState.RunPhase.MAP)
	assert_eq(result.run.expedition_hp, 100)
	assert_true(result.run.map_state.nodes.is_empty())


func test_build_pins_content_snapshot_to_current_generation() -> void:
	var service := StartExpeditionTestFixture.bootstrap_service()
	var profile := StartExpeditionTestFixture.base_profile()
	var commander := StartExpeditionTestFixture.commander_beta()
	var receipt := StartExpeditionTestFixture.receipt()

	var result := service.build(
		profile, commander, 0, receipt, StartExpeditionTestFixture.catalog()
	)

	assert_true(result.ok)
	if not result.ok:
		return
	var expected := ContentSnapshotState.from_pinned_receipt(receipt)
	assert_true(expected.ok)
	assert_true(result.run.content_snapshot.canonical_equals(expected.snapshot))
	assert_eq(result.run.content_snapshot.manifest_digest_value(), receipt.manifest_digest)


func test_build_seeds_roster_from_starting_pack_and_excludes_commander() -> void:
	var service := StartExpeditionTestFixture.bootstrap_service()
	var profile := StartExpeditionTestFixture.base_profile()
	var commander := StartExpeditionTestFixture.commander_gamma()

	var result := service.build(
		profile, commander, 0, StartExpeditionTestFixture.receipt(),
		StartExpeditionTestFixture.catalog()
	)

	assert_true(result.ok)
	if not result.ok:
		return
	var roster := result.run.roster_state
	assert_true(roster.board.placements.is_empty(), "commander must not pre-place anyone on the board")
	# gamma starting_pack = 1x recruit_a + 2x recruit_b = 3 units, all benched.
	assert_eq(roster.unit_instances.size(), 3)
	assert_eq(roster.bench_unit_instance_ids.size(), 3)
	var def_ids: Array[StringName] = []
	for unit: UnitInstance in roster.unit_instances:
		assert_eq(unit.star, 1)
		assert_true(roster.bench_unit_instance_ids.has(unit.instance_id))
		assert_ne(
			unit.def_id, StartExpeditionTestFixture.COMMANDER_GAMMA_ID,
			"the commander itself must never become a UnitInstance"
		)
		def_ids.append(unit.def_id)
	var recruit_a_count := 0
	var recruit_b_count := 0
	for def_id: StringName in def_ids:
		if def_id == StartExpeditionTestFixture.UNIT_GAMMA_RECRUIT_A:
			recruit_a_count += 1
		elif def_id == StartExpeditionTestFixture.UNIT_GAMMA_RECRUIT_B:
			recruit_b_count += 1
	assert_eq(recruit_a_count, 1)
	assert_eq(recruit_b_count, 2)
	assert_eq(result.run.next_unit_serial.to_hex(), U64Bits.from_u32(0, 3).value.to_hex())


func test_build_canonicalizes_starting_pack_before_assigning_unit_serials() -> void:
	# W5 R2 #9 / S5-AC-002：starting_pack 是 canonical set，authoring 陣列順序
	# 不具 gameplay 語意。相同的 (content_id,count_u32) 集合必須產生完全相同的
	# instance serial→def 映射、bench 排列與 pool 守恆結果。
	var authoring_b_first: Array[ContentAmountDef] = [
		StartExpeditionTestFixture.amount(StartExpeditionTestFixture.UNIT_GAMMA_RECRUIT_B, 2),
		StartExpeditionTestFixture.amount(StartExpeditionTestFixture.UNIT_GAMMA_RECRUIT_A, 1),
	]
	var authoring_a_first: Array[ContentAmountDef] = [
		StartExpeditionTestFixture.amount(StartExpeditionTestFixture.UNIT_GAMMA_RECRUIT_A, 1),
		StartExpeditionTestFixture.amount(StartExpeditionTestFixture.UNIT_GAMMA_RECRUIT_B, 2),
	]
	var service := StartExpeditionTestFixture.bootstrap_service()
	var first := service.build(
		StartExpeditionTestFixture.base_profile(),
		StartExpeditionTestFixture.commander_with(authoring_b_first),
		0, StartExpeditionTestFixture.receipt(), StartExpeditionTestFixture.catalog()
	)
	var second := service.build(
		StartExpeditionTestFixture.base_profile(),
		StartExpeditionTestFixture.commander_with(authoring_a_first),
		0, StartExpeditionTestFixture.receipt(), StartExpeditionTestFixture.catalog()
	)

	assert_true(first.ok and second.ok)
	if not (first.ok and second.ok):
		return
	var first_roster := first.run.roster_state
	var second_roster := second.run.roster_state
	assert_eq(first_roster.unit_instances.size(), second_roster.unit_instances.size())
	for index: int in range(first_roster.unit_instances.size()):
		var left: UnitInstance = first_roster.unit_instances[index]
		var right: UnitInstance = second_roster.unit_instances[index]
		assert_eq(left.instance_id, right.instance_id)
		assert_eq(left.acquired_serial.to_hex(), right.acquired_serial.to_hex())
		assert_eq(
			left.def_id, right.def_id,
			"the same serial must resolve to the same def regardless of authoring order"
		)
	assert_eq(
		first_roster.bench_unit_instance_ids, second_roster.bench_unit_instance_ids,
		"canonical starting pack order must also define the initial bench order"
	)
	assert_eq(
		first.run.unit_pool_state.entries.size(),
		second.run.unit_pool_state.entries.size()
	)
	for index: int in range(first.run.unit_pool_state.entries.size()):
		var left_pool: UnitPoolEntryState = first.run.unit_pool_state.entries[index]
		var right_pool: UnitPoolEntryState = second.run.unit_pool_state.entries[index]
		assert_eq(left_pool.unit_def_id, right_pool.unit_def_id)
		assert_eq(left_pool.total_copies, right_pool.total_copies)
		assert_eq(left_pool.remaining_copies, right_pool.remaining_copies)
		assert_eq(left_pool.reserved_copies, right_pool.reserved_copies)
		assert_eq(left_pool.held_copies, right_pool.held_copies)


func test_build_rejects_starting_pack_larger_than_the_bench() -> void:
	# W3-F8: 10 units cannot fit BoardPreparationValidator.BENCH_CAPACITY (9), and
	# the content gate has no starting_pack size rule -- so bootstrap must name it
	# rather than let RunStateValidator raise a generic VALIDATION_FAILED.
	var pack: Array[ContentAmountDef] = [
		StartExpeditionTestFixture.amount(StartExpeditionTestFixture.UNIT_ALPHA_RECRUIT, 6),
		StartExpeditionTestFixture.amount(StartExpeditionTestFixture.UNIT_BETA_RECRUIT, 4),
	]

	var result := StartExpeditionTestFixture.bootstrap_service().build(
		StartExpeditionTestFixture.base_profile(),
		StartExpeditionTestFixture.commander_with(pack),
		0,
		StartExpeditionTestFixture.receipt(),
		StartExpeditionTestFixture.catalog()
	)

	assert_false(result.ok)
	assert_eq(result.error.code, RunBootstrapError.INPUT_INVALID)
	assert_eq(result.error.field_path, &"commander_def.starting_pack")


func test_build_accepts_a_starting_pack_exactly_filling_the_bench() -> void:
	var pack: Array[ContentAmountDef] = [
		StartExpeditionTestFixture.amount(StartExpeditionTestFixture.UNIT_ALPHA_RECRUIT, 5),
		StartExpeditionTestFixture.amount(StartExpeditionTestFixture.UNIT_BETA_RECRUIT, 4),
	]

	var result := StartExpeditionTestFixture.bootstrap_service().build(
		StartExpeditionTestFixture.base_profile(),
		StartExpeditionTestFixture.commander_with(pack),
		0,
		StartExpeditionTestFixture.receipt(),
		StartExpeditionTestFixture.catalog()
	)

	assert_true(result.ok, "9 seeded units is exactly BENCH_CAPACITY and must be accepted")
	if not result.ok:
		return
	assert_eq(result.run.roster_state.bench_unit_instance_ids.size(), 9)
	assert_true(RunStateValidator.new().validate_run(result.run).ok)


func test_build_pool_is_the_whole_catalog_minus_the_starting_pack() -> void:
	# W3-F1: the pool must be catalog.create_initial_pool() with the starting_pack's
	# copies moved from remaining to held -- NOT "only the defs the commander deals,
	# all with remaining == 0", which left the shop with nothing to offer all run.
	var service := StartExpeditionTestFixture.bootstrap_service()
	var profile := StartExpeditionTestFixture.base_profile()
	var commander := StartExpeditionTestFixture.commander_alpha()
	var catalog := StartExpeditionTestFixture.catalog()

	var result := service.build(
		profile, commander, 0, StartExpeditionTestFixture.receipt(), catalog
	)

	assert_true(result.ok)
	if not result.ok:
		return
	var pool := result.run.unit_pool_state
	var initial := catalog.create_initial_pool()
	assert_eq(
		pool.entries.size(), initial.entries.size(),
		"one entry per catalog unit, not just the starting_pack's defs"
	)
	var copies := StartExpeditionTestFixture.CATALOG_TIER_1_COPIES
	# alpha starting_pack = 2x recruit, all star 1 -> weighted copies == 2.
	var dealt := _entry(pool, StartExpeditionTestFixture.UNIT_ALPHA_RECRUIT)
	assert_not_null(dealt)
	assert_eq(dealt.held_copies, 2)
	assert_eq(dealt.remaining_copies, copies - 2, "the dealt copies leave the shop's supply")
	assert_eq(dealt.reserved_copies, 0)
	assert_eq(dealt.total_copies, copies, "per-def total is conserved")
	# A unit nobody deals keeps the catalog's full supply.
	var untouched := _entry(pool, StartExpeditionTestFixture.UNIT_SHOP_ONLY)
	assert_not_null(untouched)
	assert_eq(untouched.held_copies, 0)
	assert_eq(untouched.remaining_copies, copies)
	assert_eq(untouched.total_copies, copies)
	# Ascending def_id order, as RunStateValidator._validate_pool requires.
	var previous := ""
	for entry: UnitPoolEntryState in pool.entries:
		assert_true(String(entry.unit_def_id) > previous, "pool entries must be sorted ascending")
		previous = String(entry.unit_def_id)
	assert_true(RunStateValidator.new().validate_run(result.run).ok)


func test_build_gives_a_commander_exclusive_unit_a_player_only_pool_entry() -> void:
	var result := StartExpeditionTestFixture.bootstrap_service().build(
		StartExpeditionTestFixture.base_profile(),
		StartExpeditionTestFixture.commander_delta(),
		0,
		StartExpeditionTestFixture.receipt(),
		StartExpeditionTestFixture.catalog()
	)

	assert_true(result.ok)
	if not result.ok:
		return
	# UNIT_DELTA_EXCLUSIVE has no ShopUnitRule, so it has no catalog pool entry; it
	# still needs one (conservation), but the shop must never be able to draw it.
	var exclusive := _entry(
		result.run.unit_pool_state, StartExpeditionTestFixture.UNIT_DELTA_EXCLUSIVE
	)
	assert_not_null(exclusive)
	assert_eq(exclusive.held_copies, 2)
	assert_eq(exclusive.remaining_copies, 0)
	assert_eq(exclusive.reserved_copies, 0)
	assert_eq(exclusive.total_copies, 2)
	assert_true(RunStateValidator.new().validate_run(result.run).ok)


func test_build_rejects_a_starting_pack_exceeding_the_catalog_pool_supply() -> void:
	# tier-1 units have CATALOG_TIER_1_COPIES copies; a pack asking for more than
	# the pool holds cannot be dealt without inventing copies (breaking the total).
	var pack: Array[ContentAmountDef] = [
		StartExpeditionTestFixture.amount(StartExpeditionTestFixture.UNIT_ALPHA_RECRUIT, 3),
	]
	var thin_catalog := EconomyExpeditionCatalog.new(
		StartExpeditionTestFixture.receipt().manifest_digest,
		_config_with_tier_1_copies(2),
		_alpha_only_units(),
		_no_map_nodes()
	)

	var result := StartExpeditionTestFixture.bootstrap_service().build(
		StartExpeditionTestFixture.base_profile(),
		StartExpeditionTestFixture.commander_with(pack),
		0,
		StartExpeditionTestFixture.receipt(),
		thin_catalog
	)

	assert_false(result.ok)
	assert_eq(result.error.code, RunBootstrapError.INPUT_INVALID)
	assert_eq(result.error.field_path, &"commander_def.starting_pack.count_u32")


func test_bootstrapped_run_can_open_a_shop_and_receive_offers() -> void:
	# W3-F1 regression, end of the failure chain the reviewer described: a run built
	# by this service must be playable, i.e. ShopService must actually draw offers
	# out of its pool. The old pool shape returned ok with ZERO offers, forever.
	var catalog := StartExpeditionTestFixture.catalog()
	var result := StartExpeditionTestFixture.bootstrap_service().build(
		StartExpeditionTestFixture.base_profile(),
		StartExpeditionTestFixture.commander_alpha(),
		0,
		StartExpeditionTestFixture.receipt(),
		catalog
	)

	assert_true(result.ok)
	if not result.ok:
		return
	var run := result.run
	var generated := ShopService.new().generate_offers(GenerateOffersRequest.new(
		StringName(run.run_id), &"node_fixture", run.economy_state,
		run.unit_pool_state, run.roster_state, run.reservation_owners,
		EconomyTestFixture.shop_rng(), run.next_transaction_serial,
		run.next_unit_serial, catalog
	))

	assert_true(generated.ok, "a bootstrapped run must be able to open the shop")
	if not generated.ok:
		return
	assert_eq(
		generated.transaction.economy_state.shop_offers.size(),
		ShopService.OFFER_COUNT,
		"every shop slot must be fillable from the bootstrapped pool"
	)


func test_build_keeps_population_bonus_out_of_the_starting_economy_level() -> void:
	# W3-F3: economy_state.level is the shop tier-odds key AND the XP ladder, so it
	# must carry only STARTING_ECONOMY_LEVEL -- a commander's population_bonus must
	# not buy shop odds or free levels (REQ-META-002).
	var service := StartExpeditionTestFixture.bootstrap_service()
	var profile := StartExpeditionTestFixture.base_profile()
	var receipt := StartExpeditionTestFixture.receipt()
	var catalog := StartExpeditionTestFixture.catalog()

	var alpha_result := service.build(
		profile, StartExpeditionTestFixture.commander_alpha(), 0, receipt, catalog
	)
	var beta_result := service.build(
		profile, StartExpeditionTestFixture.commander_beta(), 0, receipt, catalog
	)
	var gamma_result := service.build(
		profile, StartExpeditionTestFixture.commander_gamma(), 0, receipt, catalog
	)

	assert_true(alpha_result.ok and beta_result.ok and gamma_result.ok)
	if not (alpha_result.ok and beta_result.ok and gamma_result.ok):
		return
	var base_level := RunBootstrapService.STARTING_ECONOMY_LEVEL
	# alpha bonus 1 / beta bonus 0 / gamma bonus 2 -- all start on the same level.
	assert_eq(alpha_result.run.economy_state.level, base_level)
	assert_eq(beta_result.run.economy_state.level, base_level)
	assert_eq(gamma_result.run.economy_state.level, base_level)


func test_try_commander_population_source_carries_the_bonus() -> void:
	# design.md SS4.2's "population cap 於此套用 commander.population_bonus": the
	# bonus is an EXTRA population source on top of base_level, exactly how
	# content_validator.gd's population budget counts it.
	var gamma := StartExpeditionTestFixture.commander_gamma()
	var source := RunBootstrapService.try_commander_population_source(gamma.id, gamma.population_bonus)

	assert_not_null(source)
	assert_eq(source.source_kind, PopulationSourceSnapshot.SourceKind.COMMANDER)
	assert_eq(source.source_id, StartExpeditionTestFixture.COMMANDER_GAMMA_ID)
	assert_eq(source.amount, 2)
	var sources: Array[PopulationSourceSnapshot] = [source]
	var population := PopulationCalculator.new().calculate(
		RunBootstrapService.STARTING_ECONOMY_LEVEL, sources
	)
	assert_true(population.ok)
	assert_eq(
		population.derived_capacity, RunBootstrapService.STARTING_ECONOMY_LEVEL + 2,
		"capacity == base_level + commander bonus"
	)
	# "no bonus" is the absence of a source, not a zero-amount one (which
	# PopulationCalculator rejects as INVALID_SOURCE).
	var beta := StartExpeditionTestFixture.commander_beta()
	assert_null(RunBootstrapService.try_commander_population_source(beta.id, beta.population_bonus))


func test_build_rejects_a_negative_population_bonus() -> void:
	var empty_pack: Array[ContentAmountDef] = []

	var result := StartExpeditionTestFixture.bootstrap_service().build(
		StartExpeditionTestFixture.base_profile(),
		StartExpeditionTestFixture.commander_with(empty_pack, -1),
		0,
		StartExpeditionTestFixture.receipt(),
		StartExpeditionTestFixture.catalog()
	)

	assert_false(result.ok, "a negative population bonus has no valid meaning")
	assert_eq(result.error.code, RunBootstrapError.INPUT_INVALID)
	assert_eq(result.error.field_path, &"commander_def.population_bonus")


func test_build_seeds_four_named_rng_streams() -> void:
	var service := StartExpeditionTestFixture.bootstrap_service()
	var profile := StartExpeditionTestFixture.base_profile()
	var commander := StartExpeditionTestFixture.commander_alpha()

	var result := service.build(
		profile, commander, 0, StartExpeditionTestFixture.receipt(),
		StartExpeditionTestFixture.catalog()
	)

	assert_true(result.ok)
	if not result.ok:
		return
	assert_eq(result.run.rng_stream_states.size(), 4)
	for index: int in range(4):
		var named: NamedRngState = result.run.rng_stream_states[index]
		assert_eq(named.stream_name, index)
		assert_not_null(named.snapshot)
		assert_eq(named.snapshot.rng_version, 1)


func test_build_run_seed_is_deterministic_from_profile_id_and_next_run_serial() -> void:
	var service := StartExpeditionTestFixture.bootstrap_service()
	var receipt := StartExpeditionTestFixture.receipt()
	var catalog := StartExpeditionTestFixture.catalog()
	var commander := StartExpeditionTestFixture.commander_alpha()
	var profile_a := StartExpeditionTestFixture.base_profile(5)
	var profile_a_again := StartExpeditionTestFixture.base_profile(5)
	var profile_b := StartExpeditionTestFixture.base_profile(6)

	var result_a := service.build(profile_a, commander, 0, receipt, catalog)
	var result_a_again := service.build(profile_a_again, commander, 0, receipt, catalog)
	var result_b := service.build(profile_b, commander, 0, receipt, catalog)

	assert_true(result_a.ok and result_a_again.ok and result_b.ok)
	if not (result_a.ok and result_a_again.ok and result_b.ok):
		return
	assert_eq(result_a.run.run_seed.to_hex(), result_a_again.run.run_seed.to_hex())
	assert_eq(result_a.run.run_id, result_a_again.run.run_id)
	assert_ne(result_a.run.run_seed.to_hex(), result_b.run.run_seed.to_hex())
	assert_ne(result_a.run.run_id, result_b.run.run_id)


func test_build_result_passes_full_run_state_validation() -> void:
	var service := StartExpeditionTestFixture.bootstrap_service()
	var profile := StartExpeditionTestFixture.base_profile()
	var commander := StartExpeditionTestFixture.commander_gamma()

	var result := service.build(
		profile, commander, 2, StartExpeditionTestFixture.receipt(),
		StartExpeditionTestFixture.catalog()
	)

	assert_true(result.ok)
	if not result.ok:
		return
	var validation := RunStateValidator.new().validate_run(result.run)
	assert_true(validation.ok, "bootstrapped RunState must satisfy RunStateValidator.validate_run")


func _entry(pool: UnitPoolState, def_id: StringName) -> UnitPoolEntryState:
	for entry: UnitPoolEntryState in pool.entries:
		if entry.unit_def_id == def_id:
			return entry
	return null


func _config_with_tier_1_copies(copies: int) -> EconomyConfigRule:
	var config := StartExpeditionTestFixture.catalog().config()
	var copies_by_tier: Array[EconomyValueRule] = [EconomyValueRule.new(1, copies)]
	config.pool_copies_by_tier = copies_by_tier
	return config


func _alpha_only_units() -> Array[ShopUnitRule]:
	var units: Array[ShopUnitRule] = [
		ShopUnitRule.new(StartExpeditionTestFixture.UNIT_ALPHA_RECRUIT, 1, 1),
	]
	return units


func _no_map_nodes() -> Array[MapNodeRule]:
	var nodes: Array[MapNodeRule] = []
	return nodes
