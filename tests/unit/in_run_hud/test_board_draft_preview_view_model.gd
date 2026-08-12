extends GutTest

## IRH-REQ-008（specs/in-run-hud）-- BoardDraftPreviewViewModel。
##
## 契約：拖曳草稿的「人口 x/y」「合不合法」「羈絆會怎麼變」三者都必須由 domain 給，
## 人口一律經 RunCommandFactory.board_validation_report()（含指揮官人口來源），
## 羈絆一律經 BattleSetupSourceCompiler.compile_trait_progress()。呈現層零公式（spec §10.3）。

const TRAIT_DUO: StringName = &"trait.duo"
const UNIT_DEF_A: StringName = &"unit.duo_a"
const UNIT_DEF_B: StringName = &"unit.duo_b"
const ECONOMY_LEVEL: int = 3
const COMMANDER_POPULATION_BONUS: int = 1
const INSTANCE_IDS: Array[String] = [
	"u_0000000000000301",
	"u_0000000000000302",
	"u_0000000000000303",
	"u_0000000000000304",
	"u_0000000000000305",
]


func test_population_matches_a_direct_validator_call_through_the_factory() -> void:
	var run := _draft_run()
	var catalog := _battle_catalog(run.content_snapshot.manifest_digest_value())
	var factory := _factory(run.content_snapshot.manifest_digest_value(), catalog)
	var controller := _controller_for(run, catalog)
	var view_model := BoardDraftPreviewViewModel.new(controller, factory, catalog)

	var placements := _placements(2)
	var bench: Array[String] = [INSTANCE_IDS[2], INSTANCE_IDS[3], INSTANCE_IDS[4]]
	var snapshot := view_model.preview(placements, bench)

	var expected_roster := controller.roster_snapshot()
	expected_roster.board = BoardState.new(placements)
	expected_roster.bench_unit_instance_ids = bench.duplicate()
	var direct := factory.board_validation_report(expected_roster, ECONOMY_LEVEL)

	assert_eq(snapshot.derived_capacity, direct.derived_capacity, "人口上限必須逐值同源")
	assert_eq(
		snapshot.derived_capacity, ECONOMY_LEVEL + COMMANDER_POPULATION_BONUS,
		"指揮官人口加成必須經 factory 的來源台帳生效"
	)
	assert_eq(snapshot.used_population, 2)
	assert_true(snapshot.valid, "草稿在上限內且指派完整時必須合法")
	assert_true(snapshot.issues.is_empty())


func test_over_capacity_draft_is_rejected_with_the_validators_named_issue() -> void:
	var run := _draft_run()
	var catalog := _battle_catalog(run.content_snapshot.manifest_digest_value())
	var factory := _factory(run.content_snapshot.manifest_digest_value(), catalog)
	var view_model := BoardDraftPreviewViewModel.new(
		_controller_for(run, catalog), factory, catalog
	)

	var empty_bench: Array[String] = []
	var snapshot := view_model.preview(_placements(5), empty_bench)
	assert_eq(snapshot.used_population, 5)
	assert_eq(snapshot.derived_capacity, 4)
	assert_false(snapshot.valid)
	assert_true(
		snapshot.issue_codes().has(BoardValidationIssue.OVER_CAPACITY),
		"超過人口上限必須以 validator 的具名碼回報"
	)


func test_draft_trait_progress_differs_from_the_committed_layout() -> void:
	var run := _draft_run()
	var catalog := _battle_catalog(run.content_snapshot.manifest_digest_value())
	var factory := _factory(run.content_snapshot.manifest_digest_value(), catalog)
	var controller := _controller_for(run, catalog)
	var view_model := BoardDraftPreviewViewModel.new(controller, factory, catalog)

	var committed := view_model.committed_preview()
	assert_eq(committed.used_population, 1, "已提交佈局只有一顆上場")
	assert_eq(committed.trait_progress.size(), 1)
	assert_eq(committed.trait_progress[0].trait_id, TRAIT_DUO)
	assert_eq(committed.trait_progress[0].distinct_count, 1)
	assert_eq(committed.trait_progress[0].active_tier, 0, "只有一個 def_id 時未達門檻")
	assert_eq(committed.trait_progress[0].next_required_count, 2)

	var bench: Array[String] = [INSTANCE_IDS[2], INSTANCE_IDS[3], INSTANCE_IDS[4]]
	var draft := view_model.preview(_placements(2), bench)
	assert_eq(draft.trait_progress[0].distinct_count, 2, "草稿加入第二個 def_id")
	assert_eq(draft.trait_progress[0].active_tier, 1, "草稿佈局下羈絆會達成第一階")
	assert_eq(draft.trait_progress[0].next_required_count, -1, "只有一階時已滿階")

	var expected_roster := controller.roster_snapshot()
	expected_roster.board = BoardState.new(_placements(2))
	expected_roster.bench_unit_instance_ids = bench.duplicate()
	var direct := BattleSetupSourceCompiler.new().compile_trait_progress(
		expected_roster, catalog
	)
	assert_eq(draft.trait_progress.size(), direct.size())
	assert_eq(draft.trait_progress[0].active_tier, direct[0].active_tier)
	assert_eq(
		draft.trait_progress[0].member_instance_ids, direct[0].member_instance_ids
	)


func test_incomplete_and_out_of_half_drafts_forward_validator_issues_verbatim() -> void:
	var run := _draft_run()
	var catalog := _battle_catalog(run.content_snapshot.manifest_digest_value())
	var factory := _factory(run.content_snapshot.manifest_digest_value(), catalog)
	var view_model := BoardDraftPreviewViewModel.new(
		_controller_for(run, catalog), factory, catalog
	)

	var wrong_half: Array[BoardPlacementState] = [
		BoardPlacementState.new(5, 0, INSTANCE_IDS[0]),
	]
	var bench: Array[String] = [
		INSTANCE_IDS[1], INSTANCE_IDS[2], INSTANCE_IDS[3], INSTANCE_IDS[4],
	]
	var snapshot := view_model.preview(wrong_half, bench)
	assert_false(snapshot.valid)
	assert_true(
		snapshot.issue_codes().has(BoardValidationIssue.WRONG_HALF),
		"越過玩家半場必須被 validator 擋下"
	)

	var partial_bench: Array[String] = [INSTANCE_IDS[1]]
	var incomplete := view_model.preview(_placements(1), partial_bench)
	assert_false(incomplete.valid)
	assert_true(
		incomplete.issue_codes().has(BoardValidationIssue.UNIT_UNASSIGNED),
		"草稿沒涵蓋全部單位時必須如實回報，不由 ViewModel 補位"
	)


func test_preview_is_read_only_for_inputs_canonical_state_and_outputs() -> void:
	var run := _draft_run()
	var catalog := _battle_catalog(run.content_snapshot.manifest_digest_value())
	var factory := _factory(run.content_snapshot.manifest_digest_value(), catalog)
	var controller := _controller_for(run, catalog)
	var view_model := BoardDraftPreviewViewModel.new(controller, factory, catalog)

	var placements := _placements(2)
	var bench: Array[String] = [INSTANCE_IDS[2], INSTANCE_IDS[3], INSTANCE_IDS[4]]
	var snapshot := view_model.preview(placements, bench)
	placements.clear()
	bench.clear()
	assert_eq(snapshot.used_population, 2, "呼叫端事後改動輸入不應影響已回傳的快照")

	var after := controller.roster_snapshot()
	assert_eq(after.board.placements.size(), 1, "預覽不得寫回 canonical 佈局")
	assert_eq(after.bench_unit_instance_ids.size(), 4)

	snapshot.derived_capacity = 99
	snapshot.trait_progress[0].distinct_count = 99
	var again := view_model.committed_preview()
	assert_eq(again.derived_capacity, 4, "改動先前回傳的快照不應影響之後的讀取")
	assert_eq(again.trait_progress[0].distinct_count, 1)


# ---------------------------------------------------------------------------
# fixtures：5 個單位（3 個 unit.duo_a、2 個 unit.duo_b），已提交佈局只有第一顆上場。
# trait.duo 門檻 2（不同 def_id）；經濟等級 3 ＋ 指揮官人口加成 1 → 人口上限 4。
# ---------------------------------------------------------------------------

func _draft_run() -> RunState:
	var run := SaveRootFixture.create_valid_root().run
	run.run_phase = RunState.RunPhase.PREPARE
	var empty_offers: Array[ShopOffer] = []
	run.economy_state = EconomyState.new(10, ECONOMY_LEVEL, 0, 0, 0, 0, empty_offers)
	var no_equipment: Array[String] = []
	var units: Array[UnitInstance] = []
	for index: int in range(INSTANCE_IDS.size()):
		var def_id := UNIT_DEF_A if index % 2 == 0 else UNIT_DEF_B
		units.append(UnitInstance.new(
			INSTANCE_IDS[index], def_id, 1, no_equipment, U64Bits.zero()
		))
	var bench: Array[String] = [
		INSTANCE_IDS[1], INSTANCE_IDS[2], INSTANCE_IDS[3], INSTANCE_IDS[4],
	]
	var no_items: Array[ItemInstanceState] = []
	var no_ids: Array[String] = []
	var relics: Array[RelicSlotState] = []
	for index: int in range(5):
		relics.append(RelicSlotState.new(index, null))
	run.roster_state = RosterState.new(
		BoardState.new(_placements(1)), bench, units, no_items, no_ids, no_ids, relics
	)
	return run


func _placements(count: int) -> Array[BoardPlacementState]:
	var result: Array[BoardPlacementState] = []
	for index: int in range(count):
		result.append(BoardPlacementState.new(0, index, INSTANCE_IDS[index]))
	return result


func _battle_catalog(manifest_digest: String) -> BattleRuleCatalog:
	var trait_rule := BattleTraitRule.new()
	trait_rule.trait_id = TRAIT_DUO
	trait_rule.trait_kind = &"faction"
	trait_rule.member_rule = &"unit"
	var threshold := BattleTraitThresholdRule.new()
	threshold.required_count = 2
	var effect_ids: Array[StringName] = [&"effect.duo_t1"]
	threshold.effect_ids = effect_ids
	var thresholds: Array[BattleTraitThresholdRule] = [threshold]
	trait_rule.thresholds = thresholds
	var units: Array[BattleUnitRule] = [
		_unit_rule(UNIT_DEF_A), _unit_rule(UNIT_DEF_B),
	]
	var traits: Array[BattleTraitRule] = [trait_rule]
	var abilities: Array[BattleAbilityRule] = []
	var effects: Array[BattleEffectRule] = []
	var encounters: Array[BattleEncounterRule] = []
	var equipment: Array[BattleEquipmentRule] = []
	var configs: Array[BattleCombatConfigRule] = []
	return BattleRuleCatalog.new(
		manifest_digest, units, traits, abilities, effects, encounters, equipment, configs
	)


func _unit_rule(unit_id: StringName) -> BattleUnitRule:
	var rule := BattleUnitRule.new()
	rule.unit_id = unit_id
	var trait_ids: Array[StringName] = [TRAIT_DUO]
	rule.trait_ids = trait_ids
	rule.base_stats = BattleUnitStatsRule.new()
	rule.base_stats.health = 100
	rule.base_stats.attack = 10
	rule.base_stats.armor = 0
	rule.base_stats.magic_resist = 0
	rule.base_stats.attack_speed_milli = 1000
	rule.base_stats.attack_range_cells = 1
	rule.base_stats.start_mana = 0
	rule.base_stats.max_mana = 50
	rule.base_stats.move_speed_milli = 1000
	rule.ai_profile = &"melee"
	rule.basic_attack_profile = &"melee"
	rule.availability = &"always"
	rule.shop_condition = &"none"
	return rule


func _factory(
	manifest_digest: String,
	battle_catalog: BattleRuleCatalog
) -> RunCommandFactory:
	var no_effects: Array[StringName] = []
	return RunCommandFactory.new(
		EconomyTestFixture.catalog(manifest_digest),
		null,
		battle_catalog,
		no_effects,
		&"commander.fixture",
		COMMANDER_POPULATION_BONUS
	)


func _controller_for(run: RunState, catalog: BattleRuleCatalog) -> RunController:
	var repository := SaveRootFixture.create_repository(FakeSaveStorage.new())
	add_child_autofree(repository)
	return ViewModelTestFixture.controller_for(run, catalog, repository)
