extends GutTest

## T11 (specs/meta-progression/design.md §4.4; tasks.md T11「已知前置缺口」第 3 點) — pins
## the third gap the T11 wiring end-to-end test is expected to hit: content/packs/
## vertical_slice/economy_configs/slice_default.tres's xp_thresholds only defines levels
## 3..8 (see the .tres itself: key_u32 values 3,4,5,6,7,8 -- no 1, no 2), while a freshly
## bootstrapped expedition starts at economy_state.level == RunBootstrapService.
## STARTING_ECONOMY_LEVEL == 1 (run_bootstrap_service.gd:15,152). The first XP a fresh run
## ever earns hits battle_settlement_service.gd's _add_xp() with economy.level == 1, and
## config.value_for(xp_thresholds, 1, -1) falls through to the -1 fallback (nothing keyed at
## 1), tripping `threshold < 1` -> ExpeditionActionError.REWARD_CONFIG_INVALID
## (battle_settlement_service.gd:345-356). Existing content-pack gate tests only ever probed
## levels 3..8 (per HANDOFF.md's own T11-wave4 note about this file), so this never
## surfaced before now.
##
## This is a pure content-DATA gap (the compiled EconomyConfigRule the real pack produces is
## missing entries), not a not-yet-written-class gap, so it needs no dynamic load() -- it is
## already red today against the real content pack, using only already-existing production
## classes (BuildLabContentBootstrap, BattleSettlementService).

## Asserts the DESIRED end state (a valid, positive threshold at levels 1 and 2), not
## today's actual state -- this must be RED now and turn GREEN once the content fix lands.
## (An earlier draft of this test asserted value_for(...)==-1, i.e. "the gap currently
## exists"; that assertion would have started FAILING the moment the content fix landed,
## exactly backwards for a TDD red-then-green test. Fixed before this became the committed
## red evidence.)
func test_slice_default_xp_thresholds_must_cover_levels_one_and_two() -> void:
	var registry := ContentRegistryService.new()
	add_child_autofree(registry)
	var bootstrap := BuildLabContentBootstrap.new().run(registry)
	assert_true(bootstrap.ok, "BuildLabContentBootstrap failed: %s" % bootstrap.error_message)
	if not bootstrap.ok:
		return
	var config := bootstrap.economy_catalog.config()
	assert_true(
		config.value_for(config.xp_thresholds, 1, -1) >= 1,
		"slice_default.tres's xp_thresholds must define a positive threshold for level 1" +
		" (a fresh run starts at economy level 1 -- RunBootstrapService.STARTING_ECONOMY_LEVEL)" +
		" -- currently only levels 3..8 are defined"
	)
	assert_true(
		config.value_for(config.xp_thresholds, 2, -1) >= 1,
		"slice_default.tres's xp_thresholds must define a positive threshold for level 2 too" +
		" (a run that levels up once from the level-1 start must be able to level up again)"
	)


## The behavioural manifestation: a freshly bootstrapped (level 1) run's first XP-granting
## battle win must NOT be rejected with REWARD_CONFIG_INVALID. This must be fixed by adding
## the missing xp_thresholds entries to content/packs/vertical_slice/economy_configs/
## slice_default.tres (a content-data change, not a code change) -- T11's own scope per
## tasks.md's "已知前置缺口" framing (the end-to-end wiring test surfaces it; content is the
## fix, same shape as the two other content gaps HANDOFF.md §3 already documents having been
## found and fixed this same way during S4 wave4).
func test_a_fresh_runs_first_xp_gain_does_not_get_rejected_as_config_invalid() -> void:
	var registry := ContentRegistryService.new()
	add_child_autofree(registry)
	var bootstrap := BuildLabContentBootstrap.new().run(registry)
	assert_true(bootstrap.ok, "BuildLabContentBootstrap failed: %s" % bootstrap.error_message)
	if not bootstrap.ok:
		return
	var digest := bootstrap.manifest_digest
	var root := ResolutionFixtureFactory.create_root(ResolutionState.Kind.BATTLE_RESULT_PENDING)
	root.run.content_snapshot = bootstrap.content_snapshot
	root.run.run_phase = RunState.RunPhase.COMBAT
	root.run.expedition_hp = 100
	root.run.economy_state.level = 1
	root.run.economy_state.xp = 0
	var node_id := root.run.map_state.nodes[0].node_id
	root.run.current_node_id = OptionalStringValue.new(node_id)
	root.run.map_state.current_node_id = OptionalStringValue.new(node_id)
	root.run.income_claimed_node_ids = [node_id]
	_set_win_result_with_xp_proposal(root.run, 4)

	var settlement_catalog := _settlement_catalog(bootstrap, digest)
	var settled := BattleSettlementService.new().settle(root.run, settlement_catalog)
	# The single assertion T11 must make true: a level-1 run's first add_xp proposal must not
	# be rejected as REWARD_CONFIG_INVALID. As of this writing (before the content fix) this
	# fails with exactly that code, because slice_default.tres's xp_thresholds only defines
	# levels 3..8 -- see this file's header and the first test above for the structural proof.
	assert_true(
		settled.ok,
		"a level-1 run's first add_xp proposal must not fail with REWARD_CONFIG_INVALID" +
		" once slice_default.tres's xp_thresholds covers levels 1-2 -- got %s" % (
			String(settled.error.code) if not settled.ok else "ok"
		)
	)


func _set_win_result_with_xp_proposal(run: RunState, xp_amount: int) -> void:
	var previous := run.resolution_state as BattleResultPendingResolutionState
	var result := BattleResult.new()
	result.battle_setup_hash = StringName(previous.battle_setup_hash)
	result.outcome = &"player_win"
	result.final_tick = 20
	result.survivor_instance_ids = [&"u_0000000000000001"]
	result.expedition_damage = 0
	var proposal_result := RunMutationProposal.create(
		&"once_per_node", "u/u_0000000000000001", &"effect.fixture", 0, &"add_xp", xp_amount
	)
	assert_true(proposal_result.ok)
	if proposal_result.ok:
		result.run_mutation_proposals.append(proposal_result.proposal)
	result.summary_hash = &"0000000000000000000000000000000000000000000000000000000000000000"
	var sealed := BattleResultCodecV1.new().seal(result.to_record())
	assert_true(sealed.ok)
	run.resolution_state = BattleResultPendingResolutionState.new(
		previous.battle_setup_hash, BattleResult.from_record(sealed.record)
	)


## A settlement-capable EconomyExpeditionCatalog carrying the REAL, compiled slice_default
## economy config (bootstrap.economy_catalog.config()) but re-pinned to the digest the
## fixture root actually carries, plus a minimal reward table so RewardService.generate_stage
## (called after the XP/HP adjustments succeed) has something to draw from -- mirrors
## EconomyTestFixture.settlement_catalog()'s own shape, just built from the real config.
func _settlement_catalog(
	bootstrap: BuildLabBootstrapResult, digest: String
) -> EconomyExpeditionCatalog:
	var units: Array[ShopUnitRule] = [ShopUnitRule.new(&"unit.fixture", 1, 1)]
	var nodes: Array[MapNodeRule] = []
	for kind: int in range(7):
		nodes.append(MapNodeRule.new(
			StringName("mapnode.fixture_%d" % kind), kind, _encounter_id_for_kind(kind)
		))
	var standard_candidates: Array[RewardCandidateRule] = [
		RewardCandidateRule.new(&"gold", null, 1, 3),
	]
	var tables: Array[RewardTableRule] = [
		RewardTableRule.new(&"reward.standard", standard_candidates, 3),
	]
	return EconomyExpeditionCatalog.new(
		digest, bootstrap.economy_catalog.config(), units, nodes, tables
	)


func _encounter_id_for_kind(kind: int) -> StringName:
	match kind:
		MapNodeState.NodeKind.NORMAL:
			return &"encounter.normal"
		MapNodeState.NodeKind.ELITE:
			return &"encounter.elite"
		MapNodeState.NodeKind.BOSS:
			return &"encounter.boss"
	return &""
